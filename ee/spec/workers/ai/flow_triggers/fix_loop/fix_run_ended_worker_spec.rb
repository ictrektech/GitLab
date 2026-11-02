# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::FixRunEndedWorker, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:trigger) do
    create(:ai_flow_trigger, project: project, event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]])
  end

  let(:status) { :finished }
  let(:fix_run_attributes) { {} }
  let(:fix_run) do
    create(:duo_workflows_workflow, status,
      project: project,
      merge_request: merge_request,
      workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
      trigger_event_type: :merge_request,
      trigger_flow_trigger: trigger,
      **fix_run_attributes)
  end

  let(:event) { Ai::DuoWorkflows::WorkflowFinishedCloudEvent.build(workflow: fix_run) }
  let(:service_response) { ServiceResponse.success }
  let(:service) { instance_double(Ai::FlowTriggers::FixLoop::FixRunEndedService, execute: service_response) }
  let(:worker) { described_class.new }

  before do
    allow(Ai::FlowTriggers::FixLoop::FixRunEndedService).to receive(:new).and_return(service)
  end

  def handle_event
    worker.handle_event(event)
  end

  it_behaves_like 'subscribes to event'

  context 'when the fix run failed' do
    let(:status) { :failed }
    let(:event) { Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: fix_run) }

    it_behaves_like 'subscribes to event'

    context 'with the copy of the event for messaging sessions' do
      let(:event) { Ai::DuoWorkflows::WorkflowFailedEvent.build(workflow: fix_run, status_event: :drop) }

      it_behaves_like 'ignores the published event'
    end
  end

  context 'when a user stopped the fix run' do
    let(:status) { :stopped }
    let(:event) { Ai::DuoWorkflows::WorkflowStoppedEvent.build(workflow: fix_run) }

    it_behaves_like 'subscribes to event'
  end

  context 'with a session of another flow' do
    let(:fix_run_attributes) do
      { workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference }
    end

    it_behaves_like 'ignores the published event'
  end

  context 'with a session that no flow trigger started' do
    let(:fix_run_attributes) { { trigger_flow_trigger: nil } }

    it_behaves_like 'ignores the published event'
  end

  context 'with a session without a merge request' do
    let(:fix_run_attributes) { { merge_request: nil } }

    it_behaves_like 'ignores the published event'
  end

  context 'with a session that another event started' do
    let(:fix_run_attributes) { { trigger_event_type: :mention } }

    it_behaves_like 'ignores the published event'
  end

  it 'does not inherit the composite identity of the enqueuing context' do
    expect(described_class.skip_composite_identity_passthrough?).to be(true)
  end

  it 'defers only on database-wide health signals' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org, tables: [], indicators: Gitlab::Database::HealthStatus::GLOBAL_INDICATORS)
  end

  describe '.dispatch?' do
    it 'is false for a session that no longer exists' do
      event
      fix_run.destroy!

      expect(described_class.dispatch?(event)).to be(false)
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(dap_software_factory: false)
    end

    it_behaves_like 'ignores the published event'

    it 'does not check the fix run when the job runs' do
      handle_event

      expect(Ai::FlowTriggers::FixLoop::FixRunEndedService).not_to have_received(:new)
    end
  end

  context 'when dap_software_factory is enabled for the project only' do
    before do
      stub_feature_flags(dap_software_factory: project)
    end

    it_behaves_like 'subscribes to event'

    it 'checks the end of the fix run' do
      handle_event

      expect(Ai::FlowTriggers::FixLoop::FixRunEndedService).to have_received(:new).with(fix_run)
    end
  end

  describe '#handle_event' do
    it 'checks the end of the fix run' do
      handle_event

      expect(Ai::FlowTriggers::FixLoop::FixRunEndedService).to have_received(:new).with(fix_run)
    end

    context 'when the check does not stop the loop' do
      let(:service_response) { ServiceResponse.error(message: 'Fix run pushed.', reason: :pushed) }

      it 'logs the reason' do
        expect(worker.logger).to receive(:info).with(hash_including(
          'message' => 'Fix loop not stopped: Fix run pushed.',
          'reason' => :pushed,
          Labkit::Fields::DUO_WORKFLOW_ID => fix_run.id,
          'merge_request_id' => merge_request.id
        ))

        handle_event
      end
    end

    context 'when the session runs again' do
      before do
        event
        fix_run.update!(status: Ai::DuoWorkflows::Workflow.state_machines[:status].states[:running].value)
      end

      it 'does not check the fix run' do
        handle_event

        expect(Ai::FlowTriggers::FixLoop::FixRunEndedService).not_to have_received(:new)
      end
    end

    context 'when the session no longer exists' do
      before do
        event
        fix_run.destroy!
      end

      it 'does not check the fix run' do
        handle_event

        expect(Ai::FlowTriggers::FixLoop::FixRunEndedService).not_to have_received(:new)
      end
    end
  end
end
