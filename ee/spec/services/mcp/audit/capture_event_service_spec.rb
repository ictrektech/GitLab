# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Audit::CaptureEventService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:session) do
    create(:ai_governance_session, :mcp, user: user, namespace: group, project_id: nil,
      agent_type: 'claude-code')
  end

  let(:kind) { :tool_invoked }
  let(:tool_name) { 'get_issue' }
  let(:arguments) { { 'issue_iid' => 3 } }

  subject(:service) do
    described_class.new(
      current_user: user, session: session, kind: kind, tool_name: tool_name,
      arguments: arguments, duration_s: 0.25
    )
  end

  # Stubs the worker as well as capturing, so every example calling this runs
  # without enqueuing anything.
  def enqueued_attributes
    captured = nil
    allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async) { |events| captured = events.first }

    service.execute

    captured
  end

  describe '#initialize' do
    # All four callers pass a literal, so an unmapped kind is a bug rather than
    # bad data: it fails loudly instead of dropping a compliance record.
    it 'rejects a kind it cannot map to an event name' do
      expect do
        described_class.new(current_user: user, session: session, kind: :not_a_kind)
      end.to raise_error(ArgumentError, 'unknown MCP audit kind: :not_a_kind')
    end
  end

  describe '#execute' do
    it 'enqueues an audit event through the existing AI audit pipeline' do
      expect(enqueued_attributes).to include('event_name' => 'ai_tool_invoked', 'author_id' => user.id,
        'ai_governance_session_id' => session.id)
    end

    it 'records the tool call context in details' do
      expect(enqueued_attributes['details']).to include(
        'mcp_server' => 'core',
        'agent_initiated' => true,
        'agent_name' => 'claude-code',
        'tool_name' => 'get_issue',
        'outcome' => 'success',
        'duration_s' => 0.25,
        'arguments' => { 'issue_iid' => 3 }
      )
    end

    # `agent_name` is the normalised slug; the unverified claim is kept alongside
    # it so the two can be compared after the fact.
    describe 'the unverified OAuth application name' do
      let_it_be(:application) do
        create(:oauth_application, name: '[Unverified Dynamic Application] OpenCode')
      end

      before do
        allow(::Current).to receive(:token_info).and_return({ token_application_id: application.id })
      end

      it 'records the full application name, prefix included' do
        expect(enqueued_attributes['details']).to include(
          'oauth_application_id' => application.id,
          'oauth_application_name' => '[Unverified Dynamic Application] OpenCode'
        )
      end

      context 'without an OAuth application' do
        before do
          allow(::Current).to receive(:token_info).and_return({ token_id: 1 })
        end

        it 'omits both keys' do
          details = enqueued_attributes['details']

          expect(details).not_to have_key('oauth_application_id')
          expect(details).not_to have_key('oauth_application_name')
        end
      end
    end

    it 'assigns a unique cloud_event_id per call' do
      ids = []
      allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async) do |events|
        ids << events.first['cloud_event_id']
      end

      2.times { service.execute }

      expect(ids.uniq.size).to eq(2)
    end

    # Sidekiq rejects non-native JSON types, and `attributes` typecasts these two.
    it 'serialises created_at and ip_address into JSON-native values' do
      attributes = enqueued_attributes

      expect(attributes['created_at']).to be_a(String)
      expect(attributes['ip_address']).to be_nil.or(be_a(String))
    end

    # Taken from the session, not resolved per call: a session's Redis key
    # already includes its container, so the two can never disagree.
    describe 'sharding key' do
      it "uses the session's namespace for a group-scoped session" do
        expect(enqueued_attributes).to include('project_id' => nil, 'namespace_id' => session.namespace_id)
      end

      # check_547b01c40f requires exactly one of the two, and a project-scoped
      # session stores the project namespace, which cannot gate storage.
      context 'with a project-scoped session' do
        let_it_be(:session) do
          create(:ai_governance_session, :mcp, user: user, project_id: project.id,
            namespace_id: project.project_namespace_id, agent_type: 'opencode')
        end

        it "uses the session's project" do
          expect(enqueued_attributes).to include('project_id' => project.id, 'namespace_id' => nil)
        end
      end
    end

    describe 'event kinds' do
      {
        session_started: 'ai_agent_session_started',
        session_ended: 'ai_agent_session_ended',
        tool_invoked: 'ai_tool_invoked',
        tool_failed: 'ai_tool_execution_failed'
      }.each do |event_kind, event_name|
        context "with kind #{event_kind}" do
          let(:kind) { event_kind }

          it 'maps to an allowed AI audit event name' do
            expect(enqueued_attributes['event_name']).to eq(event_name)
            expect(::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES).to include(event_name)
          end
        end
      end
    end

    # A failed call emits ai_tool_invoked alongside ai_tool_execution_failed, and both must say it failed.
    context 'when an invocation failed' do
      subject(:service) do
        described_class.new(current_user: user, session: session, kind: :tool_invoked, tool_name: 'get_issue',
          error: ArgumentError.new('bad input'))
      end

      it 'records an error outcome' do
        expect(enqueued_attributes).to include('event_name' => 'ai_tool_invoked')
        expect(enqueued_attributes['details']).to include('outcome' => 'error')
      end
    end

    context 'when the tool call failed' do
      let(:kind) { :tool_failed }

      subject(:service) do
        described_class.new(current_user: user, session: session, kind: kind, tool_name: 'get_issue',
          error: ArgumentError.new('bad input'))
      end

      it 'records the error class and message' do
        expect(enqueued_attributes['details']).to include(
          'outcome' => 'error',
          'error_class' => 'ArgumentError',
          'error_message' => 'bad input'
        )
      end
    end

    context 'when arguments exceed the size cap' do
      let(:arguments) { { 'blob' => 'a' * (described_class::ARGUMENTS_BYTE_CAP + 1) } }

      it 'replaces them rather than storing an oversized payload' do
        expect(enqueued_attributes['details']['arguments']).to eq(described_class::ARGUMENTS_OMITTED)
      end
    end

    context 'without arguments' do
      let(:arguments) { nil }

      it 'omits the key' do
        expect(enqueued_attributes['details']).not_to have_key('arguments')
      end
    end

    # Serialising is what makes the payload Sidekiq-safe, so the unserialisable
    # cases are the ones worth pinning down.
    context 'when the arguments cannot be serialised' do
      let(:arguments) { { 'blob' => (+"\xC3").force_encoding(Encoding::UTF_8) } }

      it 'replaces them rather than raising' do
        expect(enqueued_attributes['details']['arguments']).to eq(described_class::ARGUMENTS_OMITTED)
      end
    end

    # Outside a request there is no remote_ip, which is the default here, so the
    # populated case is the one worth pinning.
    context 'when the request carries an IP address' do
      before do
        allow(::Gitlab::ApplicationContext).to receive(:current_context_attribute)
          .with(:remote_ip).and_return('203.0.113.1')
      end

      it 'serialises it to a string Sidekiq accepts' do
        expect(enqueued_attributes['ip_address']).to eq('203.0.113.1')
      end
    end

    # The session and cron callers build the service without a tool name.
    context 'without a tool name' do
      let(:tool_name) { nil }

      it 'omits the key' do
        expect(enqueued_attributes['details']).not_to have_key('tool_name')
      end
    end

    describe 'the failure reason' do
      it 'is omitted for a successful call' do
        expect(enqueued_attributes['details']).not_to have_key('failure_reason')
      end

      context 'when the call was denied by a tool rule' do
        subject(:service) do
          described_class.new(
            current_user: user, session: session, kind: :tool_failed, tool_name: tool_name,
            error: StandardError.new('denied'), failure_reason: 'unauthorized'
          )
        end

        it 'records it alongside the generic outcome' do
          expect(enqueued_attributes['details']).to include('outcome' => 'error', 'failure_reason' => 'unauthorized')
        end
      end
    end

    # Calls made with these tokens can also appear in the Duo Workflow Service's own
    # events, so they are tagged for a consumer to line the two up.
    describe 'the Duo Agent Platform tag' do
      it 'is omitted for other tokens' do
        allow(::Current).to receive(:token_info).and_return({ token_id: 9, token_scopes: [:mcp] })

        expect(enqueued_attributes['details']).not_to include('via', 'token_id')
      end

      it 'records the source and token for an ai_workflows token' do
        allow(::Current).to receive(:token_info).and_return({ token_id: 9, token_scopes: [:ai_workflows, :mcp] })

        expect(enqueued_attributes['details']).to include('via' => 'duo_agent_platform', 'token_id' => 9)
      end
    end

    # Only an aggregated tool routes to a sub-tool, and that name is what tells a
    # create apart from an update behind save_merge_request.
    describe 'the dispatched tool name' do
      it 'omits the key when the tool did not dispatch' do
        expect(enqueued_attributes['details']).not_to have_key('dispatched_tool_name')
      end

      context 'when the tool dispatched to a sub-tool' do
        subject(:service) do
          described_class.new(
            current_user: user, session: session, kind: kind, tool_name: 'save_merge_request',
            arguments: arguments, dispatched_tool_name: 'update_merge_request'
          )
        end

        it 'records it' do
          expect(enqueued_attributes['details']).to include('dispatched_tool_name' => 'update_merge_request')
        end
      end
    end

    context 'when the OAuth application behind the token no longer exists' do
      before do
        allow(::Current).to receive(:token_info).and_return({ token_application_id: non_existing_record_id })
      end

      it 'records the id but omits the unverified name' do
        details = enqueued_attributes['details']

        expect(details['oauth_application_id']).to eq(non_existing_record_id)
        expect(details).not_to have_key('oauth_application_name')
      end
    end

    context 'when the event is not a tool call' do
      let(:kind) { :session_started }

      it 'records no outcome' do
        expect(enqueued_attributes['details']).not_to have_key('outcome')
      end
    end
  end
end
