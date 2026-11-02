# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::CloudEventsFlowTriggerWorker, feature_category: :dap_triggers do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestCloudEventsFlowTriggerWorker'
      end

      include Ai::CloudEventsFlowTriggerWorker

      def self.cloud_event_class
        MergeRequests::ApprovedCloudEvent
      end

      def self.event_type
        :merge_request
      end

      def self.action
        'approved'
      end
    end
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) do
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]]
    )
  end

  let(:approved_at) { Time.zone.parse('2026-05-08T10:00:00Z') }
  let(:cloud_event) do
    MergeRequests::ApprovedCloudEvent.build(
      merge_request: merge_request,
      current_user: user,
      approval: instance_double(Approval, created_at: approved_at)
    )
  end

  let(:worker) { worker_class.new }
  let(:filter_evaluator) { instance_double(Ai::FlowTriggers::FilterEvaluator, allowed?: true) }
  let(:run_service) { instance_double(Ai::FlowTriggers::RunService) }

  describe '#handle_event' do
    subject(:handle_event) { worker.handle_event(cloud_event) }

    before do
      allow(worker).to receive_messages(find_resource_and_container: [merge_request, project], feature_enabled?: true)
      allow(Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_return(filter_evaluator)
      allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
      allow(run_service).to receive(:execute)
    end

    context 'when all conditions are met' do
      it 'dispatches RunService' do
        expect(run_service).to receive(:execute)

        handle_event
      end
    end

    context 'when an inherited group trigger matches' do
      let_it_be(:group) { create(:group) }
      let_it_be(:group_project) { create(:project, group: group) }
      let_it_be(:merge_request_for_group) do
        create(:merge_request, source_project: group_project, target_project: group_project)
      end

      let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
      let_it_be(:inherited_trigger) do
        create(:ai_flow_trigger, :for_inheritance_consumer,
          group: group,
          ai_catalog_item_consumer: inheritance_consumer,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]])
      end

      let(:cloud_event) do
        MergeRequests::ApprovedCloudEvent.build(
          merge_request: merge_request_for_group,
          current_user: user,
          approval: instance_double(Approval, created_at: approved_at)
        )
      end

      before do
        allow(worker).to receive_messages(
          find_resource_and_container: [merge_request_for_group, group_project],
          feature_enabled?: true
        )
      end

      it 'dispatches RunService for the inherited trigger' do
        expect(Ai::FlowTriggers::RunService).to receive(:new).with(
          hash_including(flow_trigger: inherited_trigger)
        ).and_return(run_service)
        expect(run_service).to receive(:execute)

        handle_event
      end
    end

    context 'when the flow trigger is inactive' do
      before do
        Ai::FlowTrigger.find(flow_trigger.id).update!(active: false)
      end

      it 'does not call RunService' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the cloud event class does not match' do
      let(:cloud_event) do
        MergeRequests::ApprovedEvent.new(
          data: { current_user_id: user.id, merge_request_id: merge_request.id, approved_at: approved_at.iso8601 }
        )
      end

      it 'returns early without calling RunService' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when find_resource_and_container returns nil' do
      before do
        allow(worker).to receive(:find_resource_and_container).and_return(nil)
      end

      it 'returns early without calling RunService' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the feature flag is disabled' do
      before do
        allow(worker).to receive(:feature_enabled?).and_return(false)
      end

      it 'returns early without calling RunService' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the event was caused by a flow acting with a composite identity', :request_store do
      let_it_be(:flow_service_account) { create(:user, :service_account, composite_identity_enforced: true) }

      let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

      let(:duo_workflow_id) { parent_workflow.id.to_s }
      let(:cloud_event) do
        ::Gitlab::ApplicationContext.with_context(duo_workflow_id: duo_workflow_id) do
          MergeRequests::ApprovedCloudEvent.build(
            merge_request: merge_request,
            current_user: user,
            approval: instance_double(Approval, created_at: approved_at)
          )
        end
      end

      before do
        stub_feature_flags(ai_flow_trigger_chaining: false)
        ::Gitlab::Auth::Identity.fabricate(flow_service_account).link!(user, context: :authentication)
      end

      it 'does not call RunService and logs the reason' do
        expect(worker.logger).to receive(:info).with(hash_including(
          'message' => 'Event caused by a flow, skipping flow triggers.',
          'reason' => :non_human_trigger_not_permitted,
          'gitlab_composite_actor_id' => flow_service_account.id
        ))
        expect(run_service).not_to receive(:execute)

        handle_event
      end

      context 'when ai_flow_trigger_chaining is enabled' do
        before do
          stub_feature_flags(ai_flow_trigger_chaining: project.root_ancestor)
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(user, :update_duo_workflow, parent_workflow).and_return(true)
        end

        it 'dispatches RunService with the parent workflow from the event' do
          expect(Ai::FlowTriggers::RunService).to receive(:new)
            .with(hash_including(current_user: user, parent_workflow: parent_workflow)).and_return(run_service)
          expect(run_service).to receive(:execute)

          handle_event
        end

        shared_examples 'skips flow triggers without an authorized parent' do
          it 'does not call RunService and logs the reason' do
            expect(worker.logger).to receive(:info).with(hash_including(
              'message' => 'Event caused by a flow without an authorized parent workflow, skipping flow triggers.',
              'reason' => :non_human_trigger_not_permitted,
              'gitlab_composite_actor_id' => flow_service_account.id,
              Labkit::Fields::DUO_WORKFLOW_ID => duo_workflow_id&.to_i
            ))
            expect(run_service).not_to receive(:execute)

            handle_event
          end
        end

        context 'when the event has no workflow id' do
          let(:duo_workflow_id) { nil }

          it_behaves_like 'skips flow triggers without an authorized parent'
        end

        context 'when the workflow does not exist' do
          let(:duo_workflow_id) { non_existing_record_id.to_s }

          it_behaves_like 'skips flow triggers without an authorized parent'
        end

        context 'when the event user may not update the workflow' do
          let(:duo_workflow_id) { create(:duo_workflows_workflow, project: project).id.to_s }

          it_behaves_like 'skips flow triggers without an authorized parent'
        end
      end
    end

    context 'when the user does not exist' do
      before do
        allow(cloud_event).to receive(:current_user).and_return(nil)
      end

      it 'returns early without calling RunService' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when passes_event_checks? returns false' do
      before do
        allow(worker).to receive(:passes_event_checks?).and_return(false)
      end

      it 'does not dispatch flow triggers' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when passes_trigger_checks? returns false for the flow trigger' do
      before do
        allow(worker).to receive(:passes_trigger_checks?)
          .with(flow_trigger, cloud_event, merge_request, nil).and_return(false)
      end

      it 'does not dispatch the flow trigger' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the filter does not match' do
      let(:filter_evaluator) { instance_double(Ai::FlowTriggers::FilterEvaluator, allowed?: false) }

      it 'does not dispatch RunService' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'with an action defined' do
      it 'passes action in filter data' do
        expect(Ai::FlowTriggers::FilterEvaluator).to receive(:new).with(
          flow_trigger: flow_trigger,
          hook_scope: :merge_request,
          data: { 'action' => 'approved' }
        ).and_return(filter_evaluator)

        handle_event
      end

      it 'passes action in execution params' do
        expect(run_service).to receive(:execute).with({
          input: merge_request.iid.to_s,
          event: :merge_request,
          action: 'approved'
        })

        handle_event
      end
    end

    context 'without an action defined' do
      let(:worker_class_without_action) do
        Class.new do
          def self.name
            'TestWorkerWithoutAction'
          end

          include Ai::CloudEventsFlowTriggerWorker

          def self.cloud_event_class
            MergeRequests::ApprovedCloudEvent
          end

          def self.event_type
            :merge_request_ready
          end
        end
      end

      let(:worker) { worker_class_without_action.new }

      let_it_be(:flow_trigger_ready) do
        create(:ai_flow_trigger,
          project: project,
          user: service_account,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request_ready]]
        )
      end

      before do
        allow(worker).to receive_messages(find_resource_and_container: [merge_request, project], feature_enabled?: true)
      end

      it 'passes empty filter data' do
        expect(Ai::FlowTriggers::FilterEvaluator).to receive(:new).with(
          flow_trigger: flow_trigger_ready,
          hook_scope: :merge_request_ready,
          data: {}
        ).and_return(filter_evaluator)

        handle_event
      end

      it 'does not include action in execution params' do
        expect(run_service).to receive(:execute).with({
          input: merge_request.iid.to_s,
          event: :merge_request_ready
        })

        handle_event
      end
    end

    context 'with the response of the run' do
      let(:response) { ServiceResponse.error(message: 'flow trigger is not active') }

      before do
        allow(run_service).to receive(:execute).and_return(response)
      end

      it 'passes the response to after_flow_trigger_run' do
        expect(worker).to receive(:after_flow_trigger_run).with(flow_trigger, merge_request, response)

        handle_event
      end
    end

    context 'when RunService raises an error' do
      it 'tracks the exception and continues' do
        allow(run_service).to receive(:execute).and_raise(StandardError.new('boom'))

        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          instance_of(StandardError),
          hash_including(
            flow_trigger_id: flow_trigger.id,
            resource_id: merge_request.id,
            container_id: project.id
          )
        )

        handle_event
      end

      it 'passes an error response to after_flow_trigger_run' do
        allow(run_service).to receive(:execute).and_raise(StandardError.new('boom'))

        expect(worker).to receive(:after_flow_trigger_run).with(flow_trigger, merge_request,
          have_attributes(error?: true, message: 'Flow trigger run raised an error.'))

        handle_event
      end
    end

    context 'when a trigger check raises an error' do
      before do
        allow(worker).to receive(:passes_trigger_checks?).and_raise(StandardError.new('boom'))
      end

      it 'tracks the exception and does not call after_flow_trigger_run', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), hash_including(flow_trigger_id: flow_trigger.id))
        expect(worker).not_to receive(:after_flow_trigger_run)

        handle_event
      end
    end
  end
end
