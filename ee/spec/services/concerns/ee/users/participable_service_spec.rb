# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::Users::ParticipableService, feature_category: :duo_agent_platform do
  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:service_class) do
    Class.new do
      include EE::Users::ParticipableService

      attr_reader :current_user, :participation_object

      def initialize(current_user, participation_object = nil)
        @current_user = current_user
        @participation_object = participation_object
      end
    end
  end

  let(:service) { service_class.new(current_user, project) }

  describe '#user_disabled_fields' do
    context 'when user is a regular user' do
      let_it_be(:user) { create(:user) }

      it 'returns disabled: false and empty disabled_reason' do
        result = service.user_disabled_fields(user)

        expect(result).to eq({ disabled: false, disabled_reason: '', flow_trigger_events: [] })
      end
    end

    context 'when user is a service account without composite identity enforced' do
      let_it_be(:user) { create(:user, :service_account, composite_identity_enforced: false) }

      it 'returns disabled: false and empty disabled_reason' do
        result = service.user_disabled_fields(user)

        expect(result).to eq({ disabled: false, disabled_reason: '', flow_trigger_events: [] })
      end
    end

    context 'when user is a service account with composite identity enforced' do
      let_it_be(:user) { create(:user, :service_account, composite_identity_enforced: true) }

      context 'when quota check succeeds' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |quota_service|
            allow(quota_service).to receive(:execute).and_return(ServiceResponse.success)
          end
        end

        it 'returns disabled: false and empty disabled_reason' do
          result = service.user_disabled_fields(user)

          expect(result).to eq({ disabled: false, disabled_reason: '', flow_trigger_events: [] })
        end
      end

      context 'when quota check fails with usage_quota_exceeded' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |quota_service|
            allow(quota_service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Usage quota exceeded', reason: :usage_quota_exceeded)
            )
          end
        end

        it 'returns disabled: true with no credits message and empty flow_trigger_events' do
          result = service.user_disabled_fields(user)

          expect(result).to eq({ disabled: true, disabled_reason: "Unavailable - no credits", flow_trigger_events: [] })
        end
      end

      context 'when quota check fails with user_missing' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |quota_service|
            allow(quota_service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'User is required', reason: :user_missing)
            )
          end
        end

        it 'returns disabled: true with invalid user message and empty flow_trigger_events' do
          result = service.user_disabled_fields(user)

          expect(result).to eq({ disabled: true, disabled_reason: "Unavailable - invalid user",
flow_trigger_events: [] })
        end
      end

      context 'when quota check fails with namespace_missing' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |quota_service|
            allow(quota_service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Namespace is required', reason: :namespace_missing)
            )
          end
        end

        it 'returns disabled: true with missing default namespace message and empty flow_trigger_events' do
          result = service.user_disabled_fields(user)

          expect(result).to eq({ disabled: true, disabled_reason: "Unavailable - missing default namespace",
flow_trigger_events: [] })
        end
      end

      context 'when quota check fails with an unknown reason' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |quota_service|
            allow(quota_service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Something went wrong', reason: :some_unknown_reason)
            )
          end
        end

        it 'returns disabled: true with unknown reason message and empty flow_trigger_events' do
          result = service.user_disabled_fields(user)

          expect(result).to eq({ disabled: true, disabled_reason: "Unavailable - unknown reason",
flow_trigger_events: [] })
        end
      end
    end

    context 'with all trigger types on the participation project' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project_in_group) { create(:project, group: group) }
      let(:service) { service_class.new(current_user, project_in_group) }

      let_it_be(:sa_config) { create(:service_account) }
      let_it_be(:config_trigger) do
        create(:ai_flow_trigger, project: project_in_group, user: sa_config, event_types: [0, 1])
      end

      let_it_be(:child_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project_in_group) }
      let_it_be(:sa_direct) { child_consumer.parent_item_consumer.service_account }
      let_it_be(:direct_trigger) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project_in_group,
          ai_catalog_item_consumer: child_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer]])
      end

      let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
      let_it_be(:sa_inheritance) { inheritance_consumer.service_account }
      let_it_be(:group_trigger) do
        create(:ai_flow_trigger, :for_inheritance_consumer, group: group,
          ai_catalog_item_consumer: inheritance_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])
      end

      it 'returns correct flow_trigger_events for each trigger type' do
        expect(service.user_disabled_fields(sa_config)[:flow_trigger_events]).to contain_exactly(:MENTION, :ASSIGN)
        expect(service.user_disabled_fields(sa_direct)[:flow_trigger_events]).to contain_exactly(:ASSIGN_REVIEWER)
        expect(service.user_disabled_fields(sa_inheritance)[:flow_trigger_events]).to contain_exactly(:MENTION)
      end

      it 'returns empty when the trigger is inactive' do
        ::Ai::FlowTrigger.find(config_trigger.id).update!(active: false)

        expect(service.user_disabled_fields(sa_config)[:flow_trigger_events]).to be_empty
      end

      context 'when the participation object is a group' do
        let(:service) { service_class.new(current_user, group) }

        it 'returns flow_trigger_events from group projects and inherited triggers' do
          expect(service.user_disabled_fields(sa_config)[:flow_trigger_events]).to contain_exactly(:MENTION, :ASSIGN)
          expect(service.user_disabled_fields(sa_direct)[:flow_trigger_events]).to contain_exactly(:ASSIGN_REVIEWER)
          expect(service.user_disabled_fields(sa_inheritance)[:flow_trigger_events]).to contain_exactly(:MENTION)
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'returns empty for inherited SA' do
          expect(service.user_disabled_fields(sa_inheritance)[:flow_trigger_events]).to be_empty
        end
      end
    end
  end
end
