# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::UpsertService, feature_category: :ai_agents do
  let_it_be(:namespace) { create(:group) }
  let_it_be(:current_user) { create(:user, owner_of: namespace) }

  let(:rule) do
    Ai::ToolRule.find_or_initialize_for_namespace(
      namespace_id: namespace.id,
      tool_name: 'create_issue'
    )
  end

  subject(:service) { described_class.new(rule, current_user, params) }

  describe '#execute' do
    before do
      allow(Gitlab::Audit::Auditor).to receive(:audit)
    end

    context 'when the rule is new' do
      let(:params) { { web_access: :allow } }

      it 'returns a success response' do
        expect(service.execute).to be_success
      end

      it 'persists the rule' do
        expect { service.execute }.to change { Ai::ToolRule.count }.by(1)
      end

      it 'returns the rule as payload' do
        response = service.execute
        expect(response.payload).to eq(rule)
        expect(response.payload.web_access).to eq('allow')
      end

      it 'emits a created audit event' do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'ai_tool_rule_created',
            author: current_user,
            scope: namespace,
            target: rule,
            message: "Created tool rule for create_issue: web_access=allow, local_access=, background_access="
          )
        )

        service.execute
      end
    end

    context 'when background_access is set' do
      let(:params) { { background_access: :deny } }

      it 'persists background_access and records it in the created audit message', :aggregate_failures do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(message: a_string_including('background_access=deny'))
        )

        expect(service.execute).to be_success
        expect(rule.reload.background_access).to eq('deny')
      end
    end

    context 'when the rule already exists' do
      let(:existing_rule) do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow)
      end

      let(:rule) { existing_rule }
      let(:params) { { web_access: :deny } }

      it 'updates the existing rule without creating a new one' do
        existing_rule

        expect { service.execute }.not_to change { Ai::ToolRule.count }
      end

      it 'returns the updated rule' do
        response = service.execute

        expect(response.payload.web_access).to eq('deny')
      end

      it 'emits an updated audit event with correct additional_details' do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'ai_tool_rule_updated',
            author: current_user,
            scope: namespace,
            target: existing_rule,
            message: "Updated tool rule for create_issue: web_access allow->deny",
            additional_details: hash_including(
              tool_name: 'create_issue',
              web_access_from: 'allow',
              web_access_to: 'deny'
            )
          )
        )

        service.execute
      end

      it 'does not include unchanged fields in additional_details' do
        service.execute

        expect(Gitlab::Audit::Auditor).to have_received(:audit).with(
          hash_including(
            additional_details: satisfy { |d|
              !d.key?(:local_access_from) && !d.key?(:local_access_to)
            }
          )
        )
      end
    end

    context 'when an existing rule changes background_access' do
      let(:existing_rule) do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', background_access: :allow)
      end

      let(:rule) { existing_rule }
      let(:params) { { background_access: :deny } }

      it 'persists the change' do
        expect { service.execute }.to change { existing_rule.reload.background_access }.from('allow').to('deny')
      end

      it 'records background_access in the updated audit message and details', :aggregate_failures do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'ai_tool_rule_updated',
            message: 'Updated tool rule for create_issue: background_access allow->deny',
            additional_details: hash_including(
              background_access_from: 'allow',
              background_access_to: 'deny'
            )
          )
        )

        service.execute
      end
    end

    context 'when both web_access and local_access change' do
      let(:existing_rule) do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow, local_access: :allow)
      end

      let(:rule) { existing_rule }
      let(:params) { { web_access: :deny, local_access: :ask } }

      it 'includes both fields in the audit message' do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'ai_tool_rule_updated',
            message: "Updated tool rule for create_issue: web_access allow->deny, local_access allow->ask"
          )
        )

        service.execute
      end
    end

    context 'when no fields change' do
      let(:existing_rule) do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow)
      end

      let(:rule) { existing_rule }
      let(:params) { { web_access: :allow } }

      it 'does not emit an updated audit event' do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)

        service.execute
      end
    end

    context 'when only web_access is provided' do
      let(:params) { { web_access: :ask, local_access: nil } }

      it 'only updates web_access' do
        service.execute
        expect(rule.web_access).to eq('ask')
        expect(rule.local_access).to be_nil
      end
    end

    context 'when only local_access is provided' do
      let(:params) { { web_access: nil, local_access: :deny } }

      it 'only updates local_access' do
        service.execute
        expect(rule.local_access).to eq('deny')
        expect(rule.web_access).to be_nil
      end
    end

    context 'when unsetting access types' do
      let(:existing_rule) do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :deny, local_access: :ask)
      end

      let(:rule) { existing_rule }

      context 'when another access type stays set' do
        let(:params) { { unset_access_types: [:web_access] } }

        it 'clears the access type and keeps the rule', :aggregate_failures do
          expect(service.execute).to be_success
          expect(existing_rule.reload).to have_attributes(web_access: nil, local_access: 'ask')
        end

        it 'emits an updated audit event' do
          expect(Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              name: 'ai_tool_rule_updated',
              message: 'Updated tool rule for create_issue: web_access deny->unset'
            )
          )

          service.execute
        end
      end

      context 'when every access type ends up unset' do
        let(:params) { { unset_access_types: [:web_access, :local_access] } }

        it 'deletes the rule', :aggregate_failures do
          existing_rule

          expect { expect(service.execute).to be_success }.to change { Ai::ToolRule.count }.by(-1)
        end

        it 'emits an updated audit event with every cleared access type' do
          expect(Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              name: 'ai_tool_rule_updated',
              target: existing_rule,
              message: 'Updated tool rule for create_issue: web_access deny->unset, local_access ask->unset',
              additional_details: hash_including(
                web_access_from: 'deny',
                web_access_to: nil,
                local_access_from: 'ask',
                local_access_to: nil
              )
            )
          )

          service.execute
        end
      end

      context 'when a value is set and the rest is unset' do
        let(:params) { { local_access: :deny, unset_access_types: [:web_access] } }

        it 'applies both', :aggregate_failures do
          expect(service.execute).to be_success
          expect(existing_rule.reload).to have_attributes(web_access: nil, local_access: 'deny')
        end
      end

      context 'when the same access type is set and unset' do
        let(:params) { { web_access: :allow, unset_access_types: [:web_access] } }

        it 'returns an error without changing the rule', :aggregate_failures do
          response = service.execute

          expect(response).to be_error
          expect(response.message).to eq('An access type cannot be both set and unset')
          expect(existing_rule.reload.web_access).to eq('deny')
        end
      end

      context 'when an unset name is not an access type' do
        let(:params) { { unset_access_types: [:project_id] } }

        it 'returns an error without changing the rule', :aggregate_failures do
          response = service.execute

          expect(response).to be_error
          expect(response.message).to eq('Only access types can be unset')
          expect(existing_rule.reload.project_id).to be_nil
        end
      end

      context 'when the rule does not exist yet' do
        let(:rule) do
          Ai::ToolRule.find_or_initialize_for_namespace(namespace_id: namespace.id, tool_name: 'create_issue')
        end

        let(:params) { { unset_access_types: [:web_access] } }

        it 'succeeds without creating a rule or an audit event', :aggregate_failures do
          expect(Gitlab::Audit::Auditor).not_to receive(:audit)

          expect { expect(service.execute).to be_success }.not_to change { Ai::ToolRule.count }
        end
      end
    end

    context 'when the rule fails to save' do
      let(:params) { { web_access: :allow } }

      before do
        allow(rule).to receive(:save).and_return(false)
        allow(rule.errors).to receive(:full_messages).and_return(['web_access is invalid'])
      end

      it 'returns an error response' do
        expect(service.execute).to be_error
      end

      it 'includes the validation errors' do
        expect(service.execute.message).to include('web_access is invalid')
      end

      it 'does not emit an audit event' do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)

        service.execute
      end
    end

    context 'when user is not authorized' do
      let(:params) { { web_access: :allow } }
      let(:current_user) { create(:user) }

      it 'returns an error response' do
        expect(service.execute).to be_error
      end

      it 'does not persist the rule' do
        expect { service.execute }.not_to change { Ai::ToolRule.count }
      end

      it 'does not emit a tool rule audit event' do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit).with(
          hash_including(name: a_string_starting_with('ai_tool_rule'))
        )

        service.execute
      end
    end

    context 'when updating a project-scoped rule' do
      let_it_be(:project) { create(:project, namespace: namespace) }

      let(:rule) do
        Ai::ToolRule.find_or_initialize_for_namespace(
          namespace_id: namespace.id,
          tool_name: 'create_issue',
          project_id: project.id
        )
      end

      let(:params) { { web_access: :deny } }

      before do
        allow(project).to receive(:duo_features_enabled).and_return(true)
      end

      context 'when user is a maintainer' do
        let_it_be(:maintainer) { create(:user, maintainer_of: project) }
        let(:current_user) { maintainer }

        it 'is authorized and saves the rule', :aggregate_failures do
          expect(service.execute).to be_success
          expect(Ai::ToolRule.find_by(namespace_id: namespace.id, project_id: project.id,
            tool_name: 'create_issue')).to be_present
        end
      end

      context 'when user is a developer' do
        let_it_be(:developer) { create(:user, developer_of: project) }
        let(:current_user) { developer }

        it 'returns an error response' do
          expect(service.execute).to be_error
        end
      end
    end
  end
end
