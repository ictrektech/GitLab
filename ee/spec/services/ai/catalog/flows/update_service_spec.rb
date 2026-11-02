# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::UpdateService, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers

  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:item) { create(:ai_catalog_item, item_type: :flow, project: project) }
  let_it_be_with_reload(:latest_released_version) do
    create(:ai_catalog_flow_version, :released, version: '1.0.0', item: item)
  end

  let_it_be_with_reload(:latest_version) { create(:ai_catalog_flow_version, version: '1.1.0', item: item) }

  let(:definition) do
    <<~YAML
      version: v1
      environment: ambient
      components:
        - name: updated_agent
          type: AgentComponent
          prompt_id: updated_prompt
          toolset:
            - gitlab_blob_search
            - grep
      routers: []
      flow:
        entry_point: updated_agent
    YAML
  end

  let(:params) do
    {
      item: item,
      name: 'New name',
      description: 'New description',
      visibility: :restricted,
      release: true,
      definition: definition
    }
  end

  let(:service) { described_class.new(project: project, current_user: user, params: params) }

  before do
    enable_ai_catalog
  end

  it_behaves_like Ai::Catalog::Items::BaseUpdateService do
    let(:item_schema_version) { Ai::Catalog::ItemVersion::FLOW_SCHEMA_VERSION }
    let(:expected_updated_definition) do
      YAML.safe_load(definition).merge('yaml_definition' => definition)
    end

    let(:expected_update_event_properties) do
      {
        label: 'flow',
        item_type: 'custom_flow',
        item_version: '1.1.0',
        item_schema_version: 'v1',
        custom_item_id: item.id,
        tools: 'gitlab_blob_search,grep',
        components: 'AgentComponent'
      }
    end

    context 'when user has permissions' do
      before_all do
        project.add_maintainer(user)
      end

      context 'when definition is provided and valid' do
        it 'updates attributes correctly' do
          execute_service

          expect(latest_version.reload.definition).to eq(expected_updated_definition)
          expect(item.reload).to have_attributes(
            name: 'New name',
            description: 'New description',
            visibility: 'restricted'
          )
        end
      end

      context 'when flow is not a flow' do
        before do
          allow(item).to receive(:flow?).and_return(false)
        end

        it_behaves_like 'an error response', 'Flow not found'
      end

      it_behaves_like 'yaml definition update service behavior'

      it 'passes the project as the container to the DuoWorkflowService client' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(container: project)
        ).and_call_original

        execute_service
      end

      context 'when the definition has an include section' do
        let_it_be(:referenced_agent) do
          create(:ai_catalog_agent, :public, project: project).tap do |agent|
            create(:ai_catalog_agent_version, :released, item: agent, version: '1.2.0')
          end
        end

        let(:definition) do
          super() + <<~YAML
            include:
              - source: ai-catalog
                item_type: agent
                item_id: "#{referenced_agent.id}"
                version: "1.2.0"
          YAML
        end

        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?)
            .with(user, :read_ai_catalog_item, referenced_agent).and_return(true)
        end

        it 'updates the definition with the include entries' do
          expect(execute_service).to be_success

          expect(latest_version.reload.definition['include']).to contain_exactly(
            {
              'source' => 'ai-catalog',
              'item_type' => 'agent',
              'item_id' => referenced_agent.id.to_s,
              'version' => '1.2.0'
            }
          )
        end

        it 'records a dependency row pinning the referenced version' do
          expect(execute_service).to be_success

          dependency = item.reload.latest_version.dependencies.sole

          expect(dependency.dependency_id).to eq(referenced_agent.id)
          expect(dependency.dependency_version.version).to eq('1.2.0')
        end

        context 'when the referenced agent is deleted before its dependency row is written' do
          before do
            allow(Ai::Catalog::ItemVersionDependency).to receive(:bulk_insert!)
              .and_raise(ActiveRecord::InvalidForeignKey)
          end

          it_behaves_like 'an error response', 'Referenced agents changed while the flow was saved. Try again.'

          it 'keeps the previous definition' do
            expect { execute_service }.not_to change { latest_version.reload.definition }
          end
        end

        context 'when ai_catalog_flow_agent_references is disabled' do
          before do
            stub_feature_flags(ai_catalog_flow_agent_references: false)
          end

          it_behaves_like 'an error response', 'Referencing AI Catalog items with include is not available'

          it 'does not call DWS validation' do
            expect(Ai::DuoWorkflow::DuoWorkflowService::Client).not_to receive(:new)

            execute_service
          end
        end
      end

      context 'when only the visibility changes and the latest version references a private agent' do
        let_it_be(:private_agent) do
          create(:ai_catalog_agent, :private, project: project).tap do |agent|
            create(:ai_catalog_agent_version, :released, item: agent, version: '1.0.0')
          end
        end

        let(:params) { { item: item, visibility: :public } }
        let(:private_agent_include) do
          { 'include' => [{ 'source' => 'ai-catalog', 'item_type' => 'agent',
                            'item_id' => private_agent.id.to_s, 'version' => '1.0.0' }] }
        end

        before do
          latest_version.update!(definition: latest_version.definition.merge(private_agent_include))
        end

        it 'refuses to make the flow public even though the released version has no include' do
          response = execute_service

          expect(response).to be_error
          expect(response.message.first).to include('must be at least as visible as the flow')
          expect(item.reload).to be_visibility_private
        end

        context 'when the visibility is lowered' do
          let(:params) { { item: item, visibility: :private } }

          before do
            item.update!(visibility: :restricted)
          end

          it 'saves without resolving the references' do
            expect(Ai::Catalog::Flows::ReferenceResolver).not_to receive(:new)

            expect(execute_service).to be_success
            expect(item.reload).to be_visibility_private
          end
        end

        context 'when the visibility is blank' do
          let(:params) { { item: item, visibility: nil } }

          it_behaves_like 'an error response', 'Visibility cannot be blank'
        end

        context 'when the flow has no released version' do
          let_it_be_with_reload(:draft_only_item) do
            create(:ai_catalog_item, item_type: :flow, project: project, visibility: :private)
          end

          let_it_be_with_reload(:draft_only_version) do
            create(:ai_catalog_flow_version, :draft, version: '1.0.0', item: draft_only_item)
          end

          let(:params) { { item: draft_only_item, visibility: :public } }

          before do
            draft_only_version.update!(definition: draft_only_version.definition.merge(private_agent_include))
          end

          it 'refuses to make the flow public' do
            response = execute_service

            expect(response).to be_error
            expect(response.message.first).to include('must be at least as visible as the flow')
            expect(draft_only_item.reload).to be_visibility_private
          end
        end
      end

      context 'when the include section is removed from a draft version' do
        let_it_be(:previous_dependency) do
          create(:ai_catalog_item_version_dependency, ai_catalog_item_version: latest_version)
        end

        it 'deletes the dependency rows the version no longer references' do
          expect(execute_service).to be_success

          expect(Ai::Catalog::ItemVersionDependency.for_item_version(latest_version)).to be_empty
        end

        context 'when ai_catalog_flow_agent_references is disabled' do
          before do
            stub_feature_flags(ai_catalog_flow_agent_references: false)
          end

          it 'still deletes the dependency rows' do
            expect(execute_service).to be_success

            expect(Ai::Catalog::ItemVersionDependency.for_item_version(latest_version)).to be_empty
          end
        end
      end

      context 'when DWS returns validation errors' do
        before do
          allow_next_instance_of(Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
            allow(client).to receive(:validate_flow_config)
              .and_return(ServiceResponse.error(message: ['Component missing input variables: goal']))
          end
        end

        it_behaves_like 'an error response', ['Component missing input variables: goal']
      end

      context 'when DWS is unavailable' do
        before do
          allow_next_instance_of(Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
            allow(client).to receive(:validate_flow_config)
              .and_return(
                ServiceResponse.error(
                  message: 'Unable to validate flow configuration. Duo Workflow Service is currently unavailable.'
                )
              )
          end
        end

        it_behaves_like 'an error response',
          ['Unable to validate flow configuration. Duo Workflow Service is currently unavailable.']
      end

      it_behaves_like 'rejects an oversized YAML definition before validation' do
        let(:oversized_definition) { "#{definition}# #{'a' * 40.kilobytes}\n" }

        it 'does not call DWS' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).not_to receive(:new)

          execute_service
        end
      end

      context 'when updating without a definition change' do
        let(:params) { { item: item, name: 'New name' } }

        it 'does not call DWS validation and succeeds' do
          dws_client = instance_double(Ai::DuoWorkflow::DuoWorkflowService::Client)
          allow(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).and_return(dws_client)
          allow(dws_client).to receive(:validate_flow_config)

          result = execute_service

          expect(result).to be_success
          expect(dws_client).not_to have_received(:validate_flow_config)
        end
      end
    end
  end

  describe 'audit events' do
    let(:params) { super().except(:visibility).merge(public: true) }
    let(:execute_service) do
      service.execute
    end

    before_all do
      project.add_maintainer(user)
    end

    it 'creates audit events for the changes', :aggregate_failures do
      expect { execute_service }.to change { AuditEventReader.count }.by(3)

      audit_events = AuditEventReader.last(3)

      expect(audit_events[0]).to have_attributes(
        author: user,
        entity_type: 'Project',
        entity_id: project.id,
        target_details: "#{item.name} (ID: #{item.id})"
      )
      expect(audit_events[0].details).to include(
        custom_message: "Updated AI flow: Added tools: [gitlab_blob_search, grep], " \
          "Entry point changed from 'main_agent' to 'updated_agent', " \
          "Added components: [updated_agent], Removed components: [main_agent]",
        event_name: "update_ai_catalog_flow",
        target_type: "Ai::Catalog::Item"
      )

      expect(audit_events[1]).to have_attributes(
        author: user,
        entity_type: 'Project',
        entity_id: project.id,
        target_details: "#{item.name} (ID: #{item.id})"
      )
      expect(audit_events[1].details).to include(
        custom_message: 'Made AI flow public'
      )

      expect(audit_events[2]).to have_attributes(
        author: user,
        entity_type: 'Project',
        entity_id: project.id
      )
      expect(audit_events[2].details).to include(
        custom_message: 'Released version 1.1.0 of AI flow'
      )
    end

    context 'when update fails' do
      before do
        allow(item).to receive(:save).and_return(false)
        item.errors.add(:base, 'Item cannot be updated')
      end

      it 'does not create an audit event' do
        expect { execute_service }.not_to change { AuditEventReader.count }
      end
    end
  end
end
