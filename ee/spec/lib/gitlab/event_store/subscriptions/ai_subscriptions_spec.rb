# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::EventStore::Subscriptions::AiSubscriptions, feature_category: :dap_triggers do
  let(:store) do
    Gitlab::EventStore::Store.new do |store|
      described_class.new(store).register
    end
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:merge_request) do
    create(:merge_request, source_project: project, target_project: project, author: user)
  end

  def create_trigger(event_type)
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [Ai::FlowTrigger::EVENT_TYPES[event_type]]
    )
  end

  shared_examples 'queued only for a project with a matching trigger' do |worker, event_type, other_event_type|
    it 'does not queue the worker when the project has no trigger for the event type' do
      expect(worker).not_to receive(:perform_async)

      store.publish(event)
    end

    it 'does not queue the worker for a trigger on another event type' do
      create_trigger(other_event_type)

      expect(worker).not_to receive(:perform_async)

      store.publish(event)
    end

    it 'queues the worker when the project has a trigger for the event type' do
      create_trigger(event_type)

      expect(worker).to receive(:perform_async)

      store.publish(event)
    end
  end

  describe 'merge request ready events' do
    let(:event) { MergeRequests::ReadyEvent.build(merge_request: merge_request, current_user: user) }

    it_behaves_like 'queued only for a project with a matching trigger',
      Ai::Catalog::Flows::ExecuteMergeRequestReadyWorkflowTriggersWorker, :merge_request_ready, :merge_request
  end

  describe 'merge request code conflict events' do
    let(:event) { MergeRequests::CodeConflictEvent.build(merge_request: merge_request) }

    it_behaves_like 'queued only for a project with a matching trigger',
      Ai::Catalog::Flows::ExecuteCodeConflictAiWorkflowTriggersWorker, :merge_request_code_conflict, :merge_request
  end

  describe 'merge request approved events' do
    let(:event) do
      MergeRequests::ApprovedCloudEvent.build(
        merge_request: merge_request,
        current_user: user,
        approval: instance_double(Approval, created_at: Time.current)
      )
    end

    it_behaves_like 'queued only for a project with a matching trigger',
      Ai::Catalog::Flows::ExecuteMergeRequestApprovedWorkflowTriggersWorker, :merge_request, :merge_request_ready
  end
end
