# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackInteractions::SlackBlockActions::DuoApprovalDecisionHandler, feature_category: :duo_agent_platform do
  describe '#execute' do
    let_it_be(:chat_name) { create(:chat_name) }
    let_it_be(:slack_installation) { create(:slack_integration, team_id: chat_name.team_id) }

    let(:request_entry) do
      {
        'message_type' => 'request',
        'message_id' => 'toolu_01issue',
        'content' => 'Tool create_issue requires approval',
        'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report' } }
      }
    end

    let(:chat_log) { [request_entry] }
    let(:fingerprint) { Ai::DuoWorkflows::PendingToolApproval.new(request_entry).fingerprint }
    let(:workflow) do
      create(:duo_workflows_workflow, :tool_call_approval_required, user: chat_name.user,
        messaging_callback_context: {
          'adapter' => 'slack', 'team_id' => chat_name.team_id, 'channel_id' => 'C123', 'thread_ts' => '100.200',
          'user_id' => chat_name.chat_id, 'status_ts' => '111.222', 'pending_approval' => fingerprint
        })
    end

    let(:action_id) { 'duo_approval_approve' }
    let(:action_value) { "#{workflow.id}:#{fingerprint}" }
    let(:action) { { action_id: action_id, value: action_value } }
    let(:params) do
      {
        team: { id: chat_name.team_id },
        user: { id: chat_name.chat_id },
        actions: [action]
      }
    end

    let(:update_message_url) { "#{Slack::API::BASE_URL}/chat.update" }
    let(:post_ephemeral_url) { "#{Slack::API::BASE_URL}/chat.postEphemeral" }
    let(:resolve_result) { ServiceResponse.success }
    let(:resolve_service) do
      instance_double(Ai::DuoWorkflows::ResolveToolApprovalService).tap do |service|
        # Records the decision like the real service, since the card is rendered from it.
        allow(service).to receive(:execute) do
          if resolve_result.success?
            workflow.merge_messaging_callback_context!(
              'answered_approval' => fingerprint,
              'answered_decision' => action_id == 'duo_approval_approve' ? 'approved' : 'denied'
            )
          end

          resolve_result
        end
      end
    end

    subject(:execute) { described_class.new(params, action).execute }

    before do
      stub_request(:post, update_message_url).to_return(
        status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:post, post_ephemeral_url).to_return(
        status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      allow(Ai::DuoWorkflows::ResolveToolApprovalService).to receive(:new).and_return(resolve_service)
      allow_next_found_instance_of(Ai::DuoWorkflows::Workflow) do |instance|
        allow(instance).to receive(:latest_ui_chat_log).and_return(chat_log)
      end
    end

    shared_examples 'notifies only the clicker with' do |text|
      it 'posts an ephemeral in the thread and leaves the card alone', :aggregate_failures do
        execute

        expect(WebMock).to have_requested(:post, post_ephemeral_url).with { |req|
          body = ::Gitlab::Json::SafeParser.parse(req.body)

          body['channel'] == 'C123' &&
            body['user'] == chat_name.chat_id &&
            body['thread_ts'] == '100.200' &&
            body['text'] == text
        }
        expect(WebMock).not_to have_requested(:post, update_message_url)
      end
    end

    it 'resolves the approval for the linked user against the clicked fingerprint' do
      expect(Ai::DuoWorkflows::ResolveToolApprovalService).to receive(:new).with(
        workflow: workflow,
        current_user: chat_name.user,
        approved: true,
        fingerprint: fingerprint,
        surface: 'slack'
      ).and_return(resolve_service)

      execute
    end

    it 'tracks the decision' do
      expect { execute }.to trigger_internal_events('ai_duo_messaging_tool_approval_resolved').with(
        user: chat_name.user,
        namespace: workflow.resource_parent.root_ancestor,
        additional_properties: { label: 'approved', value: workflow.id, property: 'slack' }
      )
    end

    it 're-renders the progress message with the decided card, keeping the payload and dropping the buttons',
      :aggregate_failures do
      execute

      expect(WebMock).to have_requested(:post, update_message_url).with { |req|
        body = ::Gitlab::Json::SafeParser.parse(req.body)
        card = body['blocks'].sole

        body['channel'] == 'C123' &&
          body['ts'] == '111.222' &&
          body['text'] == 'Approved. GitLab Duo is continuing.' &&
          card['type'] == 'container' &&
          card['default_collapsed'] == true &&
          card['subtitle']['text'] == 'Approved' &&
          req.body.include?('Bug report') &&
          card['child_blocks'].none? { |b| b['type'] == 'actions' } &&
          card['child_blocks'].last['elements'].sole['text'] ==
            "Approved by <@#{chat_name.chat_id}>. GitLab Duo is continuing."
      }
      expect(WebMock).not_to have_requested(:post, post_ephemeral_url)
    end

    it 'hands the adapter the stored callback context' do
      expect(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context)
        .with(hash_including('team_id' => chat_name.team_id, 'status_ts' => '111.222')).and_call_original

      execute
    end

    context 'when the session log has nothing to render' do
      let(:chat_log) { [] }

      it 'does not edit the progress message' do
        execute

        expect(WebMock).not_to have_requested(:post, update_message_url)
      end
    end

    context 'when denying' do
      let(:action_id) { 'duo_approval_deny' }

      it 'passes approved: false and reports the denial', :aggregate_failures do
        expect(Ai::DuoWorkflows::ResolveToolApprovalService).to receive(:new)
          .with(hash_including(approved: false)).and_return(resolve_service)

        expect { execute }.to trigger_internal_events('ai_duo_messaging_tool_approval_resolved').with(
          user: chat_name.user,
          namespace: workflow.resource_parent.root_ancestor,
          additional_properties: { label: 'denied', value: workflow.id, property: 'slack' }
        )

        expect(WebMock).to have_requested(:post, update_message_url).with { |req|
          ::Gitlab::Json::SafeParser.parse(req.body)['text'].start_with?('Denied.')
        }
      end
    end

    context 'when the service refuses the decision' do
      shared_examples 'a refused decision' do
        it 'tracks nothing' do
          expect { execute }.not_to trigger_internal_events('ai_duo_messaging_tool_approval_resolved')
        end
      end

      context 'when the clicker is not the session owner' do
        let(:resolve_result) { ServiceResponse.error(message: 'not owner', reason: :not_owner) }

        it_behaves_like 'a refused decision'
        it_behaves_like 'notifies only the clicker with',
          'Only the person who started this session can respond to this request.'
      end

      context 'when the clicker lost access to the session' do
        let(:resolve_result) { ServiceResponse.error(message: 'not allowed', reason: :not_authorized) }

        it_behaves_like 'a refused decision'
        it_behaves_like 'notifies only the clicker with',
          'Only the person who started this session can respond to this request.'
      end

      context 'when the request was already answered' do
        let(:resolve_result) { ServiceResponse.error(message: 'stale', reason: :stale_request) }

        it_behaves_like 'a refused decision'
        it_behaves_like 'notifies only the clicker with', 'This approval request has already been answered.'
      end

      context 'when the session is no longer waiting for an approval' do
        let(:resolve_result) { ServiceResponse.error(message: 'nope', reason: :not_approvable) }

        it_behaves_like 'a refused decision'
        it_behaves_like 'notifies only the clicker with', 'This approval request has already been answered.'
      end

      context 'when the session has already moved past the approval state' do
        let(:workflow) do
          create(:duo_workflows_workflow, :running, user: chat_name.user,
            messaging_callback_context: {
              'adapter' => 'slack', 'team_id' => chat_name.team_id, 'channel_id' => 'C123',
              'thread_ts' => '100.200', 'status_ts' => '111.222', 'pending_approval' => fingerprint
            })
        end

        let(:resolve_result) { ServiceResponse.error(message: 'nope', reason: :not_approvable) }

        it_behaves_like 'a refused decision'
        it_behaves_like 'notifies only the clicker with', 'This approval request has already been answered.'
      end

      context 'when posting the notice raises' do
        let(:resolve_result) { ServiceResponse.error(message: 'not owner', reason: :not_owner) }

        before do
          allow_next_instance_of(::Slack::API) do |api|
            allow(api).to receive(:post_ephemeral).and_raise(StandardError, 'boom')
          end
        end

        it 'tracks the exception and does not raise' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(kind_of(StandardError), workflow_id: workflow.id)

          expect { execute }.not_to raise_error
        end
      end

      context 'when the session cannot be continued' do
        let(:resolve_result) { ServiceResponse.error(message: 'nope', reason: :continue_failed) }

        it_behaves_like 'a refused decision'
        it_behaves_like 'notifies only the clicker with', 'This request can no longer be answered.'
      end
    end

    context 'when the Slack account is not linked to a GitLab user' do
      let(:params) { super().merge(user: { id: 'U_UNKNOWN' }) }

      it 'resolves nothing' do
        expect(Ai::DuoWorkflows::ResolveToolApprovalService).not_to receive(:new)

        execute
      end

      it 'tells the clicker to connect their account' do
        execute

        expect(WebMock).to have_requested(:post, post_ephemeral_url).with { |req|
          body = ::Gitlab::Json::SafeParser.parse(req.body)

          body['user'] == 'U_UNKNOWN' && body['text'].start_with?('Your Slack account is not connected')
        }
      end

      context 'and the callback context has no channel to notify in' do
        let(:workflow) do
          create(:duo_workflows_workflow, :tool_call_approval_required, user: chat_name.user,
            messaging_callback_context: { 'adapter' => 'slack', 'pending_approval' => fingerprint })
        end

        it 'stays silent' do
          execute

          expect(WebMock).not_to have_requested(:post, post_ephemeral_url)
        end
      end
    end

    context 'when no progress message is recorded in the callback context' do
      let(:workflow) do
        create(:duo_workflows_workflow, :tool_call_approval_required, user: chat_name.user,
          messaging_callback_context: {
            'adapter' => 'slack', 'team_id' => chat_name.team_id, 'channel_id' => 'C123',
            'pending_approval' => fingerprint
          })
      end

      it 'still applies the decision without calling chat.update', :aggregate_failures do
        expect(resolve_service).to receive(:execute)

        execute

        expect(WebMock).not_to have_requested(:post, update_message_url)
      end
    end

    context 'when updating the progress message raises' do
      before do
        allow_next_instance_of(::Slack::API) do |api|
          allow(api).to receive(:update_message).and_raise(StandardError, 'boom')
        end
      end

      it 'tracks the exception and does not raise' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(StandardError), workflow_id: workflow.id)

        expect { execute }.not_to raise_error
      end
    end

    context 'when the session has no resource parent' do
      before do
        allow_next_found_instance_of(Ai::DuoWorkflows::Workflow) do |instance|
          allow(instance).to receive(:resource_parent).and_return(nil)
        end
      end

      it 'evaluates the flag without an actor and still applies the decision' do
        expect(resolve_service).to receive(:execute)

        execute
      end
    end

    context 'when the Slack workspace has no bot installation' do
      let_it_be(:other_chat_name) { create(:chat_name, team_id: 'T_NO_INSTALL', user: chat_name.user) }

      let(:params) { super().merge(team: { id: other_chat_name.team_id }, user: { id: other_chat_name.chat_id }) }

      it 'applies the decision but skips the card update', :aggregate_failures do
        expect(resolve_service).to receive(:execute)

        execute

        expect(WebMock).not_to have_requested(:post, update_message_url)
      end

      context 'and the decision is refused' do
        let(:resolve_result) { ServiceResponse.error(message: 'not owner', reason: :not_owner) }

        it 'cannot notify the clicker either' do
          execute

          expect(WebMock).not_to have_requested(:post, post_ephemeral_url)
        end
      end
    end

    context 'when the slack_duo_api_flow flag is disabled' do
      before do
        stub_feature_flags(slack_duo_api_flow: false)
      end

      it 'does nothing', :aggregate_failures do
        expect(Ai::DuoWorkflows::ResolveToolApprovalService).not_to receive(:new)

        execute

        expect(WebMock).not_to have_requested(:post, update_message_url)
        expect(WebMock).not_to have_requested(:post, post_ephemeral_url)
      end
    end

    context 'when the value is malformed' do
      let(:action_value) { 'garbage' }

      it 'does nothing' do
        expect(Ai::DuoWorkflows::ResolveToolApprovalService).not_to receive(:new)

        execute
      end
    end

    context 'when the workflow does not exist' do
      let(:action_value) { "#{non_existing_record_id}:#{fingerprint}" }

      it 'does nothing' do
        expect(Ai::DuoWorkflows::ResolveToolApprovalService).not_to receive(:new)

        execute
      end
    end
  end
end
