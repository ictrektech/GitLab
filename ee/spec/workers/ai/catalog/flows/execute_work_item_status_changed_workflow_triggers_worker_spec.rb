# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ExecuteWorkItemStatusChangedWorkflowTriggersWorker,
  feature_category: :dap_triggers do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:work_item) { create(:work_item, project: project, author: user) }
  let_it_be(:status) { ::WorkItems::Statuses::SystemDefined::Status.find(2) }
  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) do
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]]
    )
  end

  let(:cloud_event) { ::WorkItems::StatusChangedEvent.build(work_item: work_item, current_user: user, status: status) }
  let(:resource) { work_item }
  let(:event) { cloud_event }

  let(:wrong_event) do
    ::MergeRequests::DraftStateChangeEvent.new(
      data: { current_user_id: user.id, merge_request_id: non_existing_record_id, new_draft_status: false }
    )
  end

  let(:doomed_resource) { create(:work_item, project: project) }

  let(:doomed_resource_event) do
    ::WorkItems::StatusChangedEvent.build(work_item: doomed_resource, current_user: user, status: status)
  end

  it_behaves_like 'subscribes to event'
  it_behaves_like 'a cloud events flow trigger worker' do
    # Override filter_data to include the status name, the type ID, and the marker injected by filter_data_extras.
    let(:filter_data) do
      {
        'action' => 'status_changed',
        'status' => { 'name' => status.name.to_s },
        'work_item_type_id' => work_item.work_item_type_id,
        'software_factory_enabled' => false
      }
    end

    # Goal templates name the user who changed the status.
    let(:additional_run_params) { { triggered_by_username: user.username } }
  end

  describe '#handle_event' do
    subject(:handle_event) { described_class.new.handle_event(cloud_event) }

    let(:run_service) { instance_double(::Ai::FlowTriggers::RunService) }
    let(:filter_evaluator) { instance_double(::Ai::FlowTriggers::FilterEvaluator, allowed?: true) }

    before do
      allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_return(filter_evaluator)
      allow(::Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
      allow(run_service).to receive(:execute)
    end

    # A rule on a field that the data lacks compares against nil, so a negative operator passes.
    it 'gives the filter a value for every allowed work item field' do
      data = nil
      allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_wrap_original do |original, **kwargs|
        data = kwargs[:data]
        original.call(**kwargs)
      end

      handle_event

      ::Ai::FlowTrigger::ALLOWED_FILTER_FIELDS['work_item'].each_key do |field|
        expect(data.dig(*field.split('.'))).not_to be_nil, "the filter data has no value for #{field}"
      end
    end

    context 'when filter_data_extras returns an action key' do
      before do
        allow_next_instance_of(described_class) do |worker|
          allow(worker).to receive(:filter_data_extras).and_return('action' => 'other', 'status' => { 'name' => 'x' })
        end
      end

      it 'keeps the action defined by the worker class' do
        expect(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).with(
          hash_including(data: { 'action' => 'status_changed', 'status' => { 'name' => 'x' } })
        ).and_return(filter_evaluator)

        handle_event
      end
    end

    context 'when the work item has no project (group-level epic)' do
      let_it_be(:group) { create(:group) }
      let_it_be(:epic) { create(:work_item, :epic, namespace: group, author: user) }

      let(:cloud_event) do
        ::WorkItems::StatusChangedEvent.build(work_item: epic, current_user: user, status: status)
      end

      it 'does not start a flow' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the trigger has a status.name filter' do
      # Separate project so the top-level unfiltered `flow_trigger` does not also fire.
      let_it_be(:filtered_project) { create(:project) }
      let_it_be(:filtered_work_item) { create(:work_item, project: filtered_project, author: user) }

      let(:cloud_event) do
        ::WorkItems::StatusChangedEvent.build(work_item: filtered_work_item, current_user: user, status: status)
      end

      let(:filter) do
        {
          'work_item' => {
            'rules' => [
              { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
              { 'field' => 'status.name', 'operator' => 'in', 'value' => [filtered_status_name] }
            ]
          }
        }
      end

      before do
        create(:ai_flow_trigger,
          project: filtered_project,
          user: service_account,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: filter)

        allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_call_original
      end

      context 'when the new status name matches the filter' do
        let(:filtered_status_name) { status.name.to_s }

        it 'starts a flow' do
          expect(run_service).to receive(:execute)

          handle_event
        end
      end

      context 'when the new status name does not match the filter' do
        let(:filtered_status_name) { 'Some Other Status' }

        it 'does not start a flow' do
          expect(run_service).not_to receive(:execute)

          handle_event
        end
      end
    end

    context 'when the trigger has a work_item_type_id filter' do
      # Separate project so the top-level unfiltered `flow_trigger` does not also fire.
      let_it_be(:typed_project) { create(:project) }
      let_it_be(:task) { create(:work_item, :task, project: typed_project, author: user) }
      let_it_be(:issue) { create(:work_item, project: typed_project, author: user) }
      let_it_be(:typed_flow_trigger) do
        create(:ai_flow_trigger,
          project: typed_project,
          user: service_account,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'status.name', 'operator' => 'in', 'value' => [status.name.to_s] },
                { 'field' => 'work_item_type_id', 'operator' => 'in', 'value' => [task.work_item_type_id] }
              ]
            }
          })
      end

      let(:cloud_event) do
        ::WorkItems::StatusChangedEvent.build(work_item: changed_work_item, current_user: user, status: status)
      end

      before do
        allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_call_original
      end

      context 'when the work item type matches the filter' do
        let(:changed_work_item) { task }

        it 'starts a flow' do
          expect(run_service).to receive(:execute)

          handle_event
        end
      end

      context 'when the work item type does not match the filter' do
        let(:changed_work_item) { issue }

        it 'does not start a flow' do
          expect(run_service).not_to receive(:execute)

          handle_event
        end
      end

      context 'when the event has no work_item_type_id, as before the field existed' do
        let(:cloud_event) do
          event = ::WorkItems::StatusChangedEvent.build(work_item: task, current_user: user, status: status)
          event_data = event.data[:data].except(:work_item_type_id)

          ::WorkItems::StatusChangedEvent.new(data: event.data.merge(data: event_data))
        end

        it 'does not start a flow for an in rule' do
          expect(run_service).not_to receive(:execute)

          handle_event
        end

        # Accepted: events lack the field only while old and new code run side by side during the deploy.
        context 'with a not_in rule' do
          let_it_be(:not_in_flow_trigger) do
            create(:ai_flow_trigger,
              project: typed_project,
              user: service_account,
              event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
              filter: {
                'work_item' => {
                  'rules' => [
                    { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                    { 'field' => 'work_item_type_id', 'operator' => 'not_in', 'value' => [task.work_item_type_id] }
                  ]
                }
              })
          end

          it 'starts a flow, because the missing type is not in the list' do
            expect(::Ai::FlowTriggers::RunService).to receive(:new)
              .with(hash_including(flow_trigger: not_in_flow_trigger)).once.and_return(run_service)
            expect(run_service).to receive(:execute).once

            handle_event
          end
        end
      end
    end

    context 'when the trigger has a software_factory_enabled filter' do
      using RSpec::Parameterized::TableSyntax

      # Separate project so the top-level unfiltered `flow_trigger` does not also fire.
      let_it_be(:factory_project) { create(:project) }
      let_it_be(:planned_work_item) { create(:work_item, project: factory_project, author: user) }
      let_it_be(:unplanned_work_item) { create(:work_item, project: factory_project, author: user) }
      let_it_be(:work_item_without_plan) { create(:work_item, project: factory_project, author: user) }

      let(:cloud_event) do
        ::WorkItems::StatusChangedEvent.build(work_item: event_work_item, current_user: user, status: status)
      end

      before_all do
        create(:work_item_agent_plan, work_item: planned_work_item, ai_planning_enabled: true)
        create(:work_item_agent_plan, work_item: unplanned_work_item)
      end

      before do
        allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_call_original

        create(:ai_flow_trigger,
          project: factory_project,
          user: service_account,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
          filter: {
            'work_item' => {
              'rules' => [
                { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
                { 'field' => 'software_factory_enabled', 'operator' => 'in', 'value' => [rule_value] }
              ]
            }
          })
      end

      where(:rule_value, :event_work_item, :flow_runs) do
        true  | ref(:planned_work_item)      | 1
        true  | ref(:unplanned_work_item)    | 0
        true  | ref(:work_item_without_plan) | 0
        false | ref(:planned_work_item)      | 0
        false | ref(:unplanned_work_item)    | 1
        false | ref(:work_item_without_plan) | 1
      end

      with_them do
        it 'starts a flow only when the marker matches the rule' do
          expect(run_service).to receive(:execute).exactly(flow_runs).times

          handle_event
        end
      end

      # The trigger is created before the flag goes off, as a stored rule.
      context 'when dap_software_factory is disabled' do
        let(:rule_value) { true }

        before do
          stub_feature_flags(dap_software_factory: false)
        end

        where(:event_work_item, :flow_runs) do
          ref(:planned_work_item)      | 1
          ref(:work_item_without_plan) | 0
        end

        with_them do
          it 'still filters with the stored rule' do
            expect(run_service).to receive(:execute).exactly(flow_runs).times

            handle_event
          end
        end
      end
    end
  end
end
