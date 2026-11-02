# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::UpdateService, feature_category: :dap_triggers do
  include Ai::Catalog::TestHelpers
  include AfterNextHelpers

  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:different_group) { create(:group) }
  let_it_be(:human_user) { create(:user, maintainer_of: project) }
  let_it_be(:composite_identity_enforced) { false }
  # reload: true because a passing example flips composite_identity_enforced on
  # this account, and the dirty in-memory record then fails trigger validation.
  let_it_be(:service_account_provisioned_by_group, reload: true) do
    create(:service_account, developer_of: project, provisioned_by_group: project.group,
      composite_identity_enforced: composite_identity_enforced)
  end

  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let(:current_user) { human_user }
  let(:service_account) { service_account_provisioned_by_group }

  let(:event_types) { [Ai::FlowTrigger::EVENT_TYPES[:mention]] }
  let(:params) { { user_id: service_account.id, event_types: event_types } }
  let(:trigger) { create(:ai_flow_trigger, project: project, user: service_account) }
  let(:service) { described_class.new(project: project, current_user: current_user, trigger: trigger) }

  before do
    stub_ee_application_setting(duo_features_enabled: true)
    allow(Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
    stub_validate_config_service
  end

  describe '#execute' do
    it 'updates a flow trigger' do
      response = service.execute(params)
      expect(response).to be_success
      flow_trigger = response.payload

      expect(flow_trigger).to be_persisted
      expect(flow_trigger.user).to eq(service_account)
      expect(flow_trigger.event_types).to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
      expect(flow_trigger.project).to eq(project)
      expect(service_account.reload.composite_identity_enforced).to be(true)
    end

    it 'does not validate the flow configuration for a config_path trigger' do
      expect(::Ai::Catalog::Items::ValidateConfigService).not_to receive(:new)

      response = service.execute(event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention],
        Ai::FlowTrigger::EVENT_TYPES[:assign]])
      expect(response).to be_success
    end

    it 'emits a flow_trigger_updated audit event on success' do
      expect { service.execute(params) }.to change { AuditEventReader.count }.by(1)

      audit_event = AuditEventReader.last

      expect(audit_event).to have_attributes(
        author: current_user,
        entity_type: 'Project',
        entity_id: project.id,
        target_details: "#{trigger.description} (ID: #{trigger.id})"
      )
      expect(audit_event.details).to include(
        event_name: 'flow_trigger_updated',
        target_type: 'Ai::FlowTrigger'
      )
    end

    context 'with on-finish settings' do
      let(:filter) do
        {
          'work_item' => {
            'rules' => [
              { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
              { 'field' => 'status.name', 'operator' => 'in', 'value' => ['Planning'] }
            ]
          }
        }
      end

      let(:event_types) { [Ai::FlowTrigger::EVENT_TYPES[:work_item]] }
      let(:trigger) do
        create(:ai_flow_trigger, project: project, user: service_account, event_types: event_types, filter: filter,
          status_on_finish: 'Ready for development')
      end

      it 'records the old and new on-finish settings in the audit event' do
        expect(service.execute(params.merge(status_on_finish: 'In review', ready_merge_requests_on_finish: true)))
          .to be_success

        expect(AuditEventReader.last.details[:on_finish_settings]).to eq(
          'status_on_finish' => { 'from' => 'Ready for development', 'to' => 'In review' },
          'ready_merge_requests_on_finish' => { 'from' => false, 'to' => true }
        )
      end

      it 'records on-finish settings that are turned off' do
        expect(service.execute(params.merge(status_on_finish: nil))).to be_success

        expect(AuditEventReader.last.details[:on_finish_settings]).to eq(
          'status_on_finish' => { 'from' => 'Ready for development', 'to' => nil }
        )
      end

      it 'records no on-finish settings when they do not change' do
        expect(service.execute(params)).to be_success

        expect(AuditEventReader.last.details).not_to have_key(:on_finish_settings)
      end

      it 'records no diff details when nothing audited changes', :aggregate_failures do
        expect(service.execute(params)).to be_success

        details = AuditEventReader.last.details
        expect(details).not_to have_key(:on_finish_settings)
        expect(details).not_to have_key(:flow)
        expect(details).not_to have_key(:schedule)
        expect(details).not_to have_key(:active)
        expect(details).not_to have_key(:service_account)
      end

      it 'records no schedule when the filter changes outside the scheduled key', :aggregate_failures do
        other_rules = [
          { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
          { 'field' => 'status.name', 'operator' => 'in', 'value' => ['In progress'] }
        ]

        expect(service.execute(params.merge(filter: { 'work_item' => { 'rules' => other_rules } }))).to be_success

        expect(AuditEventReader.last.details).not_to have_key(:schedule)
      end
    end

    it 'records an active toggle in the audit event', :aggregate_failures do
      expect(service.execute(params.merge(active: false))).to be_success

      expect(AuditEventReader.last.details[:active]).to eq('from' => true, 'to' => false)
    end

    context 'when the service account changes' do
      let_it_be(:new_service_account) do
        create(:service_account, developer_of: project, provisioned_by_group: project.group)
      end

      it 'records the old and new account in the audit event', :aggregate_failures do
        expect(service.execute(params.merge(user_id: new_service_account.id))).to be_success

        expect(AuditEventReader.last.details[:service_account]).to eq(
          'from' => { 'id' => service_account.id, 'username' => service_account.username },
          'to' => { 'id' => new_service_account.id, 'username' => new_service_account.username }
        )
      end
    end

    it 'does not emit an audit event when update fails' do
      invalid_params = params.merge(event_types: [99])
      expect { service.execute(invalid_params) }.not_to change { AuditEventReader.count }
    end

    context 'when the trigger is scheduled with schedule config' do
      let_it_be(:scheduled_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }

      let(:trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: nil,
          config_path: nil,
          ai_catalog_item_consumer: scheduled_consumer,
          autonomous_service_account: create(:service_account, composite_identity_enforced: false),
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          filter: { 'scheduled' => { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14 } })
      end

      let!(:schedule) { create(:ai_flow_schedule, flow_trigger: trigger) }

      before_all do
        project.add_developer(scheduled_consumer.active_service_account)
      end

      it 'updates the flow schedule when the schedule config changes' do
        params = { filter: { 'scheduled' => { 'frequency' => 'HOURLY', 'minute' => 15 } } }

        response = service.execute(params)

        expect(response).to be_success
        expect(schedule.reload.cron).to eq('15 * * * *')
      end

      it 'records the old and new schedule in the audit event', :aggregate_failures do
        params = { filter: { 'scheduled' => { 'frequency' => 'HOURLY', 'minute' => 15 } } }

        expect(service.execute(params)).to be_success

        expect(AuditEventReader.last.details[:schedule]).to eq(
          'from' => { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14 },
          'to' => { 'frequency' => 'HOURLY', 'minute' => 15 }
        )
      end

      it 'removes the flow schedule when the scheduled event type is dropped' do
        params = { ai_catalog_item_consumer_id: scheduled_consumer.id,
                   event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]], filter: {} }

        expect { service.execute(params) }.to change { Ai::FlowSchedule.count }.by(-1)
      end

      it 'records the hand-back to the shared account when autonomous events are dropped',
        :aggregate_failures do
        dedicated_account = trigger.autonomous_service_account
        shared_account = scheduled_consumer.active_service_account
        params = { ai_catalog_item_consumer_id: scheduled_consumer.id,
                   event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]], filter: {} }

        expect(service.execute(params)).to be_success

        expect(AuditEventReader.last.details[:service_account]).to eq(
          'from' => { 'id' => dedicated_account.id, 'username' => dedicated_account.username },
          'to' => { 'id' => shared_account.id, 'username' => shared_account.username }
        )
      end

      context 'when materializing the flow schedule fails' do
        before do
          allow_next_instance_of(::Ai::FlowSchedules::SyncFromTriggerService) do |sync_service|
            allow(sync_service).to receive(:execute).and_return(ServiceResponse.error(message: 'sync failed'))
          end
        end

        it 'still updates the flow trigger and logs the sync error' do
          allow(Gitlab::AppLogger).to receive(:error)

          params = { filter: { 'scheduled' => { 'frequency' => 'HOURLY', 'minute' => 15 } } }
          response = service.execute(params)

          expect(response).to be_success
          expect(Gitlab::AppLogger).to have_received(:error).with(
            hash_including(
              message: 'Failed to sync the flow schedule for the flow trigger',
              error_message: 'sync failed'
            )
          )
        end
      end
    end

    context 'when changing a gated attribute of a scheduled trigger' do
      let_it_be(:scheduled_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }
      let_it_be(:other_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }
      let_it_be(:dedicated_account) { create(:service_account, composite_identity_enforced: false) }
      let_it_be(:owner_user) { create(:user, owner_of: project) }

      let_it_be(:custom_role) do
        create(:member_role, :developer, :admin_ai_catalog_item_consumer, namespace: project.group)
      end

      let_it_be(:custom_role_user) { create(:user) }
      let_it_be(:custom_role_membership) do
        create(:project_member, :developer, member_role: custom_role, user: custom_role_user, project: project)
      end

      let(:gated_attributes) { 'Flow' }

      let(:rank_error) do
        "#{gated_attributes} cannot be changed on a scheduled trigger that runs with more permissions " \
          'than your own'
      end

      let(:manage_error) do
        "#{gated_attributes} cannot be changed on a scheduled trigger unless you can manage the service " \
          'account it runs as'
      end

      let(:account_access_level) { Gitlab::Access::MAINTAINER }
      let(:params) { { ai_catalog_item_consumer_id: other_consumer.id } }
      let(:scheduled_filter) { { 'scheduled' => { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14 } } }

      let(:trigger) do
        create(:ai_flow_trigger, :autonomous,
          project: project,
          ai_catalog_item_consumer: scheduled_consumer,
          autonomous_service_account: dedicated_account,
          filter: scheduled_filter)
      end

      before_all do
        project.add_developer(scheduled_consumer.active_service_account)
        project.add_developer(other_consumer.active_service_account)
      end

      before do
        stub_licensed_features(custom_roles: true)
        create(:project_member, access_level: account_access_level, user: dedicated_account, project: project)
        project.team.purge_member_access_cache_for_user_id(dedicated_account.id)
      end

      context 'when the editor ranks below the dedicated account' do
        let(:current_user) { custom_role_user }

        it 'refuses and leaves the trigger and the account untouched' do
          response = service.execute(params)

          expect(response).to be_error
          expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
          expect(response.message).to eq(rank_error)
          expect(trigger.reload.ai_catalog_item_consumer).to eq(scheduled_consumer)
          expect(project.member(dedicated_account).access_level).to eq(Gitlab::Access::MAINTAINER)
        end

        it 'refuses detaching the flow when explicitly set to nil' do
          response = service.execute(ai_catalog_item_consumer_id: nil)

          expect(response).to be_error
          expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
          expect(response.message).to eq(rank_error)
          expect(trigger.reload.ai_catalog_item_consumer).to eq(scheduled_consumer)
        end

        context 'with a param the trigger carries no attribute for' do
          let(:gated_attributes) { 'Unrecognized param' }

          it 'refuses rather than treating the unknown param as safe' do
            response = service.execute(unrecognized_param: true)

            expect(response).to be_error
            expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
            expect(response.message).to eq(rank_error)
          end
        end

        it 'allows an edit that repeats the flow it already points at' do
          response = service.execute(ai_catalog_item_consumer_id: scheduled_consumer.id)

          expect(response).to be_success
        end

        it 'reads a string id that matches the stored one as no change' do
          response = service.execute(ai_catalog_item_consumer_id: scheduled_consumer.id.to_s)

          expect(response).to be_success
        end

        context 'with an ungated attribute' do
          where(:attribute, :value) do
            [
              [:filter, { 'scheduled' => { 'frequency' => 'HOURLY', 'minute' => 15 } }],
              [:description, 'a renamed trigger'],
              [:active, false],
              [:goals, { 'scheduled' => 'triage the backlog' }]
            ]
          end

          with_them do
            it 'allows the edit and keeps it', :aggregate_failures do
              expect(service.execute(attribute => value)).to be_success
              expect(trigger.reload.public_send(attribute)).to eq(value)
            end
          end
        end

        context 'with a config path' do
          let(:gated_attributes) { 'External agent' }

          it 'refuses repointing the trigger at a repository config', :aggregate_failures do
            response = service.execute(config_path: 'evil/config.yml')

            expect(response).to be_error
            expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
            expect(response.message).to eq(rank_error)
            expect(trigger.reload.config_path).to be_nil
          end
        end

        context 'with more than one gated param' do
          let(:gated_attributes) { 'Flow and External agent' }

          it 'names every refused attribute and leaves the ungated one out', :aggregate_failures do
            response = service.execute(
              description: 'a renamed trigger',
              config_path: 'evil/config.yml',
              ai_catalog_item_consumer_id: nil
            )

            expect(response).to be_error
            expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
            expect(response.message).to eq(rank_error)
            expect(trigger.reload.ai_catalog_item_consumer).to eq(scheduled_consumer)
          end
        end

        context 'when the edit also drops the autonomous event types' do
          let(:params) do
            {
              ai_catalog_item_consumer_id: other_consumer.id,
              event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]],
              filter: {}
            }
          end

          it 'changes the flow and gives the dedicated account up' do
            response = service.execute(params)

            expect(response).to be_success
            expect(trigger.reload.ai_catalog_item_consumer).to eq(other_consumer)
            expect(trigger.autonomous_service_account).to be_nil
            expect(project.member(dedicated_account)).to be_nil
          end
        end

        context 'when the trigger has no dedicated account yet' do
          let(:trigger) do
            create(:ai_flow_trigger, :for_catalog_consumer,
              project: project,
              ai_catalog_item_consumer: scheduled_consumer)
          end

          let(:params) do
            {
              ai_catalog_item_consumer_id: other_consumer.id,
              event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
              filter: scheduled_filter
            }
          end

          it 'leaves the refusal to provisioning rather than the privilege gate' do
            response = service.execute(params)

            expect(response).to be_error
            expect(response.reason).to eq(
              ::Ai::FlowTriggers::ProvisionAutonomousServiceAccountService::ERROR_REASON_NOT_PROVISIONED
            )
          end
        end
      end

      context "when the editor matches the account's role but cannot invite members" do
        let(:current_user) { custom_role_user }
        let(:account_access_level) { Gitlab::Access::DEVELOPER }

        it 'refuses and names the membership permission, not the rank' do
          response = service.execute(params)

          expect(response).to be_error
          expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
          expect(response.message).to eq(manage_error)
          expect(trigger.reload.ai_catalog_item_consumer).to eq(scheduled_consumer)
        end
      end

      context 'when the account holds a role the editor cannot assign at any rank' do
        let(:account_access_level) { Gitlab::Access::PLANNER }

        it 'refuses a Maintainer editor' do
          response = service.execute(params)

          expect(response).to be_error
          expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
          expect(response.message).to eq(rank_error)
          expect(trigger.reload.ai_catalog_item_consumer).to eq(scheduled_consumer)
        end
      end

      context 'when the editor can assign the role the account holds' do
        where(:editor, :account_access_level) do
          [
            [ref(:human_user), Gitlab::Access::MAINTAINER],
            [ref(:human_user), Gitlab::Access::DEVELOPER],
            [ref(:owner_user), Gitlab::Access::PLANNER]
          ]
        end

        with_them do
          let(:current_user) { editor }

          it 'changes the flow and re-levels the account to the new flow' do
            response = service.execute(params)

            expect(response).to be_success
            expect(trigger.reload.ai_catalog_item_consumer).to eq(other_consumer)
            expect(project.member(dedicated_account).access_level).to eq(Gitlab::Access::DEVELOPER)
          end
        end
      end

      context 'when the dedicated account holds no membership' do
        let(:current_user) { custom_role_user }

        before do
          project.members.find_by(user: dedicated_account).destroy!
          project.project_members.reset
          project.team.purge_member_access_cache_for_user_id(dedicated_account.id)
        end

        it 'changes the flow, since there is no access to inherit' do
          response = service.execute(params)

          expect(response).to be_success
          expect(trigger.reload.ai_catalog_item_consumer).to eq(other_consumer)
        end
      end
    end

    context 'when using invalid params' do
      let(:event_types) { [99] }

      it 'returns the error' do
        response = service.execute(params)
        expect(response).not_to be_success
        expect(response.message).to include('invalid event types: 99')
      end
    end

    context 'when the current_user is not a maintainer of the project' do
      let(:current_user) { create(:user, developer_of: project) }

      it 'returns an error and does not create the flow trigger' do
        response = service.execute(params)
        expect(response).not_to be_success
      end
    end

    context 'when the provisioning group is not the root ancestor of the project' do
      let(:service_account) { create(:service_account, developer_of: project, provisioned_by_group: different_group) }

      it 'returns an error and does not create the flow trigger' do
        response = service.execute(params)
        expect(response).not_to be_success
      end
    end

    context 'when updating catalog item configuration' do
      let_it_be(:item_consumer1) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }
      let_it_be(:item_consumer2) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }

      context 'when switching from config_path to catalog item' do
        let(:trigger) do
          create(:ai_flow_trigger, project: project, user: service_account, config_path: 'path/config.yml')
        end

        let(:params) do
          {
            ai_catalog_item_consumer_id: item_consumer1.id,
            config_path: nil
          }
        end

        it 'updates to use catalog item' do
          response = service.execute(params)
          flow_trigger = response.payload

          expect(response).to be_success
          expect(flow_trigger.ai_catalog_item_consumer).to eq(item_consumer1)
          expect(flow_trigger.config_path).to be_nil
        end

        it 'records the flow source change in the audit event', :aggregate_failures do
          expect(service.execute(params)).to be_success

          expect(AuditEventReader.last.details[:flow]).to eq(
            'from' => { 'type' => 'config_path', 'config_path' => 'path/config.yml' },
            'to' => {
              'type' => 'ai_catalog_item',
              'ai_catalog_item_consumer_id' => item_consumer1.id,
              'name' => item_consumer1.item.name
            }
          )
        end

        it 'records the hand-over to the catalog item account', :aggregate_failures do
          expect(service.execute(params)).to be_success

          account = item_consumer1.active_service_account
          expect(AuditEventReader.last.details[:service_account]).to eq(
            'from' => { 'id' => service_account.id, 'username' => service_account.username },
            'to' => { 'id' => account.id, 'username' => account.username }
          )
        end

        context 'when ai_catalog_create_third_party_flows is disabled' do
          before do
            stub_feature_flags(ai_catalog_create_third_party_flows: false)
          end

          it 'does not return an error' do
            response = service.execute(params)

            expect(response).to be_success
          end
        end
      end

      context 'when switching from catalog item to config_path' do
        let(:trigger) do
          create(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer1)
        end

        let(:params) do
          {
            user_id: service_account.id,
            config_path: 'new/path/config.yml',
            ai_catalog_item_consumer_id: nil
          }
        end

        it 'updates to use config_path' do
          response = service.execute(params)
          expect(response).to be_success
          flow_trigger = response.payload

          expect(flow_trigger.config_path).to eq('new/path/config.yml')
          expect(flow_trigger.ai_catalog_item_consumer).to be_nil
        end

        it 'records the flow and account change back to a config path', :aggregate_failures do
          expect(service.execute(params)).to be_success

          details = AuditEventReader.last.details
          expect(details[:flow]).to eq(
            'from' => {
              'type' => 'ai_catalog_item',
              'ai_catalog_item_consumer_id' => item_consumer1.id,
              'name' => item_consumer1.item.name
            },
            'to' => { 'type' => 'config_path', 'config_path' => 'new/path/config.yml' }
          )
          account = item_consumer1.active_service_account
          expect(details[:service_account]).to eq(
            'from' => { 'id' => account.id, 'username' => account.username },
            'to' => { 'id' => service_account.id, 'username' => service_account.username }
          )
        end

        context 'when ai_catalog_create_third_party_flows is disabled' do
          before do
            stub_feature_flags(ai_catalog_create_third_party_flows: false)
          end

          it 'returns an error' do
            response = service.execute(params)

            expect(response).to be_error
            expect(response.message).to include('You have insufficient permissions')
            expect(response.reason).to eq(:unauthorized)
          end
        end
      end

      context 'when updating catalog item' do
        let_it_be_with_reload(:trigger) do
          create(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer1,
            event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign]]
          )
        end

        it 'does not validate the flow configuration when event types are unchanged' do
          expect(::Ai::Catalog::Items::ValidateConfigService).not_to receive(:new)

          response = service.execute(description: 'updated description')
          expect(response).to be_success
        end

        it 'does not validate the flow configuration when event types are only removed' do
          expect(::Ai::Catalog::Items::ValidateConfigService).not_to receive(:new)

          response = service.execute(event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
          expect(response).to be_success
        end

        context 'when adding event types' do
          let(:params) do
            { event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign],
              Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer]] }
          end

          context 'when the flow configuration is invalid' do
            before do
              allow_next(::Ai::Catalog::Items::ValidateConfigService)
                .to receive(:execute)
                .and_return(ServiceResponse.error(
                  message: ['Component missing input variables: goal'],
                  reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG
                ))
            end

            it 'returns an error and does not update the flow trigger' do
              response = service.execute(params)

              expect(response).to be_error
              expect(response.message)
                .to include('Cannot add trigger events because the custom flow configuration is invalid')
              expect(response.reason)
                .to eq(::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG)
              expect(trigger.reload.event_types).to contain_exactly(
                Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign]
              )
            end

            it 'does not emit an audit event' do
              expect { service.execute(params) }.not_to change { AuditEventReader.count }
            end
          end

          context 'when Duo Workflow Service is unavailable' do
            before do
              allow_next(::Ai::Catalog::Items::ValidateConfigService)
                .to receive(:execute)
                .and_return(ServiceResponse.error(
                  message: 'Unable to validate flow configuration. Duo Workflow Service is currently unavailable.',
                  reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE
                ))
            end

            it 'passes through the service-unavailable error and does not update the flow trigger' do
              response = service.execute(params)

              expect(response).to be_error
              expect(response.message)
                .to include('Unable to validate flow configuration. Duo Workflow Service is currently unavailable.')
              expect(response.reason)
                .to eq(::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE)
              expect(trigger.reload.event_types).to contain_exactly(
                Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign]
              )
            end
          end

          context 'when the flow configuration is valid' do
            it 'updates the flow trigger' do
              response = service.execute(params)

              expect(response).to be_success
              expect(trigger.reload.event_types).to contain_exactly(
                Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign],
                Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer]
              )
            end
          end
        end

        it 'updates to different catalog item' do
          update_params = {
            ai_catalog_item_consumer_id: item_consumer2.id
          }

          response = service.execute(update_params)
          expect(response).to be_success
          flow_trigger = response.payload

          expect(flow_trigger.ai_catalog_item_consumer).to eq(item_consumer2)
        end

        it 'records the flow change between catalog items in the audit event', :aggregate_failures do
          update_params = { ai_catalog_item_consumer_id: item_consumer2.id }

          expect(service.execute(update_params)).to be_success

          expect(AuditEventReader.last.details[:flow]).to eq(
            'from' => {
              'type' => 'ai_catalog_item', 'ai_catalog_item_consumer_id' => item_consumer1.id,
              'name' => item_consumer1.item.name
            },
            'to' => {
              'type' => 'ai_catalog_item', 'ai_catalog_item_consumer_id' => item_consumer2.id,
              'name' => item_consumer2.item.name
            }
          )
        end
      end

      context 'when switching the item consumer' do
        let_it_be_with_reload(:trigger) do
          create(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer1,
            event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]]
          )
        end

        context 'when the target flow configuration is invalid' do
          before do
            allow_next(::Ai::Catalog::Items::ValidateConfigService)
              .to receive(:execute)
              .and_return(ServiceResponse.error(
                message: ['Component missing input variables: goal'],
                reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG
              ))
          end

          it 'returns an error and does not switch the item consumer' do
            response = service.execute(ai_catalog_item_consumer_id: item_consumer2.id)

            expect(response).to be_error
            expect(response.message)
              .to include('Cannot add trigger events because the custom flow configuration is invalid')
            expect(trigger.reload.ai_catalog_item_consumer).to eq(item_consumer1)
          end

          it 'does not emit an audit event' do
            expect { service.execute(ai_catalog_item_consumer_id: item_consumer2.id) }
              .not_to change { AuditEventReader.count }
          end
        end

        context 'when the target flow configuration is valid' do
          it 'switches to the new item consumer' do
            response = service.execute(ai_catalog_item_consumer_id: item_consumer2.id)

            expect(response).to be_success
            expect(trigger.reload.ai_catalog_item_consumer).to eq(item_consumer2)
          end
        end

        it 'does not validate when the same item consumer is supplied' do
          expect(::Ai::Catalog::Items::ValidateConfigService).not_to receive(:new)

          response = service.execute(ai_catalog_item_consumer_id: item_consumer1.id)
          expect(response).to be_success
        end
      end

      context 'when the custom flow has no pinned version' do
        let_it_be_with_reload(:trigger) do
          create(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer1,
            event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]]
          )
        end

        before do
          allow_next_found_instance_of(::Ai::Catalog::ItemConsumer) do |consumer|
            allow(consumer).to receive(:pinned_version).and_return(nil)
          end

          allow_next(::Ai::Catalog::Items::ValidateConfigService).to receive(:execute).and_call_original
        end

        it 'returns an error and does not update the flow trigger' do
          response = service.execute(event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention],
            Ai::FlowTrigger::EVENT_TYPES[:assign]])

          expect(response).to be_error
          expect(response.message)
            .to include('Cannot add trigger events because the custom flow configuration is invalid')
          expect(trigger.reload.event_types).to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
        end
      end

      context 'when also passing a matching user_id' do
        let(:params) do
          {
            user_id: item_consumer1.active_service_account.id,
            ai_catalog_item_consumer_id: item_consumer1.id,
            config_path: nil
          }
        end

        it 'updates the flow trigger, but does not set the user ID' do
          response = service.execute(params)
          expect(response).to be_success
          flow_trigger = response.payload

          expect(flow_trigger.ai_catalog_item_consumer).to eq(item_consumer1)
          expect(flow_trigger.user_id).to be_nil
        end
      end

      context 'with a group trigger' do
        let_it_be_with_reload(:trigger) { create(:ai_flow_trigger, :for_inheritance_consumer) }

        let(:service) { described_class.new(project: nil, current_user: current_user, trigger: trigger) }

        it 'validates the flow configuration against the group when adding event types' do
          expect(::Ai::Catalog::Items::ValidateConfigService).to receive(:new)
            .with(container: trigger.group, current_user: current_user)
            .and_return(instance_double(::Ai::Catalog::Items::ValidateConfigService,
              execute: ServiceResponse.success))

          service.execute(event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention],
            Ai::FlowTrigger::EVENT_TYPES[:assign]])
        end

        it 'denies a user who cannot manage the trigger' do
          response = service.execute(description: 'Updated description')

          expect(response).to be_error
          expect(response.reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
          expect(trigger.reload.description).not_to eq('Updated description')
        end

        context 'when the user can manage the trigger' do
          before do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?)
              .with(current_user, :manage_ai_flow_triggers, trigger).and_return(true)
          end

          it 'updates the trigger and audits it on the group' do
            response = service.execute(
              description: 'Updated description',
              event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign]],
              active: false,
              ai_catalog_item_consumer_id: trigger.ai_catalog_item_consumer_id,
              user_id: nil,
              config_path: nil
            )

            expect(response).to be_success
            expect(trigger.reload).to have_attributes(
              description: 'Updated description',
              event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign]],
              active: false
            )
            expect(AuditEventReader.last).to have_attributes(entity_type: 'Group', entity_id: trigger.group_id)
          end

          shared_examples 'rejects changing the group trigger source' do
            it 'returns an error and does not update the trigger' do
              consumer_id = trigger.ai_catalog_item_consumer_id

              response = service.execute(update_params)

              expect(response).to be_error
              expect(trigger.reload).to have_attributes(
                user_id: nil, config_path: nil, ai_catalog_item_consumer_id: consumer_id
              )
            end
          end

          context 'when setting a service account from another top-level group' do
            let(:update_params) { { user_id: service_account.id } }

            it_behaves_like 'rejects changing the group trigger source'

            it 'returns an unauthorized error' do
              expect(service.execute(update_params).reason).to eq(described_class::ERROR_REASON_UNAUTHORIZED)
            end
          end

          context 'when setting a config path' do
            let(:update_params) { { config_path: 'path/config.yml' } }

            it_behaves_like 'rejects changing the group trigger source'
          end

          context 'when switching to another inheritance consumer of the same group' do
            let(:other_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: trigger.group) }
            let(:update_params) { { ai_catalog_item_consumer_id: other_consumer.id } }

            it_behaves_like 'rejects changing the group trigger source'

            it 'returns the consumer change error' do
              expect(service.execute(update_params).message)
                .to include('The flow of a group trigger cannot be changed')
            end
          end

          it 'does not remove the item consumer' do
            consumer_id = trigger.ai_catalog_item_consumer_id

            response = service.execute(ai_catalog_item_consumer_id: nil)

            expect(response).to be_error
            expect(trigger.reload.ai_catalog_item_consumer_id).to eq(consumer_id)
          end

          it 'rejects the scheduled event type' do
            response = service.execute(event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]])

            expect(response).to be_error
            expect(response.message).to eq('Scheduled triggers are not supported for group configurations')
            expect(response.reason).to eq(described_class::ERROR_REASON_INVALID_TRIGGER)
            expect(trigger.reload.event_types).not_to include(Ai::FlowTrigger::EVENT_TYPES[:scheduled])
          end

          it 'rejects the scheduled event type mixed with other event types' do
            response = service.execute(
              event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled], Ai::FlowTrigger::EVENT_TYPES[:mention]]
            )

            expect(response).to be_error
            expect(response.message).to eq('Scheduled triggers are not supported for group configurations')
            expect(trigger.reload.event_types).not_to include(Ai::FlowTrigger::EVENT_TYPES[:scheduled])
          end
        end
      end

      context 'with invalid catalog item parameters' do
        let_it_be(:other_project) { create(:project, :in_group) }
        let_it_be(:item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: other_project) }

        it 'returns an error' do
          catalog_params = {
            ai_catalog_item_consumer_id: item_consumer.id,
            config_path: nil
          }

          response = service.execute(catalog_params)
          expect(response).to be_error
          expect(response.message).to include('ai_catalog_item_consumer container does not match container')
        end
      end
    end
  end
end
