# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTrigger, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:custom_item) { create(:ai_catalog_flow) }
  let_it_be(:external_agent_item) { create(:ai_catalog_third_party_flow) }
  let_it_be(:maintained_external_agent_item) do
    create(:ai_catalog_third_party_flow, :public, verification_level: :gitlab_maintained)
  end

  let_it_be(:foundational_item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'code_review/v1') }
  let_it_be(:user) { create(:service_account) }

  subject(:flow_trigger) { build(:ai_flow_trigger, project: project) }

  def build_consumer_trigger(item, *traits)
    build(:ai_flow_trigger, :for_catalog_consumer, *traits, project: project,
      ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
        project: project, item: item))
  end

  describe 'associations' do
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to belong_to(:group).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:ai_catalog_item_consumer).class_name('Ai::Catalog::ItemConsumer').optional }
  end

  describe 'AUTONOMOUS_EVENT_TYPE_IDS' do
    it 'contains only the scheduled event type' do
      expect(described_class::AUTONOMOUS_EVENT_TYPE_IDS)
        .to contain_exactly(described_class::EVENT_TYPES[:scheduled])
    end
  end

  describe 'RUN_STATUSES' do
    it 'maps every session status to a run status' do
      session_statuses = ::Ai::DuoWorkflows::Workflow.state_machines[:status].states.map(&:name)

      expect(described_class::RUN_STATUSES.keys).to match_array(session_statuses)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_types) }
    it { is_expected.to validate_presence_of(:description) }

    it { is_expected.to validate_length_of(:description).is_at_most(255) }
    it { is_expected.to validate_length_of(:config_path).is_at_most(255) }

    it { is_expected.to allow_value(true, false).for(:active) }
    it { is_expected.not_to allow_value(nil).for(:active) }

    describe 'exactly one of project or group' do
      it 'is invalid when both project and group are set' do
        flow_trigger = build(:ai_flow_trigger, project: project, group: create(:group))

        expect(flow_trigger).not_to be_valid
      end

      it 'is invalid when neither project nor group is set' do
        flow_trigger = build(:ai_flow_trigger, project: nil, group: nil)

        expect(flow_trigger).not_to be_valid
      end

      it 'is valid for a group-scoped trigger' do
        flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer)

        expect(flow_trigger).to be_valid
      end
    end

    describe 'group_trigger_belongs_to_inheritance_consumer' do
      it 'is valid when the group matches an inheritance consumer for the same group' do
        flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer)

        expect(flow_trigger).to be_valid
      end

      it 'is invalid when the consumer is not an inheritance consumer' do
        group = create(:group)
        consumer = create(:ai_catalog_item_consumer, :parent_item_consumer, group: group)
        flow_trigger = build(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
          ai_catalog_item_consumer: consumer)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base])
          .to include('A group trigger must belong to an inheritance consumer of the same group')
      end

      it 'is invalid when the consumer belongs to a different group' do
        group = create(:group)
        other_group = create(:group)
        consumer = create(:ai_catalog_item_consumer, :inheritance, group: other_group)
        flow_trigger = build(:ai_flow_trigger, project: nil, group: group, config_path: nil, user: nil,
          ai_catalog_item_consumer: consumer)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base])
          .to include('A group trigger must belong to an inheritance consumer of the same group')
      end
    end

    describe 'group_trigger_not_autonomous' do
      it 'is invalid for a group trigger with an autonomous event type' do
        flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer, group: create(:group),
          event_types: [described_class::EVENT_TYPES[:scheduled]])

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base])
          .to include('Scheduled triggers are not supported for group configurations')
      end

      it 'is invalid for a group trigger mixing autonomous and other event types' do
        flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer, group: create(:group),
          event_types: [described_class::EVENT_TYPES[:scheduled], described_class::EVENT_TYPES[:mention]])

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base])
          .to include('Scheduled triggers are not supported for group configurations')
      end
    end

    describe 'group_trigger_consumer_unchanged' do
      let_it_be_with_reload(:group_trigger) { create(:ai_flow_trigger, :for_inheritance_consumer) }

      it 'is invalid when a persisted group trigger switches to another consumer' do
        group_trigger.ai_catalog_item_consumer =
          create(:ai_catalog_item_consumer, :inheritance, group: group_trigger.group)

        expect(group_trigger).not_to be_valid
        expect(group_trigger.errors[:base]).to include('The flow of a group trigger cannot be changed')
      end

      it 'is valid when other attributes change' do
        group_trigger.description = 'Updated description'

        expect(group_trigger).to be_valid
      end
    end

    describe 'filter' do
      it 'validates json_schema when filter changes' do
        flow_trigger.filter = { 'pipeline_hooks' => { 'unexpected' => true } }

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to be_present
      end

      it 'validates size limit when filter changes' do
        flow_trigger.filter = {
          'pipeline_hooks' => { 'rules' => [{ 'field' => 'a', 'operator' => 'eq', 'value' => 'b' * 9000 }] }
        }

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to be_present
      end
    end

    describe 'event_types_are_valid' do
      it 'rejects empty event_types array' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: [])

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:event_types]).to include("can't be blank")
      end

      it 'rejects nil event_types' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: nil)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:event_types]).to include("can't be blank")
      end

      it 'allows valid event_types array' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: [0])

        expect(flow_trigger).to be_valid
      end

      it 'allows the scheduled event type' do
        flow_trigger = build(:ai_flow_trigger, :autonomous, project: project)

        expect(flow_trigger).to be_valid
      end
    end

    describe 'scheduled_event_type_available' do
      let(:flow_trigger) do
        build(:ai_flow_trigger, :autonomous, project: project)
      end

      it 'is valid when the feature flag is enabled' do
        expect(flow_trigger).to be_valid
      end

      it 'persists the trigger when scheduled triggers are enabled for the project', :aggregate_failures do
        expect(project.duo_scheduled_triggers_enabled).to be(true)

        expect { flow_trigger.save! }.to change { described_class.count }.by(1)
        expect(flow_trigger.event_types).to include(described_class::EVENT_TYPES[:scheduled])
      end

      it 'is invalid when the feature flag is disabled' do
        stub_feature_flags(autonomous_service_account_execution: false)

        expect(flow_trigger).to be_invalid
        expect(flow_trigger.errors[:event_types]).to include('scheduled events are not available')
      end

      it 'ignores the feature flag for other event types' do
        stub_feature_flags(autonomous_service_account_execution: false)
        flow_trigger.event_types = [described_class::EVENT_TYPES[:mention]]

        flow_trigger.autonomous_service_account = nil

        expect(flow_trigger).to be_valid
      end

      context 'when the trigger already has scheduled persisted' do
        let!(:persisted_flow_trigger) do
          create(:ai_flow_trigger, :autonomous, project: project)
        end

        it 'allows saving unrelated changes after the flag is disabled' do
          stub_feature_flags(autonomous_service_account_execution: false)

          expect(persisted_flow_trigger.update(active: false)).to be true
        end

        it 'still rejects adding scheduled to a trigger that did not have it before', :aggregate_failures do
          other_trigger = create(:ai_flow_trigger, :for_catalog_consumer, project: project,
            event_types: [described_class::EVENT_TYPES[:mention]])
          stub_feature_flags(autonomous_service_account_execution: false)

          other_trigger.event_types = [described_class::EVENT_TYPES[:scheduled]]
          other_trigger.autonomous_service_account = create(:service_account, composite_identity_enforced: false)

          expect(other_trigger).to be_invalid
          expect(other_trigger.errors[:event_types]).to include('scheduled events are not available')
        end
      end

      it 'treats a trigger with no container as turned off', :aggregate_failures do
        trigger = build(:ai_flow_trigger, :autonomous)
        trigger.project = nil

        expect(trigger).to be_invalid
        expect(trigger.errors[:event_types]).to include('scheduled events are turned off')
      end

      context 'when scheduled triggers are turned off' do
        let_it_be_with_reload(:project) { create(:project, :in_group) }

        before do
          project.project_setting.update!(duo_scheduled_triggers_enabled: false)
        end

        it 'is invalid', :aggregate_failures do
          expect(flow_trigger).to be_invalid
          expect(flow_trigger.errors[:event_types]).to include('scheduled events are turned off')
        end

        it 'ignores the setting for other event types' do
          flow_trigger.event_types = [described_class::EVENT_TYPES[:mention]]
          flow_trigger.autonomous_service_account = nil

          expect(flow_trigger).to be_valid
        end

        it 'allows saving unrelated changes on a trigger that already has scheduled' do
          setting = project.project_setting
          setting.update!(duo_scheduled_triggers_enabled: true)
          persisted = create(:ai_flow_trigger, :autonomous, project: project)
          setting.update!(duo_scheduled_triggers_enabled: false)

          expect(persisted.update(active: false)).to be true
        end

        context 'when the feature flag is disabled' do
          before do
            stub_feature_flags(autonomous_service_account_execution: false)
          end

          it 'reports both reasons', :aggregate_failures do
            expect(flow_trigger).to be_invalid
            expect(flow_trigger.errors[:event_types]).to contain_exactly(
              'scheduled events are not available',
              'scheduled events are turned off'
            )
          end
        end
      end
    end

    describe 'filter_keys_match_event_types' do
      it 'allows filter keys that match event_types' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: { 'pipeline_hooks' => { 'rules' => [] } })

        expect(flow_trigger).to be_valid
      end

      it 'rejects filter keys that are not present in event_types' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
          filter: { 'pipeline_hooks' => { 'rules' => [] } })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains filters for event types not in event_types: pipeline_hooks'
        )
      end

      it 'allows a blank filter regardless of event_types' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
          filter: {})

        expect(flow_trigger).to be_valid
      end

      where(:non_hash_filter) { [123, 'a string', [1, 2, 3], true] }

      with_them do
        it 'falls through to the JSON schema validator without raising' do
          flow_trigger = build(:ai_flow_trigger,
            project: project,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
            filter: non_hash_filter)

          expect { flow_trigger.valid? }.not_to raise_error
          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include('must be a valid json schema')
        end
      end
    end

    describe 'scheduled filter schema' do
      def scheduled_trigger(config)
        build(:ai_flow_trigger,
          :autonomous,
          project: project,
          filter: { 'scheduled' => config })
      end

      it 'allows a full schedule config' do
        trigger = scheduled_trigger(
          'frequency' => 'WEEKLY', 'minute' => 30, 'hour' => 14, 'dayOfWeek' => 3, 'timezone' => 'America/New_York'
        )

        expect(trigger).to be_valid
      end

      it 'allows a config with only a frequency' do
        expect(scheduled_trigger('frequency' => 'HOURLY')).to be_valid
      end

      where(:invalid_config) do
        [
          [{ 'frequency' => 'SOMETIMES' }],
          [{ 'minute' => 30 }],
          [{ 'frequency' => 'DAILY', 'minute' => 60 }],
          [{ 'frequency' => 'DAILY', 'hour' => 24 }],
          [{ 'frequency' => 'WEEKLY', 'dayOfWeek' => 7 }],
          [{ 'frequency' => 'MONTHLY', 'dayOfMonth' => 29 }],
          [{ 'frequency' => 'DAILY', 'unknown' => 'key' }]
        ]
      end

      with_them do
        it 'rejects the config' do
          trigger = scheduled_trigger(invalid_config)

          expect(trigger).not_to be_valid
          expect(trigger.errors[:filter]).to include('must be a valid json schema')
        end
      end
    end

    describe 'filter_action_values_allowed' do
      it 'allows valid merge_request action values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'any',
              'rules' => [
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'approved' },
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'merged' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows the created merge_request action value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'created' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows the requested_changes merge_request action value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'requested_changes' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows valid work_item action values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'match' => 'any',
              'rules' => [
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'created' },
                { 'field' => 'action', 'operator' => 'eq', 'value' => 'status_changed' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects a typo in merge_request action value', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'approveed' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for merge_request: approveed. ' \
            'Allowed values are: approved, created, merged, requested_changes'
        )
      end

      it 'rejects invalid work_item action values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'updated' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for work_item: updated. Allowed values are: created, status_changed'
        )
      end

      it 'validates action values inside nested groups', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [
                {
                  'type' => 'group',
                  'match' => 'any',
                  'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'invalid_action' }]
                }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for merge_request: invalid_action. ' \
            'Allowed values are: approved, created, merged, requested_changes'
        )
      end

      it 'validates action values in array form for in operator', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => %w[created invalid_action] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for work_item: invalid_action. Allowed values are: created, status_changed'
        )
      end

      it 'does not add action value errors for event types without an action allowlist' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects nil action values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => nil }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "action values for merge_request can't be blank"
        )
      end

      it 'stops collecting action values beyond MAX_DEPTH', :aggregate_failures do
        deeply_nested = { 'field' => 'action', 'operator' => 'eq', 'value' => 'deep_action' }
        Gitlab::FilterEvaluator::MAX_DEPTH.times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'still validates action values at exactly MAX_DEPTH', :aggregate_failures do
        deeply_nested = { 'field' => 'action', 'operator' => 'eq', 'value' => 'invalid_deep_action' }
        (Gitlab::FilterEvaluator::MAX_DEPTH - 1).times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid action values for merge_request: invalid_deep_action. ' \
            'Allowed values are: approved, created, merged, requested_changes'
        )
      end

      it 'allows a blank filter' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {})

        expect(flow_trigger).to be_valid
      end
    end

    describe 'filter_fields_and_values_allowed' do
      it 'allows the filter shape the frontend writes' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'rules' => [
                {
                  'field' => 'object_attributes.status',
                  'operator' => 'in',
                  'value' => %w[running success failed canceled]
                }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows a single valid status value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows source rules with a valid pipeline source' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'failed' },
                { 'field' => 'object_attributes.source', 'operator' => 'eq', 'value' => 'merge_request_event' }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows merge_request title rules with any value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'merge_request.title', 'operator' => 'not_contains', 'value' => 'Draft:' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows ref rules with any value' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.ref', 'operator' => 'eq', 'value' => 'main' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows default_branch rules with true values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => true }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows default_branch rules with false values' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => false }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects non-boolean default_branch values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => 'yes' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.default_branch values for pipeline_hooks: yes. ' \
            'Allowed values are: true, false'
        )
      end

      it 'rejects nil values even for fields without a value allowlist', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'merge_request.title', 'operator' => 'eq', 'value' => nil }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "merge_request.title values for pipeline_hooks can't be blank"
        )
      end

      it 'rejects invalid status values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'rejects invalid source values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.source', 'operator' => 'eq', 'value' => 'marge_request_event' }
              ]
            }
          })

        allowed_sources = described_class::ALLOWED_FILTER_FIELDS['pipeline_hooks']['object_attributes.source']

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.source values for pipeline_hooks: marge_request_event. ' \
            "Allowed values are: #{allowed_sources.join(', ')}"
        )
      end

      it 'rejects unknown fields', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.not_a_real_field', 'operator' => 'eq', 'value' => 'main' }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid fields for pipeline_hooks: object_attributes.not_a_real_field. ' \
            'Allowed fields are: object_attributes.status, object_attributes.source, ' \
            'object_attributes.ref, object_attributes.default_branch, merge_request.title'
        )
      end

      it 'rejects an invalid field and an invalid value together', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                { 'field' => 'object_attributes.not_a_real_field', 'operator' => 'eq', 'value' => 'main' },
                { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid fields for pipeline_hooks: object_attributes.not_a_real_field. ' \
            'Allowed fields are: object_attributes.status, object_attributes.source, ' \
            'object_attributes.ref, object_attributes.default_branch, merge_request.title'
        )
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'validates fields and values inside nested groups', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [
                {
                  'type' => 'group',
                  'match' => 'any',
                  'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }]
                }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'rejects invalid status values in array form for in operator', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => %w[failed passed] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'rejects empty array values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => [] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "object_attributes.status values for pipeline_hooks can't be blank"
        )
      end

      it 'rejects blank values inside arrays', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => ['failed', ''] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "object_attributes.status values for pipeline_hooks can't be blank"
        )
      end

      it 'rejects nil status values', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => nil }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          "object_attributes.status values for pipeline_hooks can't be blank"
        )
      end

      it 'stops collecting rules beyond MAX_DEPTH' do
        deeply_nested = { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }
        Gitlab::FilterEvaluator::MAX_DEPTH.times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'still validates rules at exactly MAX_DEPTH', :aggregate_failures do
        deeply_nested = { 'field' => 'object_attributes.status', 'operator' => 'eq', 'value' => 'passed' }
        (Gitlab::FilterEvaluator::MAX_DEPTH - 1).times do
          deeply_nested = { 'type' => 'group', 'match' => 'all', 'rules' => [deeply_nested] }
        end

        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            'pipeline_hooks' => {
              'match' => 'all',
              'rules' => [deeply_nested]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid object_attributes.status values for pipeline_hooks: passed. ' \
            'Allowed values are: running, success, failed, canceled'
        )
      end

      it 'allows a blank filter' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {})

        expect(flow_trigger).to be_valid
      end

      it 'skips validation for event types without a field allowlist' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
          filter: {
            'mention' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'anything', 'operator' => 'eq', 'value' => 'whatever' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'does not add field errors for merge_request action filters' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
          filter: {
            'merge_request' => {
              'match' => 'all',
              'rules' => [{ 'field' => 'action', 'operator' => 'eq', 'value' => 'approved' }]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows a work_item filter with a status.name rule' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.name', 'operator' => 'in', 'value' => ['In progress', 'Done'] }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'allows a work_item filter with only an action rule and no status.name rule' do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] }
              ]
            }
          })

        expect(flow_trigger).to be_valid
      end

      it 'rejects a work_item filter with an unknown field', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.category', 'operator' => 'eq', 'value' => 'started' }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include(
          'contains invalid fields for work_item: status.category. ' \
            'Allowed fields are: action, status.name, work_item_type_id, software_factory_enabled'
        )
      end

      it 'reports a blank work_item action value once', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => [''] }]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter].count("action values for work_item can't be blank")).to eq(1)
      end

      it 'rejects a blank status.name value for work_item', :aggregate_failures do
        flow_trigger = build(:ai_flow_trigger,
          project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.name', 'operator' => 'in', 'value' => ['In progress', ''] }
              ]
            }
          })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:filter]).to include("status.name values for work_item can't be blank")
      end

      context 'with a work_item_type_id rule' do
        let_it_be(:task_type_id) { ::WorkItems::TypesFramework::Provider.new(project).find_by_base_type(:task).id }

        def work_item_type_filter(value, operator: 'in')
          {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'work_item_type_id', 'operator' => operator, 'value' => value }
              ]
            }
          }
        end

        def build_work_item_type_trigger(value, operator: 'in')
          build(:ai_flow_trigger,
            project: project,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
            filter: work_item_type_filter(value, operator: operator))
        end

        def create_work_item_type_trigger(value)
          create(:ai_flow_trigger,
            project: project,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
            filter: work_item_type_filter(value))
        end

        def invalid_type_ids_error(values)
          "contains invalid work_item_type_id values for work_item: #{values}. " \
            'Values must be integer IDs of work item types of the project or group'
        end

        it 'allows the ID of a system-defined type' do
          expect(build_work_item_type_trigger([task_type_id])).to be_valid
        end

        it 'allows the ID of a custom type of the namespace' do
          custom_type = create(:work_item_custom_type, :with_organization, organization: project.organization)

          expect(build_work_item_type_trigger([task_type_id, custom_type.id])).to be_valid
        end

        it 'allows an archived custom type, because its work items can still change status' do
          custom_type = create(:work_item_custom_type, :with_organization, :archived,
            organization: project.organization)

          expect(build_work_item_type_trigger([custom_type.id])).to be_valid
        end

        # Work items of a converted type keep the ID of the system-defined type, so events never carry
        # the custom type's own ID.
        it 'allows the system-defined ID of a converted type and rejects its own ID', :aggregate_failures do
          converted_type = create(:work_item_custom_type, :with_organization, :converted_from_task,
            organization: project.organization)

          flow_trigger = build_work_item_type_trigger([converted_type.persistable_id, converted_type.id])

          expect(converted_type.persistable_id).to eq(task_type_id)
          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(invalid_type_ids_error(converted_type.id))
        end

        it 'checks the types of the group of a group-level trigger', :aggregate_failures do
          group = create(:group)
          custom_type = create(:work_item_custom_type, :with_organization, organization: group.organization)
          flow_trigger = build(:ai_flow_trigger, :for_inheritance_consumer,
            group: group,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
            filter: work_item_type_filter([custom_type.id]))

          expect(flow_trigger).to be_valid

          flow_trigger.filter = work_item_type_filter([custom_type.id, non_existing_record_id])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(invalid_type_ids_error(non_existing_record_id))
        end

        it 'does not check the IDs again when the filter does not change' do
          flow_trigger = create_work_item_type_trigger([task_type_id])
          flow_trigger.update_column(:filter, work_item_type_filter([non_existing_record_id]))

          flow_trigger.reload.active = false

          expect(flow_trigger).to be_valid
        end

        # A stored ID can stop resolving, for example after a project transfer to another root namespace.
        it 'allows a filter change that keeps a stored ID that no longer resolves' do
          flow_trigger = create_work_item_type_trigger([task_type_id])
          flow_trigger.update_column(:filter, work_item_type_filter([non_existing_record_id]))

          flow_trigger.reload.filter = work_item_type_filter([non_existing_record_id, task_type_id])

          expect(flow_trigger).to be_valid
        end

        it 'rejects an invalid ID that a filter change adds', :aggregate_failures do
          flow_trigger = create_work_item_type_trigger([task_type_id])

          flow_trigger.filter = work_item_type_filter([task_type_id, non_existing_record_id])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(invalid_type_ids_error(non_existing_record_id))
        end

        it 'allows the in and not_in operators, with a list or a single ID', :aggregate_failures do
          expect(build_work_item_type_trigger(task_type_id)).to be_valid
          expect(build_work_item_type_trigger([task_type_id], operator: 'not_in')).to be_valid
        end

        it 'rejects the other operators', :aggregate_failures do
          %w[eq ne gt lt contains not_contains].each do |operator|
            flow_trigger = build_work_item_type_trigger([task_type_id], operator: operator)

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:filter]).to include(
              "contains invalid work_item_type_id operators for work_item: #{operator}. " \
                'Allowed operators are: in, not_in')
          end
        end

        it 'rejects an ID that is not a type of the namespace', :aggregate_failures do
          flow_trigger = build_work_item_type_trigger([task_type_id, non_existing_record_id])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(invalid_type_ids_error(non_existing_record_id))
        end

        it 'rejects an ID given as a string', :aggregate_failures do
          flow_trigger = build_work_item_type_trigger([task_type_id.to_s])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(invalid_type_ids_error(%("#{task_type_id}")))
        end

        it 'rejects a blank value', :aggregate_failures do
          flow_trigger = build_work_item_type_trigger([nil])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include("work_item_type_id values for work_item can't be blank")
        end
      end

      context 'with a software_factory_enabled rule' do
        def software_factory_filter(value, operator: 'in')
          {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'software_factory_enabled', 'operator' => operator, 'value' => value }
              ]
            }
          }
        end

        def build_software_factory_trigger(value, operator: 'in')
          build(:ai_flow_trigger,
            project: project,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
            filter: software_factory_filter(value, operator: operator))
        end

        it 'allows the in operator with true or false', :aggregate_failures do
          expect(build_software_factory_trigger([true])).to be_valid
          expect(build_software_factory_trigger([false])).to be_valid
        end

        it 'rejects the other operators', :aggregate_failures do
          %w[eq ne gt lt contains not_contains not_in].each do |operator|
            flow_trigger = build_software_factory_trigger([true], operator: operator)

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:filter]).to include(
              "contains invalid software_factory_enabled operators for work_item: #{operator}. " \
                'Allowed operators are: in')
          end
        end

        it 'rejects a value that is not a boolean', :aggregate_failures do
          flow_trigger = build_software_factory_trigger(['true', 1])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(
            'contains invalid software_factory_enabled values for work_item: true, 1. ' \
              'Allowed values are: true, false')
        end

        it 'rejects a blank value', :aggregate_failures do
          flow_trigger = build_software_factory_trigger([nil])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter])
            .to include("software_factory_enabled values for work_item can't be blank")
        end

        it 'checks dap_software_factory for the project or its root namespace', :aggregate_failures do
          stub_feature_flags(dap_software_factory: create(:group))

          expect(build_software_factory_trigger([true])).not_to be_valid

          stub_feature_flags(dap_software_factory: project)

          expect(build_software_factory_trigger([true])).to be_valid

          stub_feature_flags(dap_software_factory: project.root_ancestor)

          expect(build_software_factory_trigger([true])).to be_valid
        end

        it 'checks dap_software_factory for the group of a group trigger', :aggregate_failures do
          group_trigger = build(:ai_flow_trigger, :for_inheritance_consumer,
            group: project.root_ancestor,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
            filter: software_factory_filter([true]))

          stub_feature_flags(dap_software_factory: project)

          expect(group_trigger).not_to be_valid
          expect(group_trigger.errors[:filter])
            .to include('software_factory_enabled rules for work_item are not available')

          stub_feature_flags(dap_software_factory: project.root_ancestor)

          expect(group_trigger).to be_valid
        end

        it 'rejects the rule without raising when the trigger has no container', :aggregate_failures do
          stub_feature_flags(dap_software_factory: project.root_ancestor)

          flow_trigger = build_software_factory_trigger([true])
          flow_trigger.project = nil

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter])
            .to include('software_factory_enabled rules for work_item are not available')
        end

        context 'when dap_software_factory is disabled' do
          let(:unavailable_error) { 'software_factory_enabled rules for work_item are not available' }

          before do
            stub_feature_flags(dap_software_factory: false)
          end

          # Stores the rule as before the flag went off.
          def stored_software_factory_trigger(value)
            flow_trigger = create(:ai_flow_trigger,
              project: project,
              event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]])
            flow_trigger.update_column(:filter, software_factory_filter(value))

            flow_trigger.reload
          end

          it 'rejects a new rule', :aggregate_failures do
            flow_trigger = build_software_factory_trigger([true])

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:filter]).to include(unavailable_error)
          end

          it 'allows other edits of a trigger with a stored rule' do
            flow_trigger = stored_software_factory_trigger([true])

            flow_trigger.active = false

            expect(flow_trigger).to be_valid
          end

          it 'allows the removal of a stored rule' do
            flow_trigger = stored_software_factory_trigger([true])

            flow_trigger.filter = {
              'work_item' => { 'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => ['created'] }] }
            }

            expect(flow_trigger).to be_valid
          end

          it 'rejects a change of a stored rule', :aggregate_failures do
            flow_trigger = stored_software_factory_trigger([true])

            flow_trigger.filter = software_factory_filter([false])

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:filter]).to include(unavailable_error)
          end
        end
      end
    end

    describe 'user_is_service_account' do
      it 'rejects regular user' do
        regular_user = create(:user)
        flow_trigger = build(:ai_flow_trigger, project: project, user: regular_user)

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:user]).to include('user must be a service account')
      end
    end

    describe 'goals' do
      let(:mention) { [::Ai::FlowTrigger::EVENT_TYPES[:mention]] }

      def unused_event_type_error(event_types)
        format(
          s_('AICatalog|Instructions cannot be set for an event type the trigger does not use: %{event_types}.'),
          event_types: event_types
        )
      end

      it 'rejects a goal on a flow that does not accept one' do
        flow_trigger = build_consumer_trigger(foundational_item, :with_goals)
        expected = ::Ai::Catalog::FoundationalFlow.code_review_v1.translated_display_name

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base]).to include(
          format(s_('AICatalog|Instructions cannot be set for the %{flow_name} flow.'), flow_name: expected)
        )
      end

      it 'accepts a goal on a custom flow' do
        expect(build_consumer_trigger(custom_item, :with_goals)).to be_valid
      end

      it 'accepts a goal on an external agent' do
        expect(build_consumer_trigger(external_agent_item, :with_goals)).to be_valid
      end

      it 'accepts a goal on a configuration path trigger' do
        expect(build(:ai_flow_trigger, :with_goals, project: project, config_path: 'path/to/config.yml')).to be_valid
      end

      it 'leaves a trigger on an unsupported flow valid when no goal is set' do
        expect(build_consumer_trigger(foundational_item)).to be_valid
      end

      # An item that is not a flow has no name for the goal error to report.
      it 'refuses a goal on an item that is not a flow without raising' do
        flow_trigger = build(:ai_flow_trigger, :for_catalog_consumer, :with_goals, project: project,
          ai_catalog_item_consumer: create(:ai_catalog_item_consumer, project: project,
            item: create(:ai_catalog_agent, :public)))

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base]).to include('ai_catalog_item_consumer is not a flow')
      end

      it 'rejects a goal for an event type the trigger does not listen to' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention,
          goals: { 'assign' => 'Triage this issue.' })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base]).to contain_exactly(unused_event_type_error('assign'))
      end

      it 'rejects every goal when the event type id is unknown' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: [99],
          goals: { 'mention' => 'Summarise this.' })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:base]).to contain_exactly(unused_event_type_error('mention'))
      end

      # The mutation sends errors.full_messages, so a :base sentence and a schema
      # error on the attribute have to arrive in one list.
      it 'reports goal errors from both surfaces in full_messages' do
        flow_trigger = build_consumer_trigger(foundational_item, :with_goals)
        flow_trigger.goals = { 'assign' => 'x' * 4097 }

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors.full_messages).to contain_exactly(
          a_string_matching(/is greater than: 4096/),
          format(
            s_('AICatalog|Instructions cannot be set for the %{flow_name} flow.'),
            flow_name: ::Ai::Catalog::FoundationalFlow.code_review_v1.translated_display_name
          )
        )
      end

      it 'rejects a goal longer than the schema allows' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention,
          goals: { 'mention' => 'x' * 4097 })

        expect(flow_trigger).not_to be_valid
        expect(flow_trigger.errors[:goals]).to include('string length at `/mention` is greater than: 4096')
      end

      it 'accepts a goal at the maximum length' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention,
          goals: { 'mention' => 'x' * 4096 })

        expect(flow_trigger).to be_valid
      end

      describe 'normalisation' do
        it 'strips surrounding whitespace' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention,
            goals: { 'mention' => '  Summarise this.  ' })
          flow_trigger.validate

          expect(flow_trigger.goals).to eq({ 'mention' => 'Summarise this.' })
        end

        # Otherwise a blank value persists as a second, meaningless "unset" state.
        it 'drops blank and whitespace-only goals' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention,
            goals: { 'mention' => '   ' })
          flow_trigger.validate

          expect(flow_trigger.goals).to eq({})
        end

        it 'keeps a non-string value so the schema rejects it' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention,
            goals: { 'mention' => false })

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:goals]).to include('value at `/mention` is not a string')
        end

        it 'treats nil as no goals' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention)
          flow_trigger.goals = nil

          expect(flow_trigger).to be_valid
          expect(flow_trigger.goals).to eq({})
        end

        it 'leaves a non-hash value for the schema to reject' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention)
          flow_trigger.goals = 'Summarise this.'

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:goals]).to include('value at root is not an object')
        end

        # The jsonb attribute casts through JSON, so a symbol key arrives as a string.
        it 'stores a symbol key as a string' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention)
          flow_trigger.goals = { mention: 'Summarise this.' }

          expect(flow_trigger).to be_valid
          expect(flow_trigger.goals).to eq({ 'mention' => 'Summarise this.' })
        end

        it 'lets a blank goal pass the unsupported-flow check' do
          flow_trigger = build_consumer_trigger(foundational_item)
          flow_trigger.goals = { 'mention' => '' }

          expect(flow_trigger).to be_valid
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(ai_flow_trigger_goals: false)
        end

        it 'rejects a newly set goal' do
          flow_trigger = build_consumer_trigger(custom_item, :with_goals)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:goals]).to include('are not available')
        end

        it 'still saves a trigger that already carries a goal' do
          stub_feature_flags(ai_flow_trigger_goals: true)
          flow_trigger = build_consumer_trigger(custom_item, :with_goals)
          flow_trigger.save!

          stub_feature_flags(ai_flow_trigger_goals: false)
          flow_trigger.active = false

          expect(flow_trigger).to be_valid
        end

        it 'leaves a trigger with no goal valid' do
          expect(build_consumer_trigger(custom_item)).to be_valid
        end

        # The shape error is the accurate one, so the flag guard stays quiet.
        it 'reports only the schema error for a non-hash value' do
          flow_trigger = build(:ai_flow_trigger, project: project, event_types: mention)
          flow_trigger.goals = 'Summarise this.'

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:goals]).to contain_exactly('value at root is not an object')
        end

        context 'with a persisted trigger that carries goals' do
          let(:assign) { ::Ai::FlowTrigger::EVENT_TYPES[:assign] }

          let(:flow_trigger) do
            stub_feature_flags(ai_flow_trigger_goals: true)

            trigger = build(:ai_flow_trigger, project: project, event_types: mention + [assign],
              goals: { 'mention' => 'Summarise this.', 'assign' => 'Triage this issue.' })
            trigger.save!
            stub_feature_flags(ai_flow_trigger_goals: false)

            trigger.reload
          end

          it 'accepts dropping an event type together with its goal' do
            flow_trigger.event_types = mention
            flow_trigger.goals = { 'mention' => 'Summarise this.' }

            expect(flow_trigger).to be_valid
          end

          it 'accepts clearing every goal' do
            flow_trigger.event_types = mention
            flow_trigger.goals = {}

            expect(flow_trigger).to be_valid
          end

          it 'rejects dropping an event type while its goal stays' do
            flow_trigger.event_types = mention

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:base]).to contain_exactly(unused_event_type_error('assign'))
          end

          it 'rejects editing an existing goal' do
            flow_trigger.goals = { 'mention' => 'Changed.', 'assign' => 'Triage this issue.' }

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:goals]).to include('are not available')
          end
        end
      end
    end

    describe 'exactly_one_config_source' do
      let_it_be(:item_consumer) do
        create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: create(:ai_catalog_flow))
      end

      context 'when using config_path only' do
        it 'is valid' do
          flow_trigger = build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml')

          expect(flow_trigger).to be_valid
        end
      end

      context 'when using ai_catalog_item_consumer only' do
        it 'is valid' do
          flow_trigger =
            build(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).to be_valid
        end
      end

      context 'when using both config_path and ai_catalog_item_consumer' do
        it 'is invalid' do
          error_message = 'Exactly one of config_path, ai_catalog_item_consumer must be present'
          flow_trigger = build(:ai_flow_trigger,
            project: project,
            config_path: 'path/to/config.yml',
            ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include(error_message)
        end
      end

      context 'when using neither config_path nor ai_catalog_item_consumer' do
        it 'is invalid' do
          error_message = 'Exactly one of config_path, ai_catalog_item_consumer must be present'
          flow_trigger = build(:ai_flow_trigger, config_path: nil)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include(error_message)
        end
      end
    end

    describe 'supported_events_match_foundational_flow' do
      let_it_be(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item) }

      context 'when event types and filter keys match supported events' do
        it 'is valid' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
            filter: { 'pipeline_hooks' => { 'match' => 'all', 'rules' => [] } })

          expect(flow_trigger).to be_valid
        end
      end

      context 'when event types are not supported by the foundational flow' do
        it 'is invalid' do
          flow_trigger = build(:ai_flow_trigger,
            project: project,
            config_path: nil,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:event_types]).to include(
            'contains event types not supported by this foundational flow'
          )
        end
      end

      context 'when filter contains unsupported event type keys' do
        it 'is invalid' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
            filter: { 'mention' => { 'match' => 'all', 'rules' => [] } })

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:filter]).to include(
            'contains filters for unsupported event types: mention'
          )
        end
      end

      context 'when the foundational flow has no supported_events' do
        let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'code_review/v1') }

        it 'allows any event types and filter keys' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
            filter: { 'mention' => { 'match' => 'all', 'rules' => [] } })

          expect(flow_trigger).to be_valid
        end
      end

      context 'when the foundational flow disallows events' do
        using RSpec::Parameterized::TableSyntax

        where(:foundational_flow_reference) do
          %w[resolve_sast_vulnerability/v1 sast_fp_detection/v1 secrets_fp_detection/v1]
        end

        with_them do
          let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: foundational_flow_reference) }

          it 'is invalid when event_types are present' do
            flow_trigger = build(:ai_flow_trigger,
              :for_catalog_consumer,
              project: project,
              ai_catalog_item_consumer: item_consumer,
              event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])

            expect(flow_trigger).not_to be_valid
            expect(flow_trigger.errors[:event_types]).to include(
              'contains event types not supported by this foundational flow'
            )
          end
        end
      end

      context 'when the foundational flow reference does not match a defined flow' do
        let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'unknown/v1') }

        it 'allows any event types' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

          expect(flow_trigger).to be_valid
        end
      end

      context 'when the item is not a foundational flow' do
        let(:item) { create(:ai_catalog_flow) }

        it 'allows any event types and filter keys' do
          flow_trigger = build(:ai_flow_trigger,
            :for_catalog_consumer,
            project: project,
            ai_catalog_item_consumer: item_consumer,
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

          expect(flow_trigger).to be_valid
        end
      end
    end

    describe 'catalog_item_valid' do
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }

      let(:item) { create(:ai_catalog_flow) }

      context 'when item consumer project does not match the project' do
        let(:project) { create(:project) }

        it 'is invalid' do
          error_message = 'Exactly one of config_path, ai_catalog_item_consumer must be present'
          flow_trigger = build(:ai_flow_trigger, project: project, ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include(error_message)
        end
      end

      context 'when item is not a flow' do
        let(:item) { create(:ai_catalog_agent) }

        it 'is invalid' do
          flow_trigger = build(:ai_flow_trigger, project: project, ai_catalog_item_consumer: item_consumer)

          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:base]).to include('ai_catalog_item_consumer is not a flow')
        end
      end
    end

    context 'when ai_catalog_item_consumer is nil' do
      subject(:flow_trigger) do
        build(:ai_flow_trigger, project: project, ai_catalog_item_consumer: nil)
      end

      it { is_expected.to validate_presence_of(:user) }
    end

    context 'when ai_catalog_item_consumer is present' do
      let_it_be(:ai_catalog_item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }

      subject(:flow_trigger) do
        build(
          :ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: ai_catalog_item_consumer
        )
      end

      it { is_expected.to validate_absence_of(:user) }
      it { is_expected.to be_valid }

      context 'when ai_catalog_item_consumer does not have an active service account' do
        let_it_be(:ai_catalog_item_consumer) { create(:ai_catalog_item_consumer, project:) }

        it 'is invalid' do
          expect(flow_trigger).not_to be_valid
          expect(flow_trigger.errors[:ai_catalog_item_consumer_id]).to include('must have an active service account')
        end
      end
    end
  end

  describe '#foundational_flow' do
    subject(:foundational_flow) { trigger.foundational_flow }

    context 'when flow trigger has a catalog item consumer with a foundational flow' do
      let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it { is_expected.to eq(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1) }
    end

    context 'when flow trigger has no catalog item consumer' do
      let(:trigger) { build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml') }

      it { is_expected.to be_nil }
    end

    context 'when catalog item has no foundational flow reference' do
      let(:item) { create(:ai_catalog_flow) }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer)
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#goal_supported?' do
    using RSpec::Parameterized::TableSyntax

    let(:config_path_trigger) { build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml') }
    let(:custom_flow_trigger) { build_consumer_trigger(custom_item) }
    let(:external_agent_trigger) { build_consumer_trigger(external_agent_item) }
    let(:maintained_agent_trigger) { build_consumer_trigger(maintained_external_agent_item) }
    let(:foundational_flow_trigger) { build_consumer_trigger(foundational_item) }

    where(:trigger, :supported) do
      ref(:config_path_trigger)         | true
      ref(:custom_flow_trigger)         | true
      ref(:external_agent_trigger)      | true
      ref(:maintained_agent_trigger)    | true
      ref(:foundational_flow_trigger)   | false
    end

    with_them do
      it { expect(trigger.goal_supported?).to be(supported) }
    end

    # Stubs the item, not the globally cached FoundationalFlow definition, which
    # would leak the double into every later spec file.
    it 'is true once the flow opts in' do
      flow_trigger = build_consumer_trigger(foundational_item)
      allow(flow_trigger.ai_catalog_item_consumer.item).to receive(:accepts_trigger_goal?).and_return(true)

      expect(flow_trigger.goal_supported?).to be(true)
    end
  end

  describe '#stored_goal_for' do
    let(:trigger) { build(:ai_flow_trigger, :with_goals, project: project) }

    it 'returns the goal stored for that event type' do
      expect(trigger.stored_goal_for(:assign)).to eq('Triage this issue and add a severity label.')
      expect(trigger.stored_goal_for('assign')).to eq('Triage this issue and add a severity label.')
    end

    it 'returns nil for an event type with no goal of its own' do
      expect(trigger.stored_goal_for(:mention)).to be_nil
    end
  end

  describe 'on-finish settings' do
    let(:trigger) { build(:ai_flow_trigger, project: project) }

    it 'strips the status and stores a blank one as nil' do
      trigger.status_on_finish = '  In review  '
      expect(trigger.status_on_finish).to eq('In review')

      trigger.status_on_finish = '   '
      expect(trigger.status_on_finish).to be_nil
    end

    it { expect(trigger).to validate_length_of(:status_on_finish).is_at_most(255) }

    describe '#applies_on_finish?' do
      it 'is false by default' do
        expect(trigger.applies_on_finish?).to be(false)
      end

      it 'is true with a status or with ready merge requests' do
        expect(build(:ai_flow_trigger, status_on_finish: 'In review').applies_on_finish?).to be(true)
        expect(build(:ai_flow_trigger, ready_merge_requests_on_finish: true).applies_on_finish?).to be(true)
      end
    end

    describe 'Status changed action with statuses' do
      let(:error) do
        s_('AICatalog|On-finish settings require the work item event type with Status changed ' \
          'as its only action and at least one status.')
      end

      let(:event_types) { [::Ai::FlowTrigger::EVENT_TYPES[:work_item]] }
      let(:action_rule) { { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] } }
      let(:status_rule) { { 'field' => 'status.name', 'operator' => 'in', 'value' => ['Planning'] } }
      let(:filter) { { 'work_item' => { 'rules' => [action_rule, status_rule] } } }

      let(:trigger) do
        build(:ai_flow_trigger, project: project, event_types: event_types, filter: filter,
          status_on_finish: 'In review')
      end

      it 'accepts on-finish settings when Status changed is the only work item action and statuses are set' do
        expect(trigger).to be_valid
      end

      context 'with a match-any group next to the action and status rules' do
        let(:filter) do
          {
            'work_item' => {
              'rules' => [
                action_rule,
                status_rule,
                {
                  'type' => 'group',
                  'match' => 'any',
                  'rules' => [status_rule.merge('operator' => 'ne', 'value' => 'Done')]
                }
              ]
            }
          }
        end

        it { expect(trigger).to be_valid }
      end

      context 'with an explicit match-all scope' do
        let(:filter) { { 'work_item' => { 'match' => 'all', 'rules' => [action_rule, status_rule] } } }

        it { expect(trigger).to be_valid }
      end

      context 'with another event type next to the work item event type' do
        let(:event_types) { [::Ai::FlowTrigger::EVENT_TYPES[:mention], ::Ai::FlowTrigger::EVENT_TYPES[:work_item]] }

        it { expect(trigger).to be_valid }
      end

      context 'without the work item event type' do
        let(:event_types) { [::Ai::FlowTrigger::EVENT_TYPES[:mention]] }

        it 'rejects the settings' do
          expect(trigger).not_to be_valid
          expect(trigger.errors[:base]).to include(error)
        end
      end

      context 'with ready_merge_requests_on_finish only' do
        let(:trigger) do
          build(:ai_flow_trigger, project: project, event_types: event_types, filter: {},
            ready_merge_requests_on_finish: true)
        end

        it 'rejects the settings' do
          expect(trigger).not_to be_valid
          expect(trigger.errors[:base]).to include(error)
        end
      end

      # One top-level `in` rule per field, as the trigger form reads them, in a scope that matches all rules.
      # Each row changes one thing from the accepted filter.
      where(:case_name, :work_item_scope) do
        action = { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] }
        status = { 'field' => 'status.name', 'operator' => 'in', 'value' => ['Planning'] }
        both = action.merge('value' => %w[created status_changed])
        group = ->(rule) { { 'type' => 'group', 'rules' => [rule] } }

        [
          ['no work item filter', nil],
          ['Created next to Status changed', { 'rules' => [both, status] }],
          ['Created with a status rule', { 'rules' => [action.merge('value' => ['created']), status] }],
          ['a status rule only', { 'rules' => [status] }],
          ['Status changed without a status', { 'rules' => [action] }],
          ['a match-any scope', { 'match' => 'any', 'rules' => [action, status] }],
          ['an eq action rule', { 'rules' => [action.merge('operator' => 'eq'), status] }],
          ['a not_in action rule', { 'rules' => [action.merge('operator' => 'not_in'), status] }],
          ['two action rules', { 'rules' => [action, action, status] }],
          ['an action rule in a nested group', { 'rules' => [group.call(action), status] }],
          ['a not_in status rule', { 'rules' => [action, status.merge('operator' => 'not_in')] }],
          ['a status value that is not a list', { 'rules' => [action, status.merge('value' => 'Planning')] }],
          ['a status list without a string', { 'rules' => [action, status.merge('value' => [123])] }],
          ['two status rules', { 'rules' => [action, status, status] }],
          ['a status rule in a nested group', { 'rules' => [action, group.call(status)] }]
        ]
      end

      with_them do
        let(:filter) { work_item_scope ? { 'work_item' => work_item_scope } : {} }

        it 'rejects the settings' do
          expect(trigger).not_to be_valid
          expect(trigger.errors[:base]).to include(error)
        end
      end

      context 'with a malformed filter' do
        let(:filter) { [] }

        it 'rejects the settings without raising' do
          expect { trigger.valid? }.not_to raise_error
          expect(trigger.errors[:base]).to include(error)
        end
      end
    end

    it 'rejects a nil ready_merge_requests_on_finish' do
      trigger.ready_merge_requests_on_finish = nil

      expect(trigger).not_to be_valid
      expect(trigger.errors[:ready_merge_requests_on_finish]).to be_present
    end
  end

  describe '#foundational_flow_precondition' do
    subject(:foundational_flow) { trigger.foundational_flow_precondition }

    context 'when foundational flow has a precondition' do
      let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it { is_expected.to eq(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1.precondition) }
    end

    context 'when there is no foundational flow' do
      let(:trigger) { build(:ai_flow_trigger, project: project, config_path: 'path/to/config.yml') }

      it { is_expected.to be_nil }
    end

    context 'when foundational flow has no precondition' do
      let(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'code_review/v1') }
      let(:item_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
      let(:trigger) do
        build(:ai_flow_trigger, project: project, config_path: nil, ai_catalog_item_consumer: item_consumer)
      end

      it { is_expected.to be_nil }
    end
  end

  describe 'database constraints' do
    it 'has correct table name' do
      expect(described_class.table_name).to eq('ai_flow_triggers')
    end

    context 'when using loose foreign key on users.id' do
      it_behaves_like 'cleanup by a loose foreign key' do
        let(:lfk_column) { :user_id }
        let!(:model) { create(:ai_flow_trigger, project: project) }
        let!(:parent) { model.user }
      end
    end

    context 'when using loose foreign key on users.id for the autonomous service account' do
      it_behaves_like 'cleanup by a loose foreign key' do
        let(:lfk_column) { :autonomous_service_account_id }
        let!(:model) do
          create(:ai_flow_trigger, :for_catalog_consumer,
            event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
            autonomous_service_account: create(:service_account))
        end

        let!(:parent) { model.autonomous_service_account }
      end
    end

    context 'when using loose foreign key on projects.id' do
      it_behaves_like 'cleanup by a loose foreign key' do
        let!(:model) { create(:ai_flow_trigger, project: project) }
        let!(:parent) { model.project }
      end
    end
  end

  describe 'factory' do
    it 'creates a valid flow trigger' do
      flow_trigger = build(:ai_flow_trigger,
        project: project,
        user: user,
        description: 'Test flow trigger',
        event_types: [0])

      expect(flow_trigger).to be_valid
    end

    it 'can be created and persisted' do
      expect do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          description: 'Test flow trigger',
          event_types: [0])
      end.to change { described_class.count }.by(1)
    end
  end

  describe 'event_types_are_valid validation' do
    it 'allows multiple valid event types' do
      valid_types = Ai::FlowTrigger::EVENT_TYPES.values - Ai::FlowTrigger::AUTONOMOUS_EVENT_TYPE_IDS
      flow_trigger = build(:ai_flow_trigger, project: project, event_types: valid_types)

      expect(flow_trigger).to be_valid
    end

    # The list above drops the autonomous types because they cannot be mixed,
    # not because they are invalid.
    it 'allows an autonomous event type on its own' do
      flow_trigger = build(:ai_flow_trigger, :autonomous, project: project,
        event_types: Ai::FlowTrigger::AUTONOMOUS_EVENT_TYPE_IDS)

      expect(flow_trigger).to be_valid
    end

    it 'rejects invalid event types' do
      flow_trigger = build(:ai_flow_trigger, project: project, event_types: [99])

      expect(flow_trigger).not_to be_valid
      expect(flow_trigger.errors[:event_types]).to include('contains invalid event types: 99')
    end

    it 'rejects mixed valid and invalid event types' do
      flow_trigger = build(:ai_flow_trigger, project: project, event_types: [0, 99, 100])

      expect(flow_trigger).not_to be_valid
      expect(flow_trigger.errors[:event_types]).to include('contains invalid event types: 99, 100')
    end
  end

  describe 'timestamps' do
    let_it_be_with_reload(:flow_trigger) do
      create(:ai_flow_trigger, project: project, user: user, description: 'Test flow trigger')
    end

    it 'sets created_at and updated_at on creation' do
      expect(flow_trigger.created_at).to be_present
      expect(flow_trigger.updated_at).to be_present
    end

    it 'updates updated_at on modification' do
      original_updated_at = flow_trigger.updated_at

      travel_to(1.minute.from_now) do
        flow_trigger.update!(description: 'Updated description')

        expect(flow_trigger.updated_at).to be > original_updated_at
      end
    end
  end

  describe '.registered_for?' do
    let_it_be(:project) { create(:project) }
    let_it_be(:service_account) { create(:service_account) }

    context 'when project_id is nil' do
      it 'returns false' do
        expect(described_class.registered_for?(nil, :work_item)).to be false
      end
    end

    context 'when no flow triggers exist for the project' do
      it 'returns false' do
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end
    end

    context 'when a flow trigger exists but for a different event type' do
      before do
        create(:ai_flow_trigger, project: project, user: service_account,
          event_types: [described_class::EVENT_TYPES[:mention]])
      end

      it 'returns false' do
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end
    end

    context 'when a matching flow trigger exists' do
      before do
        create(:ai_flow_trigger, project: project, user: service_account,
          event_types: [described_class::EVENT_TYPES[:work_item]])
      end

      it 'returns true' do
        expect(described_class.registered_for?(project.id, :work_item)).to be true
      end
    end

    context 'when the only matching flow trigger is inactive' do
      before do
        create(:ai_flow_trigger, :inactive, project: project, user: service_account,
          event_types: [described_class::EVENT_TYPES[:work_item]])
      end

      it 'returns false' do
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end
    end

    context 'when project_id does not exist' do
      it 'returns false' do
        expect(described_class.registered_for?(non_existing_record_id, :work_item)).to be false
      end
    end

    context 'when a trigger is inherited from the root group' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:subgroup_project) { create(:project, group: create(:group, parent: root_group)) }
      let_it_be(:group_trigger) do
        create(:ai_flow_trigger, :for_inheritance_consumer, group: root_group,
          event_types: [described_class::EVENT_TYPES[:work_item]])
      end

      it 'returns true for a project in a subgroup using a single query' do
        expect do
          expect(described_class.registered_for?(subgroup_project.id, :work_item)).to be true
        end.not_to exceed_query_limit(1)
      end

      it 'returns false for a project outside the root group', :aggregate_failures do
        expect(described_class.registered_for?(create(:project, :in_group).id, :work_item)).to be false
        expect(described_class.registered_for?(project.id, :work_item)).to be false
      end

      it 'returns false when the group trigger is for a different event type' do
        expect(described_class.registered_for?(subgroup_project.id, :mention)).to be false
      end

      it 'returns false when the only group trigger is inactive' do
        inactive_group = create(:group)
        create(:ai_flow_trigger, :for_inheritance_consumer, :inactive, group: inactive_group,
          event_types: [described_class::EVENT_TYPES[:work_item]])

        expect(described_class.registered_for?(create(:project, group: inactive_group).id, :work_item)).to be false
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'returns false' do
          expect(described_class.registered_for?(subgroup_project.id, :work_item)).to be false
        end

        it 'returns true when the project also has its own trigger' do
          create(:ai_flow_trigger, project: subgroup_project, user: service_account,
            event_types: [described_class::EVENT_TYPES[:work_item]])

          expect(described_class.registered_for?(subgroup_project.id, :work_item)).to be true
        end
      end
    end
  end

  describe '.inherited_for_group' do
    let_it_be(:group) { create(:group) }

    it 'returns inheritance triggers for the group' do
      consumer = create(:ai_catalog_item_consumer, :inheritance, group: group)
      trigger = create(:ai_flow_trigger, :for_inheritance_consumer, group: group,
        ai_catalog_item_consumer: consumer)

      expect(described_class.inherited_for_group(group)).to contain_exactly(trigger)
    end

    it 'excludes triggers from a different group' do
      other_group = create(:group)
      consumer = create(:ai_catalog_item_consumer, :inheritance, group: other_group)
      create(:ai_flow_trigger, :for_inheritance_consumer, group: other_group,
        ai_catalog_item_consumer: consumer)

      expect(described_class.inherited_for_group(group)).to be_empty
    end

    it 'excludes direct (non-inheritance) consumers' do
      project = create(:project, group: group)
      create(:ai_flow_trigger, :for_catalog_consumer, project: project)

      expect(described_class.inherited_for_group(group)).to be_empty
    end
  end

  describe '.applicable_to_namespace' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    # Config-path trigger: SA referenced directly via user_id
    let_it_be(:config_trigger) do
      create(:ai_flow_trigger, project: project, event_types: [described_class::EVENT_TYPES[:mention]])
    end

    # Direct catalog consumer trigger: SA owned via parent item consumer
    let_it_be(:child_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }
    let_it_be(:sa_direct) { child_consumer.parent_item_consumer.service_account }
    let_it_be(:direct_trigger) do
      create(:ai_flow_trigger, :for_catalog_consumer, project: project,
        ai_catalog_item_consumer: child_consumer,
        event_types: [described_class::EVENT_TYPES[:assign_reviewer]])
    end

    # Inheritance consumer trigger: SA owned via group-level inheritance consumer
    let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
    let_it_be(:sa_inheritance) { inheritance_consumer.service_account }
    let_it_be(:group_trigger) do
      create(:ai_flow_trigger, :for_inheritance_consumer, group: group,
        ai_catalog_item_consumer: inheritance_consumer,
        event_types: [described_class::EVENT_TYPES[:pipeline_hooks]])
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it 'returns config-path and direct consumer triggers but not inherited' do
        expect(described_class.applicable_to_namespace(group))
          .to contain_exactly(config_trigger, direct_trigger)
      end
    end

    it 'returns all three trigger types' do
      expect(described_class.applicable_to_namespace(group))
        .to contain_exactly(config_trigger, direct_trigger, group_trigger)
    end

    it 'accepts pre-computed project_ids to avoid repeat queries' do
      result = described_class.applicable_to_namespace(group, project_ids: [project.id])

      expect(result).to contain_exactly(config_trigger, direct_trigger, group_trigger)
    end

    context 'when by_service_accounts is given' do
      it 'filters to config-path trigger by user_id' do
        result = described_class.applicable_to_namespace(group, by_service_accounts: [config_trigger.user])

        expect(result).to contain_exactly(config_trigger)
      end

      it 'filters to direct consumer trigger by parent consumer service account' do
        result = described_class.applicable_to_namespace(group, by_service_accounts: [sa_direct])

        expect(result).to contain_exactly(direct_trigger)
      end

      it 'filters to inheritance trigger by its consumer service account' do
        result = described_class.applicable_to_namespace(group, by_service_accounts: [sa_inheritance])

        expect(result).to contain_exactly(group_trigger)
      end
    end
  end

  describe '.applicable_to_project' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    # Config-path trigger
    let_it_be(:config_trigger) do
      create(:ai_flow_trigger, project: project, event_types: [described_class::EVENT_TYPES[:mention]])
    end

    # Direct catalog consumer trigger
    let_it_be(:child_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }
    let_it_be(:sa_direct) { child_consumer.parent_item_consumer.service_account }
    let_it_be(:direct_trigger) do
      create(:ai_flow_trigger, :for_catalog_consumer, project: project,
        ai_catalog_item_consumer: child_consumer,
        event_types: [described_class::EVENT_TYPES[:assign_reviewer]])
    end

    # Inheritance consumer trigger
    let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
    let_it_be(:sa_inheritance) { inheritance_consumer.service_account }
    let_it_be(:group_trigger) do
      create(:ai_flow_trigger, :for_inheritance_consumer, group: group,
        ai_catalog_item_consumer: inheritance_consumer,
        event_types: [described_class::EVENT_TYPES[:pipeline_hooks]])
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it 'returns config-path and direct consumer triggers but not inherited' do
        result = described_class.applicable_to_project(project)

        expect(result).to contain_exactly(config_trigger, direct_trigger)
      end
    end

    it 'returns all three trigger types' do
      result = described_class.applicable_to_project(project)

      expect(result).to contain_exactly(config_trigger, direct_trigger, group_trigger)
    end

    it 'filters by triggered_on event type' do
      result = described_class.applicable_to_project(project, triggered_on: :mention)

      expect(result).to contain_exactly(config_trigger)
    end

    context 'when by_service_accounts is given' do
      it 'filters to config-path trigger by user_id' do
        result = described_class.applicable_to_project(
          project, triggered_on: :mention, by_service_accounts: [config_trigger.user]
        )

        expect(result).to contain_exactly(config_trigger)
      end

      it 'filters to direct consumer trigger by parent consumer service account' do
        result = described_class.applicable_to_project(
          project, by_service_accounts: [sa_direct]
        )

        expect(result).to contain_exactly(direct_trigger)
      end

      it 'filters to inheritance trigger by its consumer service account' do
        result = described_class.applicable_to_project(
          project, by_service_accounts: [sa_inheritance]
        )

        expect(result).to contain_exactly(group_trigger)
      end

      it 'does not return inherited trigger when flag is off' do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)

        result = described_class.applicable_to_project(project, by_service_accounts: [sa_inheritance])

        expect(result).to be_empty
      end
    end

    context 'when container is not a Project' do
      it 'returns none' do
        expect(described_class.applicable_to_project(group)).to eq(described_class.none)
      end
    end
  end

  describe '.applicable_to_container' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:project_trigger) do
      create(:ai_flow_trigger, project: project, event_types: [described_class::EVENT_TYPES[:mention]])
    end

    let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
    let_it_be(:group_trigger) do
      create(:ai_flow_trigger, :for_inheritance_consumer, group: group,
        ai_catalog_item_consumer: inheritance_consumer,
        event_types: [described_class::EVENT_TYPES[:mention]])
    end

    context 'when container is a Project' do
      it 'returns project triggers and inherited group triggers' do
        result = described_class.applicable_to_container(project)

        expect(result).to contain_exactly(project_trigger, group_trigger)
      end
    end

    context 'when container is a Namespace' do
      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'returns only project triggers within the group' do
          expect(described_class.applicable_to_container(group)).to contain_exactly(project_trigger)
        end
      end

      context 'when the feature flag is enabled' do
        it 'returns project triggers and inherited group triggers' do
          expect(described_class.applicable_to_container(group)).to contain_exactly(project_trigger, group_trigger)
        end
      end

      context 'when container is a subgroup' do
        let_it_be(:subgroup) { create(:group, parent: group) }
        let_it_be(:project_in_subgroup) { create(:project, group: subgroup) }
        let_it_be(:subgroup_trigger) do
          create(:ai_flow_trigger, project: project_in_subgroup,
            event_types: [described_class::EVENT_TYPES[:mention]])
        end

        it 'returns triggers for subgroup projects and inherited triggers from root ancestor' do
          expect(described_class.applicable_to_container(subgroup))
            .to contain_exactly(subgroup_trigger, group_trigger)
        end
      end

      context 'when by_service_accounts is nil' do
        it 'returns project triggers and inherited group triggers' do
          expect(described_class.applicable_to_container(group, by_service_accounts: nil))
            .to contain_exactly(project_trigger, group_trigger)
        end
      end
    end

    context 'when container is neither a Project nor a Namespace' do
      it 'returns none' do
        expect(described_class.applicable_to_container("unexpected")).to be_empty
      end
    end
  end

  describe '.event_type_from_id' do
    it 'returns the event type symbol for a known id' do
      expect(described_class.event_type_from_id(0)).to eq(:mention)
      expect(described_class.event_type_from_id(1)).to eq(:assign)
      expect(described_class.event_type_from_id(2)).to eq(:assign_reviewer)
      expect(described_class.event_type_from_id(3)).to eq(:pipeline_hooks)
      expect(described_class.event_type_from_id(4)).to eq(:merge_request_ready)
      expect(described_class.event_type_from_id(5)).to eq(:merge_request_code_conflict)
      expect(described_class.event_type_from_id(6)).to eq(:merge_request)
      expect(described_class.event_type_from_id(7)).to eq(:work_item)
      expect(described_class.event_type_from_id(9)).to eq(:scheduled)
    end

    it 'returns nil for an unknown id' do
      expect(described_class.event_type_from_id(99)).to be_nil
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active triggers' do
        active_trigger = create(:ai_flow_trigger, project: project)
        create(:ai_flow_trigger, :inactive, project: project)

        expect(described_class.active).to contain_exactly(active_trigger)
      end
    end

    describe '.with_ids' do
      it 'filters triggers by id' do
        triggers = create_list(:ai_flow_trigger, 3, project: project)

        expect(project.ai_flow_triggers.with_ids([triggers[0].id, triggers[1].id])).to contain_exactly(
          triggers[0], triggers[1]
        )
      end
    end

    describe '.by_item_consumer_ids' do
      let_it_be(:item_consumer1) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }
      let_it_be(:item_consumer2) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }
      let_it_be(:item_consumer3) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }

      let_it_be(:trigger1) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer1)
      end

      let_it_be(:trigger2) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer2)
      end

      let_it_be(:trigger3) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: item_consumer3)
      end

      let_it_be(:trigger_not_for_consumer) do
        create(:ai_flow_trigger, project: project, ai_catalog_item_consumer: nil, config_path: 'bla')
      end

      it 'returns triggers filtered by item_consumer_ids' do
        expect(described_class.by_item_consumer_ids([item_consumer1.id, item_consumer2.id]))
          .to contain_exactly(trigger1, trigger2)

        expect(described_class.by_item_consumer_ids([item_consumer1.id])).to contain_exactly(trigger1)
        expect(described_class.by_item_consumer_ids([])).to be_empty
        expect(described_class.by_item_consumer_ids(nil)).to contain_exactly(trigger_not_for_consumer)
      end
    end

    describe '.ordered_by_id' do
      let_it_be(:consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, :for_flow, project:) }
      let_it_be(:first) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: consumer)
      end

      let_it_be(:second) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project, ai_catalog_item_consumer: consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it 'returns triggers ordered by id ascending' do
        expect(described_class.by_item_consumer_ids([consumer.id]).ordered_by_id).to eq([first, second])
      end
    end

    describe '.by_service_accounts' do
      subject(:by_service_accounts) do
        described_class.by_service_accounts(
          [
            trigger_for_consumer_with_included_service_account.service_account,
            trigger_for_included_service_account.user
          ]
        )
      end

      let_it_be(:trigger_for_included_service_account) do
        create(:ai_flow_trigger, project: project)
      end

      let_it_be(:trigger_for_excluded_service_account) do
        create(:ai_flow_trigger, project: project)
      end

      let_it_be(:trigger_for_consumer_with_included_service_account) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project)
      end

      let_it_be(:trigger_for_consumer_with_excluded_service_account) do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project)
      end

      it 'returns the triggers filtered by service_account' do
        expect(by_service_accounts).to contain_exactly(
          trigger_for_included_service_account, trigger_for_consumer_with_included_service_account
        )
      end

      it 'does not use a subquery' do
        expect(by_service_accounts.to_sql).not_to include('IN (SELECT "users"."id" FROM "users"')
      end

      context 'with an autonomous trigger holding a dedicated account' do
        let_it_be(:autonomous_account) { create(:service_account, composite_identity_enforced: false) }
        let_it_be(:autonomous_trigger) do
          create(:ai_flow_trigger, :for_catalog_consumer, project: project,
            event_types: [described_class::EVENT_TYPES[:scheduled]],
            autonomous_service_account: autonomous_account)
        end

        it 'leaves it out, because the account answers no interactive event' do
          expect(described_class.by_service_accounts([autonomous_account])).to be_empty
        end
      end

      context 'when querying for nil as well' do
        subject(:by_service_accounts) do
          described_class.by_service_accounts(
            [
              trigger_for_consumer_with_included_service_account.service_account,
              nil
            ]
          )
        end

        it 'filters out the nils' do
          expect(by_service_accounts).to contain_exactly(trigger_for_consumer_with_included_service_account)
        end
      end

      context 'when passing in a relation' do
        subject(:by_service_accounts) do
          described_class.by_service_accounts(
            User.where(id: [trigger_for_consumer_with_included_service_account.service_account.id])
          )
        end

        it 'uses a subquery to get the results' do
          expect(by_service_accounts.to_sql).to include('IN (SELECT "users"."id" FROM "users"')
          expect(by_service_accounts).to contain_exactly(trigger_for_consumer_with_included_service_account)
        end
      end

      context 'with an inheritance consumer trigger' do
        let_it_be(:group) { create(:group) }
        let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
        let_it_be(:inheritance_trigger) do
          create(:ai_flow_trigger, :for_inheritance_consumer, group: group,
            ai_catalog_item_consumer: inheritance_consumer)
        end

        it 'does not return inheritance triggers because the SA is on the consumer itself, not user_id or parent' do
          service_account = inheritance_consumer.service_account

          expect(described_class.by_service_accounts([service_account])).not_to include(inheritance_trigger)
        end
      end
    end

    describe '.include_parent_item_consumer' do
      let_it_be(:trigger) { create(:ai_flow_trigger, :for_catalog_consumer, project: project) }

      it 'preloads the association' do
        loaded_trigger = described_class.where(id: [trigger.id]).include_parent_item_consumer.first

        expect(loaded_trigger.association(:parent_item_consumer)).to be_loaded
      end
    end
  end

  describe '.triggered_on' do
    before do
      stub_const("#{described_class}::EVENT_TYPES", {
        mention: 0,
        comment: 1,
        issue_created: 2
      })
    end

    context 'when filtering by mention event type' do
      let_it_be(:mention_trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          event_types: [0],
          description: 'Mention trigger')
      end

      let_it_be(:multiple_types_trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          event_types: [0, 1],
          description: 'Multiple types trigger')
      end

      let_it_be(:other_type_trigger) do
        create(:ai_flow_trigger,
          project: project,
          user: user,
          event_types: [1, 2],
          description: 'Other type trigger')
      end

      it 'returns triggers that contain the mention event type' do
        result = described_class.triggered_on(:mention)

        expect(result).to contain_exactly(mention_trigger, multiple_types_trigger)
      end

      it 'returns triggers that contain the comment event type' do
        result = described_class.triggered_on(:comment)

        expect(result).to contain_exactly(multiple_types_trigger, other_type_trigger)
      end
    end
  end

  describe '.for_autonomous_service_account' do
    let_it_be(:account) { create(:service_account, composite_identity_enforced: false) }
    let_it_be(:other_project) { create(:project, :in_group) }

    let_it_be(:trigger) do
      create(:ai_flow_trigger, :autonomous, project: project, autonomous_service_account: account)
    end

    it 'returns the triggers backed by the account in the project' do
      expect(described_class.for_autonomous_service_account(account, project)).to contain_exactly(trigger)
    end

    it 'ignores a trigger backed by a different account' do
      create(:ai_flow_trigger, :autonomous, project: project)

      expect(described_class.for_autonomous_service_account(account, project)).to contain_exactly(trigger)
    end

    # Entitlement must not carry across projects, so the same account in another
    # project is not a match.
    it 'ignores the same account in another project' do
      create(:ai_flow_trigger, :autonomous, project: other_project, autonomous_service_account: account)

      expect(described_class.for_autonomous_service_account(account, other_project))
        .not_to include(trigger)
      expect(described_class.for_autonomous_service_account(account, project)).to contain_exactly(trigger)
    end

    it 'returns nil when the service account is missing' do
      expect(described_class.for_autonomous_service_account(nil, project)).to be_empty
    end

    it 'returns nil when the project is missing' do
      expect(described_class.for_autonomous_service_account(account, nil)).to be_empty
    end
  end

  describe 'autonomous trigger validations' do
    let_it_be(:autonomous_account) { create(:service_account, composite_identity_enforced: false) }

    let(:unsupported_target_message) do
      'Scheduled triggers are not supported for external agents or configuration file flows'
    end

    def autonomous_trigger(**attrs)
      build(:ai_flow_trigger, :for_catalog_consumer,
        event_types: [described_class::EVENT_TYPES[:scheduled]],
        autonomous_service_account: autonomous_account, **attrs)
    end

    it 'accepts an autonomous trigger with a non-composite account' do
      expect(autonomous_trigger).to be_valid
    end

    it 'rejects an autonomous trigger whose account enforces composite identity' do
      trigger = autonomous_trigger(
        autonomous_service_account: create(:service_account, composite_identity_enforced: true)
      )

      expect(trigger).to be_invalid
      expect(trigger.errors[:base])
        .to include('The service account for an autonomous trigger must not have composite identity enforced')
    end

    it 'rejects a catalog autonomous trigger with no account of its own' do
      trigger = autonomous_trigger(autonomous_service_account: nil)

      expect(trigger).to be_invalid
      expect(trigger.errors[:autonomous_service_account]).to include("can't be blank")
    end

    it 'rejects mixing autonomous and interactive event types' do
      trigger = autonomous_trigger(
        event_types: [described_class::EVENT_TYPES[:scheduled], described_class::EVENT_TYPES[:mention]]
      )

      expect(trigger).to be_invalid
      expect(trigger.errors[:event_types].join)
        .to include('cannot combine autonomous event types (scheduled) with other event types')
    end

    it 'rejects an autonomous service account on a non-autonomous trigger' do
      trigger = autonomous_trigger(event_types: [described_class::EVENT_TYPES[:mention]])

      expect(trigger).to be_invalid
      expect(trigger.errors[:autonomous_service_account]).to include('must be blank')
    end

    it 'reports only the missing event types when they are blank' do
      trigger = autonomous_trigger(event_types: [])

      expect(trigger).to be_invalid
      expect(trigger.errors[:event_types]).to include("can't be blank")
      expect(trigger.errors[:autonomous_service_account]).to be_empty
    end

    it 'rejects a composite account set by id, without the association loaded' do
      account = create(:service_account, composite_identity_enforced: true)
      trigger = build(:ai_flow_trigger, :for_catalog_consumer,
        event_types: [described_class::EVENT_TYPES[:scheduled]],
        autonomous_service_account_id: account.id)

      expect(trigger.association(:autonomous_service_account)).not_to be_loaded
      expect(trigger).to be_invalid
      expect(trigger.errors[:base])
        .to include('The service account for an autonomous trigger must not have composite identity enforced')
    end

    context 'with a config_path trigger, which would run as a caller-supplied user' do
      def config_path_trigger(composite:)
        build(:ai_flow_trigger,
          event_types: [described_class::EVENT_TYPES[:scheduled]],
          user: create(:service_account, composite_identity_enforced: composite))
      end

      it 'refuses the autonomous event type regardless of composite identity' do
        [true, false].each do |composite|
          trigger = config_path_trigger(composite: composite)

          expect(trigger).to be_invalid
          expect(trigger.errors[:base]).to include(unsupported_target_message)
        end
      end

      it 'still accepts interactive event types' do
        trigger = build(:ai_flow_trigger,
          event_types: [described_class::EVENT_TYPES[:mention]],
          user: create(:service_account, composite_identity_enforced: false))

        expect(trigger).to be_valid
      end
    end

    context 'with an external agent, which runs a third-party CLI' do
      def external_agent_trigger(item, **attrs)
        build(:ai_flow_trigger, :for_catalog_consumer,
          project: project,
          event_types: [described_class::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_account,
          ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
            project: project, item: item),
          **attrs)
      end

      it 'refuses the autonomous event type whether or not GitLab maintains the agent' do
        [external_agent_item, maintained_external_agent_item].each do |item|
          trigger = external_agent_trigger(item)

          expect(trigger).to be_invalid
          expect(trigger.errors[:base]).to include(unsupported_target_message)
        end
      end

      it 'still accepts interactive event types' do
        trigger = external_agent_trigger(external_agent_item,
          event_types: [described_class::EVENT_TYPES[:mention]],
          autonomous_service_account: nil)

        expect(trigger).to be_valid
      end

      it 'refuses repointing an existing scheduled trigger at an external agent' do
        trigger = create(:ai_flow_trigger, :autonomous, project: project)

        trigger.ai_catalog_item_consumer = create(:ai_catalog_item_consumer, :child_item_consumer,
          project: project, item: external_agent_item)

        expect(trigger).to be_invalid
        expect(trigger.errors[:base]).to include(unsupported_target_message)
      end

      it 'still allows deactivating a row that already holds the combination' do
        trigger = external_agent_trigger(external_agent_item)
        trigger.save!(validate: false)

        expect(trigger.update(active: false)).to be(true)
      end
    end

    it 'accepts the autonomous event type on a custom catalog flow' do
      expect(build_consumer_trigger(custom_item, :autonomous)).to be_valid
    end

    it 'accepts the autonomous event type on a foundational flow' do
      expect(build_consumer_trigger(foundational_item, :autonomous)).to be_valid
    end
  end

  describe '#container' do
    context 'when project is set' do
      let(:flow_trigger) { build(:ai_flow_trigger, project: project) }

      it 'returns the project' do
        expect(flow_trigger.container).to eq(project)
      end
    end

    context 'when group is set' do
      let(:flow_trigger) { build(:ai_flow_trigger, :for_inheritance_consumer) }

      it 'returns the group' do
        expect(flow_trigger.container).to eq(flow_trigger.group)
      end
    end
  end

  describe '#service_account' do
    subject(:service_account) { flow_trigger.service_account }

    context 'when user is set' do
      let(:flow_trigger) { build(:ai_flow_trigger) }

      it { is_expected.to eq(flow_trigger.user).and(be_a_kind_of(User)) }
    end

    context 'when ai_catalog_item_consumer is set' do
      let(:flow_trigger) { build(:ai_flow_trigger, :for_catalog_consumer, project: project) }

      it { is_expected.to eq(flow_trigger.ai_catalog_item_consumer.active_service_account).and(be_a_kind_of(User)) }
    end

    # This case shouldn't happen. The code is written in a way to return nil,
    # so that we don't silently fall back to the user association.
    context 'when ai_catalog_item_consumer and user are set, but there is no active service account' do
      let(:ai_catalog_item_consumer) { build(:ai_catalog_item_consumer) }
      let(:user) { build(:user) }

      let(:flow_trigger) { build(:ai_flow_trigger, user:, project:, ai_catalog_item_consumer:) }

      it { is_expected.to be_nil }
    end

    context 'when the trigger has its own autonomous service account' do
      let(:autonomous_service_account) { build(:service_account) }

      let(:flow_trigger) do
        build(:ai_flow_trigger, :for_catalog_consumer,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_service_account)
      end

      it { is_expected.to eq(autonomous_service_account) }
    end

    context 'when ai_catalog_item_consumer has no parent_item_consumer' do
      let_it_be(:consumer_with_no_parent) do
        create(:ai_catalog_item_consumer, :for_flow, project: project, parent_item_consumer: nil)
      end

      let_it_be(:flow_trigger) do
        build(
          :ai_flow_trigger, :for_catalog_consumer,
          project: project, ai_catalog_item_consumer: consumer_with_no_parent
        )
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#service_account_id' do
    subject(:service_account_id) { flow_trigger.service_account_id }

    context 'when user is set' do
      let(:flow_trigger) { create(:ai_flow_trigger) }

      it { is_expected.to eq(flow_trigger.user_id).and(be_an(Integer)) }
    end

    context 'when ai_catalog_item_consumer is set' do
      let(:flow_trigger) { create(:ai_flow_trigger, :for_catalog_consumer) }

      it { is_expected.to eq(flow_trigger.parent_item_consumer.service_account_id).and(be_an(Integer)) }
    end

    context 'when ai_catalog_item_consumer and user are set, but there is no active service account' do
      let(:ai_catalog_item_consumer) { build(:ai_catalog_item_consumer) }
      let(:user) { build(:user) }

      let(:flow_trigger) { build(:ai_flow_trigger, user:, project:, ai_catalog_item_consumer:) }

      it { is_expected.to be_nil }
    end

    context 'when the trigger has its own autonomous service account' do
      let(:autonomous_service_account) { create(:service_account) }

      let(:flow_trigger) do
        build(:ai_flow_trigger, :for_catalog_consumer,
          event_types: [described_class::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_service_account)
      end

      it 'wins over the consumer shared account' do
        expect(service_account_id).to eq(autonomous_service_account.id)
        expect(service_account_id).not_to eq(flow_trigger.parent_item_consumer&.service_account_id)
      end
    end

    context 'when ai_catalog_item_consumer has no parent_item_consumer' do
      let_it_be(:consumer_with_no_parent) do
        create(:ai_catalog_item_consumer, :for_flow, project: project, parent_item_consumer: nil)
      end

      let_it_be(:flow_trigger) do
        build(
          :ai_flow_trigger, :for_catalog_consumer,
          project: project, ai_catalog_item_consumer: consumer_with_no_parent
        )
      end

      it { is_expected.to be_nil }
    end

    context 'when ai_catalog_item_consumer_id references a record that no longer exists' do
      let(:flow_trigger) do
        build(:ai_flow_trigger, project: project, ai_catalog_item_consumer_id: non_existing_record_id)
      end

      it { is_expected.to be_nil }
    end

    context 'when ai_catalog_item_consumer is an inheritance consumer with its own service account' do
      let(:flow_trigger) { create(:ai_flow_trigger, :for_inheritance_consumer) }

      it { is_expected.to eq(flow_trigger.ai_catalog_item_consumer.service_account_id).and(be_an(Integer)) }
    end
  end

  describe '#autonomous_only?' do
    using RSpec::Parameterized::TableSyntax

    where(:event_types, :autonomous_only) do
      [Ai::FlowTrigger::EVENT_TYPES[:scheduled]]                                         | true
      [Ai::FlowTrigger::EVENT_TYPES[:scheduled], Ai::FlowTrigger::EVENT_TYPES[:mention]] | false
      [Ai::FlowTrigger::EVENT_TYPES[:mention]]                                           | false
      []                                                                                 | false
      nil                                                                                | false
    end

    with_them do
      it 'returns true only when all event types are autonomous' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: event_types)

        expect(flow_trigger.autonomous_only?).to eq(autonomous_only)
      end
    end
  end

  describe '#includes_autonomous?' do
    using RSpec::Parameterized::TableSyntax

    where(:event_types, :includes_autonomous) do
      [Ai::FlowTrigger::EVENT_TYPES[:scheduled]]                                         | true
      [Ai::FlowTrigger::EVENT_TYPES[:scheduled], Ai::FlowTrigger::EVENT_TYPES[:mention]] | true
      [Ai::FlowTrigger::EVENT_TYPES[:mention]]                                           | false
      []                                                                                 | false
      nil                                                                                | false
    end

    with_them do
      it 'returns true when any event type is autonomous' do
        flow_trigger = build(:ai_flow_trigger, project: project, event_types: event_types)

        expect(flow_trigger.includes_autonomous?).to eq(includes_autonomous)
      end
    end
  end
end
