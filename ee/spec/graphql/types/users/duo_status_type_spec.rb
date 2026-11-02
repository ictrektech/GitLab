# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['UserDuoStatus'], feature_category: :ai_catalog_curation do
  include GraphqlHelpers

  it { expect(described_class.graphql_name).to eq('UserDuoStatus') }

  it 'has specific fields' do
    expect(described_class).to have_graphql_fields(
      :disabled,
      :disabled_reason,
      :flow_trigger_events
    )
  end

  describe '#disabled' do
    let_it_be(:current_user) { create(:user) }

    context 'when object is a regular user' do
      let_it_be(:regular_user) { create(:user) }

      it 'returns false' do
        result = resolve_field(:disabled, regular_user, current_user: current_user)
        expect(result).to be false
      end
    end

    context 'when object is a service account without composite identity enforced' do
      let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: false) }

      it 'returns false' do
        result = resolve_field(:disabled, service_account, current_user: current_user)
        expect(result).to be false
      end
    end

    context 'when object is a service account with composite identity enforced' do
      let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

      context 'when quota check succeeds' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.success)
          end
        end

        it 'returns false' do
          result = resolve_field(:disabled, service_account, current_user: current_user)
          expect(result).to be false
        end
      end

      context 'when quota check fails with usage_quota_exceeded' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Usage quota exceeded', reason: :usage_quota_exceeded)
            )
          end
        end

        it 'returns true' do
          result = resolve_field(:disabled, service_account, current_user: current_user)
          expect(result).to be true
        end
      end

      context 'when quota check fails with user_missing' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'User is required', reason: :user_missing)
            )
          end
        end

        it 'returns true' do
          result = resolve_field(:disabled, service_account, current_user: current_user)
          expect(result).to be true
        end
      end

      context 'when quota check fails with namespace_missing' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Namespace is required', reason: :namespace_missing)
            )
          end
        end

        it 'returns true' do
          result = resolve_field(:disabled, service_account, current_user: current_user)
          expect(result).to be true
        end
      end
    end
  end

  describe '#disabled_reason' do
    let_it_be(:current_user) { create(:user) }

    context 'when object is a regular user' do
      let_it_be(:regular_user) { create(:user) }

      it 'returns empty string' do
        result = resolve_field(:disabled_reason, regular_user, current_user: current_user)
        expect(result).to eq('')
      end
    end

    context 'when object is a service account without composite identity enforced' do
      let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: false) }

      it 'returns empty string' do
        result = resolve_field(:disabled_reason, service_account, current_user: current_user)
        expect(result).to eq('')
      end
    end

    context 'when object is a service account with composite identity enforced' do
      let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

      context 'when quota check succeeds' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.success)
          end
        end

        it 'returns empty string' do
          result = resolve_field(:disabled_reason, service_account, current_user: current_user)
          expect(result).to eq('')
        end
      end

      context 'when quota check fails with usage_quota_exceeded' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Usage quota exceeded', reason: :usage_quota_exceeded)
            )
          end
        end

        it 'returns unavailable no credits message' do
          result = resolve_field(:disabled_reason, service_account, current_user: current_user)
          expect(result).to eq("Unavailable - no credits")
        end
      end

      context 'when quota check fails with user_missing' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'User is required', reason: :user_missing)
            )
          end
        end

        it 'returns unavailable invalid user message' do
          result = resolve_field(:disabled_reason, service_account, current_user: current_user)
          expect(result).to eq("Unavailable - invalid user")
        end
      end

      context 'when quota check fails with namespace_missing' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Namespace is required', reason: :namespace_missing)
            )
          end
        end

        it 'returns unavailable missing default namespace message' do
          result = resolve_field(:disabled_reason, service_account, current_user: current_user)
          expect(result).to eq("Unavailable - missing default namespace")
        end
      end

      context 'when quota check fails with an unknown reason' do
        before do
          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Something went wrong', reason: :some_unknown_reason)
            )
          end
        end

        it 'returns unavailable unknown reason message' do
          result = resolve_field(:disabled_reason, service_account, current_user: current_user)
          expect(result).to eq("Unavailable - unknown reason")
        end
      end
    end
  end

  describe '#flow_trigger_events' do
    let_it_be(:current_user) { create(:user) }
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:other_project) { create(:project, group: group) }

    # Trigger type 1: config-path trigger (user_id points directly to SA)
    let_it_be(:sa_config) { create(:service_account) }
    let_it_be(:config_trigger) do
      create(:ai_flow_trigger,
        project: project,
        user: sa_config,
        event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
    end

    # Trigger type 2: direct catalog consumer (SA owns group-level parent consumer;
    # trigger lives on the child project-level consumer)
    let_it_be(:child_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }
    let_it_be(:sa_direct) { child_consumer.parent_item_consumer.service_account }
    let_it_be(:direct_trigger) do
      create(:ai_flow_trigger, :for_catalog_consumer,
        project: project,
        ai_catalog_item_consumer: child_consumer,
        event_types: [Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer]])
    end

    # Trigger type 3: inheritance consumer (group-level, kind: :inheritance)
    let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
    let_it_be(:sa_inheritance) { inheritance_consumer.service_account }
    let_it_be(:group_trigger) do
      create(:ai_flow_trigger, :for_inheritance_consumer,
        group: group,
        ai_catalog_item_consumer: inheritance_consumer,
        event_types: [Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
    end

    def resolve_events(sa, parent:)
      batch_sync do
        resolve_field(:flow_trigger_events, sa, current_user: current_user, ctx: { duo_status_parent: parent })
      end
    end

    context 'when no parent entity is set (nil)' do
      it 'returns events from config-path trigger' do
        expect(resolve_events(sa_config, parent: nil))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
      end

      it 'returns events from direct consumer trigger' do
        expect(resolve_events(sa_direct, parent: nil))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer])
      end

      it 'returns empty for inheritance-only SA' do
        expect(resolve_events(sa_inheritance, parent: nil)).to be_empty
      end
    end

    context 'when parent entity is a Project' do
      context 'with a config-path trigger on that project' do
        it 'returns the trigger events' do
          expect(resolve_events(sa_config, parent: project))
            .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
        end

        it 'excludes config-path triggers from a different project' do
          expect(resolve_events(sa_config, parent: other_project)).to be_empty
        end
      end

      context 'with a direct catalog consumer trigger on that project' do
        it 'returns the trigger events' do
          expect(resolve_events(sa_direct, parent: project))
            .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer])
        end

        it 'excludes direct consumer triggers from a different project' do
          expect(resolve_events(sa_direct, parent: other_project)).to be_empty
        end
      end

      context 'with an inheritance consumer trigger' do
        context 'when the feature flag is enabled' do
          it 'includes events from the inherited trigger' do
            expect(resolve_events(sa_inheritance, parent: project))
              .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks])
          end
        end

        context 'when the feature flag is disabled' do
          before do
            stub_feature_flags(ai_catalog_group_inherited_consumers: false)
          end

          it 'returns empty' do
            expect(resolve_events(sa_inheritance, parent: project)).to be_empty
          end
        end
      end
    end

    context 'when parent entity is a personal namespace' do
      let_it_be(:personal_namespace) { create(:user, :with_namespace).namespace }

      it 'does not include inherited trigger events' do
        expect(resolve_events(sa_inheritance, parent: personal_namespace)).to be_empty
      end
    end

    context 'when parent entity is a Namespace (group)' do
      context 'with a config-path trigger on a project in the group' do
        it 'returns the trigger events' do
          expect(resolve_events(sa_config, parent: group))
            .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
        end
      end

      context 'with a direct catalog consumer trigger on a project in the group' do
        it 'returns the trigger events' do
          expect(resolve_events(sa_direct, parent: group))
            .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer])
        end
      end

      context 'with an inheritance consumer trigger' do
        context 'when the feature flag is enabled' do
          it 'includes events from the inherited trigger' do
            expect(resolve_events(sa_inheritance, parent: group))
              .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks])
          end
        end

        context 'when the feature flag is disabled' do
          before do
            stub_feature_flags(ai_catalog_group_inherited_consumers: false)
          end

          it 'returns empty' do
            expect(resolve_events(sa_inheritance, parent: group)).to be_empty
          end
        end
      end
    end

    context 'when parent entity is a Namespace with subgroup projects' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }
      let_it_be(:sa_subgroup) { create(:service_account) }

      before_all do
        create(:ai_flow_trigger, project: subgroup_project, user: sa_subgroup,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
      end

      it 'only includes triggers from the direct projects of the group' do
        expect(resolve_events(sa_subgroup, parent: group)).to be_empty
        expect(resolve_events(sa_subgroup, parent: subgroup))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
      end
    end

    context 'when the service account has catalog consumer triggers in several projects' do
      let_it_be(:other_child_consumer) do
        create(:ai_catalog_item_consumer,
          project: other_project,
          item: child_consumer.item,
          service_account: nil,
          parent_item_consumer: child_consumer.parent_item_consumer)
      end

      before_all do
        create(:ai_flow_trigger, :for_catalog_consumer,
          project: other_project,
          ai_catalog_item_consumer: other_child_consumer,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:assign]])
      end

      it 'returns only the events of the current project' do
        expect(resolve_events(sa_direct, parent: project))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer])
        expect(resolve_events(sa_direct, parent: other_project))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:assign])
      end
    end

    context 'when the catalog consumer also has an autonomous trigger' do
      before_all do
        create(:ai_flow_trigger, :autonomous, project: project, ai_catalog_item_consumer: child_consumer)
      end

      it 'does not add the autonomous events to the shared service account' do
        expect(resolve_events(sa_direct, parent: project))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer])
      end
    end

    context 'when one catalog consumer has several triggers in the project' do
      let_it_be(:multi_trigger_consumer) do
        create(:ai_catalog_item_consumer, :child_item_consumer, project: project)
      end

      let_it_be(:sa_multi_trigger) { multi_trigger_consumer.parent_item_consumer.service_account }

      before_all do
        create(:ai_flow_trigger, :for_catalog_consumer,
          project: project,
          ai_catalog_item_consumer: multi_trigger_consumer,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
        create(:ai_flow_trigger, :for_catalog_consumer,
          project: project,
          ai_catalog_item_consumer: multi_trigger_consumer,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:assign]])
      end

      it 'returns the events of all triggers' do
        expect(resolve_events(sa_multi_trigger, parent: project))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign])
      end
    end

    context 'when a trigger is inactive' do
      let_it_be(:sa_inactive) { create(:service_account) }

      before_all do
        create(:ai_flow_trigger, :inactive, project: project, user: sa_inactive,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
      end

      it 'excludes it' do
        expect(resolve_events(sa_inactive, parent: project)).to be_empty
      end
    end

    context 'when the service account has no triggers' do
      let_it_be(:sa_without_triggers) { create(:service_account) }

      it 'returns an empty list' do
        expect(resolve_events(sa_without_triggers, parent: project)).to eq([])
      end
    end

    context 'when the service account has several config-path triggers in the project' do
      let_it_be(:sa_multiple) { create(:service_account) }

      before_all do
        create(:ai_flow_trigger, project: project, user: sa_multiple,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign]])
        create(:ai_flow_trigger, project: project, user: sa_multiple,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]])
      end

      it 'returns the unique events of all triggers' do
        expect(resolve_events(sa_multiple, parent: project))
          .to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention], Ai::FlowTrigger::EVENT_TYPES[:assign])
      end
    end

    context 'when several service accounts are resolved together' do
      def lazy_events(sa, parent:)
        resolve_field(:flow_trigger_events, sa, current_user: current_user, ctx: { duo_status_parent: parent })
      end

      it 'loads the triggers with one query and returns each account its own events' do
        results = nil

        recorder = ActiveRecord::QueryRecorder.new do
          results = batch_sync do
            [sa_config, sa_direct, sa_inheritance].map { |sa| lazy_events(sa, parent: project) }
          end
        end

        expect(recorder.log.count { |query| query.include?('FROM "ai_flow_triggers"') }).to eq(1)
        expect(results).to eq([
          [Ai::FlowTrigger::EVENT_TYPES[:mention]],
          [Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer]],
          [Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]]
        ])
      end

      it 'loads each parent entity separately' do
        results = batch_sync do
          [lazy_events(sa_direct, parent: project), lazy_events(sa_direct, parent: other_project)]
        end

        expect(results).to eq([[Ai::FlowTrigger::EVENT_TYPES[:assign_reviewer]], []])
      end
    end
  end
end
