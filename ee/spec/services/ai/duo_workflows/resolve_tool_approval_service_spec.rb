# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ResolveToolApprovalService, feature_category: :duo_agent_platform do
  include ExclusiveLeaseHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:workflow) { create(:duo_workflows_workflow, :tool_call_approval_required, project: project, user: user) }
  let(:current_user) { user }
  let(:approved) { true }

  let(:request_entry) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01issue',
      'content' => 'Tool create_issue requires approval',
      'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report' } }
    }
  end

  let(:fingerprint) { Ai::DuoWorkflows::PendingToolApproval.new(request_entry).fingerprint }

  let(:start_run_result) { ServiceResponse.success(payload: { workflow: workflow }) }

  let(:start_run_service) do
    instance_double(Ai::DuoWorkflows::ExecuteRunService, execute: start_run_result)
  end

  subject(:execute) do
    described_class.new(
      workflow: workflow,
      current_user: current_user,
      approved: approved,
      fingerprint: fingerprint,
      surface: 'slack'
    ).execute
  end

  before do
    allow(Ai::DuoWorkflows::ExecuteRunService).to receive(:new).and_return(start_run_service)
    allow(workflow).to receive(:latest_ui_chat_log).and_return([request_entry])
    allow(current_user).to receive(:can?).and_call_original
    allow(current_user).to receive(:can?).with(:update_duo_workflow, workflow).and_return(true)
  end

  it 'continues the run with an approval event on the runtime the session last ran on' do
    expect(Ai::DuoWorkflows::ExecuteRunService).to receive(:new).with(
      workflow, event: { type: :approval, approved: true }
    ).and_return(start_run_service)

    expect(execute).to be_success
  end

  it 'audits the applied approval' do
    expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
      name: 'duo_tool_call_approved',
      author: current_user,
      scope: project,
      target: workflow,
      message: 'Approved tool call: create_issue',
      additional_details: { approval_source: 'user_explicit', approval_scope: 'once', approval_surface: 'slack' }
    ))

    execute
  end

  context 'when the caller can no longer update the session' do
    before do
      allow(current_user).to receive(:can?).and_call_original
      allow(current_user).to receive(:can?).with(:update_duo_workflow, workflow).and_return(false)
    end

    it 'refuses without touching the session' do
      expect(Ai::DuoWorkflows::ExecuteRunService).not_to receive(:new)

      expect(execute).to be_error.and have_attributes(reason: :not_authorized)
    end
  end

  context 'when the session carries a messaging callback context' do
    let(:workflow) do
      create(:duo_workflows_workflow, :tool_call_approval_required, project: project, user: user,
        messaging_callback_context: {
          'adapter' => 'slack', 'status_ts' => '100.000',
          'pending_approval' => fingerprint, 'pending_approval_ts' => '111.222'
        })
    end

    it 'records the answered request and leaves the Slack keys untouched', :aggregate_failures do
      expect(execute).to be_success

      expect(workflow.reload.messaging_callback_context).to include(
        'answered_approval' => fingerprint,
        'answered_decision' => 'approved',
        'status_ts' => '100.000', 'pending_approval' => fingerprint, 'pending_approval_ts' => '111.222'
      )
    end

    context 'when denying' do
      let(:approved) { false }

      it 'records the denial' do
        expect(execute).to be_success

        expect(workflow.reload.messaging_callback_context).to include('answered_decision' => 'denied')
      end
    end

    it 'keeps a request the resumed run posts before the decision returns', :aggregate_failures do
      allow(start_run_service).to receive(:execute) do
        workflow.merge_messaging_callback_context!(
          'pending_approval' => 'ffffffffffffffff', 'pending_approval_ts' => '999.000'
        )
        start_run_result
      end

      expect(execute).to be_success

      expect(workflow.reload.messaging_callback_context).to include(
        'answered_approval' => fingerprint,
        'pending_approval' => 'ffffffffffffffff', 'pending_approval_ts' => '999.000'
      )
    end

    it 'records nothing when continuing fails' do
      allow(start_run_service).to receive(:execute)
        .and_return(ServiceResponse.error(message: 'another run is active'))

      expect(execute).to be_error

      expect(workflow.reload.messaging_callback_context).not_to have_key('answered_approval')
    end

    context 'when an earlier, different request was answered' do
      before do
        workflow.merge_messaging_callback_context!('answered_approval' => 'ffffffffffffffff')
      end

      it 'accepts the current decision' do
        expect(execute).to be_success
      end
    end

    context 'when a decision was already applied but the runtime has not picked the run up yet' do
      before do
        workflow.merge_messaging_callback_context!('answered_approval' => fingerprint)
      end

      it 'returns stale_request without continuing the run again', :aggregate_failures do
        expect(Ai::DuoWorkflows::ExecuteRunService).not_to receive(:new)
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        expect(execute).to be_error.and have_attributes(reason: :stale_request)
      end
    end

    it 'reloads the session from the primary before checking' do
      lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(workflow.load_balancer)
      allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_return(lb_session)
      expect(lb_session).to receive(:use_primary).and_call_original

      expect(execute).to be_success
    end

    context 'when another submission recorded the decision before the lease was taken' do
      before do
        allow_next_instance_of(Gitlab::ExclusiveLease) do |lease|
          allow(lease).to receive(:try_obtain).and_wrap_original do |original|
            Ai::DuoWorkflows::Workflow.where(id: workflow.id)
              .update_all(messaging_callback_context: { 'adapter' => 'slack', 'answered_approval' => fingerprint })
            original.call
          end
        end
      end

      it 'returns stale_request without continuing the run', :aggregate_failures do
        expect(Ai::DuoWorkflows::ExecuteRunService).not_to receive(:new)

        expect(execute).to be_error.and have_attributes(reason: :stale_request)
      end
    end
  end

  context 'when denying' do
    let(:approved) { false }

    it 'passes the rejection with the event' do
      expect(Ai::DuoWorkflows::ExecuteRunService).to receive(:new).with(
        workflow, event: { type: :approval, approved: false }
      ).and_return(start_run_service)

      expect(execute).to be_success
    end

    it 'audits the applied denial' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'duo_tool_call_denied',
        message: 'Denied tool call: create_issue'
      ))

      execute
    end
  end

  context 'when the caller is not the session owner' do
    let(:current_user) { create(:user) }

    it 'refuses without touching the session' do
      expect(Ai::DuoWorkflows::ExecuteRunService).not_to receive(:new)

      expect(execute).to be_error.and have_attributes(reason: :not_owner)
    end
  end

  context 'when the session is not waiting for a tool approval' do
    let(:workflow) { create(:duo_workflows_workflow, :finished, project: project, user: user) }

    it 'returns not_approvable' do
      expect(execute).to be_error.and have_attributes(reason: :not_approvable)
    end
  end

  context 'when the fingerprint does not match the pending request' do
    let(:fingerprint) { 'deadbeefdeadbeef' }

    it 'returns stale_request' do
      expect(execute).to be_error.and have_attributes(reason: :stale_request)
    end
  end

  context 'when there is no pending request in the log' do
    before do
      allow(workflow).to receive(:latest_ui_chat_log).and_return([])
    end

    it 'returns stale_request' do
      expect(execute).to be_error.and have_attributes(reason: :stale_request)
    end
  end

  context 'when another decision holds the lease' do
    before do
      stub_exclusive_lease_taken("duo_workflows_resolve_tool_approval:#{workflow.id}")
    end

    it 'returns decision_in_progress' do
      expect(execute).to be_error.and have_attributes(reason: :decision_in_progress)
    end
  end

  context 'when writing the audit event raises' do
    before do
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'audit down')
    end

    it 'tracks the exception and still reports success', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(kind_of(StandardError), workflow_id: workflow.id)

      expect(execute).to be_success
    end
  end

  context 'when continuing the run fails' do
    let(:start_run_result) { ServiceResponse.error(message: 'another run is active') }

    it 'returns continue_failed with the message' do
      expect(execute).to be_error.and have_attributes(reason: :continue_failed, message: 'another run is active')
    end

    it 'audits nothing, because no decision was applied' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      execute
    end
  end
end
