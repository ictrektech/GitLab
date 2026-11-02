# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionLifecycleWorker, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }

  let(:flow) { ::Ai::Catalog::FoundationalFlow.new(foundational_flow_reference: 'something/v1') }
  let(:messaging_callback_context) { nil }

  let(:workflow) do
    create(
      :duo_workflows_workflow,
      :running,
      project: project,
      workflow_definition: flow.foundational_flow_reference,
      messaging_callback_context: messaging_callback_context
    )
  end

  shared_examples_for 'subscribes to failed event with new format' do
    it_behaves_like 'subscribes to event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow) }
    end
  end

  shared_examples_for 'subscribes to stopped event with new format' do
    it_behaves_like 'subscribes to event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowStoppedEvent.build(workflow: workflow) }
    end
  end

  shared_examples_for 'subscribes to finished event' do
    it_behaves_like 'subscribes to event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFinishedCloudEvent.build(workflow: workflow) }
    end
  end

  shared_examples_for 'ignores failed event with new format' do
    it_behaves_like 'ignores the published event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow) }
    end
  end

  shared_examples_for 'ignores stopped event with new format' do
    it_behaves_like 'ignores the published event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowStoppedEvent.build(workflow: workflow) }
    end
  end

  shared_examples_for 'ignores failed event with old format' do
    it_behaves_like 'ignores the published event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow, status_event: :drop) }
    end
  end

  shared_examples_for 'ignores stopped event with old format' do
    it_behaves_like 'ignores the published event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow, status_event: :stop) }
    end
  end

  shared_examples_for 'ignores finished event' do
    it_behaves_like 'ignores the published event' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFinishedCloudEvent.build(workflow: workflow) }
    end
  end

  # The schema allows both keys at once, so `status_event` is the only thing keeping
  # the aggregated copy off this worker. Built by hand: the publisher cannot emit it.
  shared_examples_for 'ignores a payload carrying both formats' do
    it_behaves_like 'ignores the published event' do
      let(:event) do
        ::Ai::DuoWorkflows::WorkflowFailedEvent.build_cloud_event(
          source: "ai/duo_workflows/workflows/#{workflow.id}",
          subject: "ai/duo_workflows/workflows/#{workflow.id}",
          event_data: {
            workflow_id: workflow.id,
            status_event: 'drop',
            workflow_definition: workflow.workflow_definition,
            adapter: 'slack'
          }
        )
      end
    end
  end

  before do
    allow(::Ai::Catalog::FoundationalFlow).to receive(:find_by).and_call_original
    allow(::Ai::Catalog::FoundationalFlow).to receive(:[]).and_call_original

    allow(::Ai::Catalog::FoundationalFlow).to receive(:find_by)
      .with(foundational_flow_reference: flow.foundational_flow_reference)
      .and_return(flow)
    allow(::Ai::Catalog::FoundationalFlow).to receive(:[])
      .with(flow.foundational_flow_reference)
      .and_return(flow)
  end

  describe 'subscriptions' do
    context 'when the flow declares a hook for the event' do
      before do
        flow.on_session_failed = ->(workflow:) {}
        flow.on_session_stopped = ->(workflow:) {}
        flow.on_session_finished = ->(workflow:) {}
      end

      it_behaves_like 'subscribes to failed event with new format'
      it_behaves_like 'subscribes to stopped event with new format'
      it_behaves_like 'subscribes to finished event'

      context 'when a surface is waiting on the session' do
        let(:messaging_callback_context) { { 'adapter' => 'slack' } }

        it_behaves_like 'subscribes to failed event with new format'
        it_behaves_like 'subscribes to stopped event with new format'
        it_behaves_like 'subscribes to finished event'

        it_behaves_like 'ignores failed event with old format'
        it_behaves_like 'ignores stopped event with old format'

        it_behaves_like 'ignores a payload carrying both formats'
      end
    end

    # Each event's guard must look up its own hook, not whichever one the flow declares.
    context 'when the flow declares only some hooks' do
      before do
        flow.on_session_failed = nil
        flow.on_session_stopped = nil
        flow.on_session_finished = ->(workflow:) {}
      end

      it_behaves_like 'subscribes to finished event'
      it_behaves_like 'ignores failed event with new format'
      it_behaves_like 'ignores stopped event with new format'
    end

    context 'when the flow declares no hook for the event' do
      before do
        flow.on_session_failed = nil
        flow.on_session_stopped = nil
        flow.on_session_finished = nil
      end

      it_behaves_like 'ignores failed event with old format'
      it_behaves_like 'ignores failed event with new format'

      it_behaves_like 'ignores stopped event with old format'
      it_behaves_like 'ignores stopped event with new format'

      it_behaves_like 'ignores finished event'

      context 'when a surface is waiting on the session' do
        let(:messaging_callback_context) { { 'adapter' => 'slack' } }

        it_behaves_like 'ignores failed event with old format'
        it_behaves_like 'ignores failed event with new format'

        it_behaves_like 'ignores stopped event with old format'
        it_behaves_like 'ignores stopped event with new format'

        it_behaves_like 'ignores finished event'
      end
    end
  end

  describe 'hook coverage' do
    it 'has a hook attribute for every event the worker is subscribed to' do
      subscribed = Gitlab::EventStore.instance.subscriptions.select do |_event, subscriptions|
        subscriptions.any? { |subscription| subscription.worker == described_class }
      end

      expect(::Ai::Catalog::FoundationalFlow::SESSION_LIFECYCLE_HOOKS.keys).to match_array(subscribed.keys)
    end

    it 'names an attribute the flow actually defines' do
      ::Ai::Catalog::FoundationalFlow::SESSION_LIFECYCLE_HOOKS.each_value do |attribute|
        expect(::Ai::Catalog::FoundationalFlow.new).to respond_to(attribute)
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:exception) { StandardError.new('hook blew up') }

    def run_exhausted(args, error = exception)
      described_class.sidekiq_retries_exhausted_block.call({ 'args' => args }, error)
    end

    it 'reports the session from a cloud event payload' do
      expect(Gitlab::AppLogger).to receive(:error).with(hash_including(
        message: 'Session lifecycle hook failed: retries exhausted',
        error_class: 'StandardError',
        event_class: 'Ai::DuoWorkflows::WorkflowFailedEvent',
        workflow_id: 123
      ))

      run_exhausted(['Ai::DuoWorkflows::WorkflowFailedEvent', { 'data' => { 'workflow_id' => 123 } }])
    end

    it 'reports the session from the batched shape the subscriber can hand it' do
      expect(Gitlab::AppLogger).to receive(:error).with(hash_including(workflow_id: 456))

      run_exhausted(['Ai::DuoWorkflows::WorkflowStoppedEvent', [{ 'workflow_id' => 456 }]])
    end

    it 'reports no error class when Sidekiq passes none' do
      expect(Gitlab::AppLogger).to receive(:error).with(hash_including(error_class: nil))

      run_exhausted(['Ai::DuoWorkflows::WorkflowFailedEvent', { 'workflow_id' => 789 }], nil)
    end
  end

  describe '#handle_event' do
    subject(:handle_event) { consume_event(subscriber: described_class, event: event) }

    let(:calls) { [] }
    let(:event) { ::Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: workflow) }

    before do
      flow.on_session_failed = ->(workflow:) { calls << [:failed, workflow] }
      flow.on_session_stopped = ->(workflow:) { calls << [:stopped, workflow] }
      flow.on_session_finished = ->(workflow:) { calls << [:finished, workflow] }
    end

    context 'when the event has no hook attribute' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowStartedEvent.new(data: { workflow_id: workflow.id }) }

      it 'returns without looking the session up' do
        expect(::Ai::DuoWorkflows::Workflow).not_to receive(:find_by_id)

        handle_event
        expect(calls).to be_empty
      end
    end

    context 'when the flow declares no hook' do
      before do
        flow.on_session_failed = nil
        flow.on_session_stopped = nil
        flow.on_session_finished = nil
      end

      it 'does nothing' do
        expect(Gitlab::AppLogger).not_to receive(:info)

        handle_event
        expect(calls).to be_empty
      end
    end

    context 'when the flow declares a hook for the event' do
      it 'lets a raising hook propagate, so Sidekiq retries it' do
        flow.on_session_failed = ->(workflow:) { raise "hook failed for #{workflow.id}" }

        expect { handle_event }.to raise_error("hook failed for #{workflow.id}")
      end

      context 'when the session is gone by the time the job runs' do
        before do
          event
          workflow.destroy!
        end

        it 'logs the skip and does not call the hook' do
          expect(Gitlab::AppLogger).to receive(:info).with(
            hash_including(message: 'Session lifecycle hook skipped: session not found')
          )

          handle_event

          expect(calls).to be_empty
        end
      end
    end

    context 'when the session is not from a foundational flow' do
      let(:workflow) do
        create(:duo_workflows_workflow, :running, project: project, workflow_definition: 'chat')
      end

      it 'does nothing' do
        expect(::Ai::Catalog::FoundationalFlow).to receive(:[]).with('chat').and_call_original
        expect(Gitlab::AppLogger).not_to receive(:info)

        handle_event
        expect(calls).to be_empty
      end
    end

    context 'when the session failed' do
      it 'runs the failed hook' do
        handle_event
        expect(calls).to contain_exactly([:failed, workflow])
      end
    end

    context 'when the session was stopped' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowStoppedEvent.build(workflow: workflow) }

      it 'runs the stopped hook' do
        handle_event
        expect(calls).to contain_exactly([:stopped, workflow])
      end
    end

    context 'when the session finished successfully' do
      let(:event) { ::Ai::DuoWorkflows::WorkflowFinishedCloudEvent.build(workflow: workflow) }

      it 'runs the finished hook' do
        handle_event
        expect(calls).to contain_exactly([:finished, workflow])
      end
    end
  end
end
