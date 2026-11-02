# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Audit::ResolveSessionService, :clean_gitlab_redis_shared_state,
  feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:application) { create(:oauth_application, name: '[Unverified Dynamic Application] Claude Desktop') }

  let(:token_info) { { token_application_id: application.id } }

  subject(:service) { described_class.new(current_user: user, container: group) }

  before do
    allow(::Current).to receive(:token_info).and_return(token_info)
    allow(::Mcp::Audit::CaptureEventService).to receive(:new).and_return(instance_double(
      ::Mcp::Audit::CaptureEventService, execute: nil
    ))
  end

  describe '#execute' do
    it 'mints a running, namespace-scoped MCP session' do
      session = service.execute

      expect(session).to be_a(::Ai::Governance::Session)
      expect(session).to have_attributes(
        user_id: user.id,
        namespace_id: group.id,
        project_id: nil,
        source: 'mcp',
        status: 'running',
        workflow_id: nil
      )
      expect(session.session_started_at).to be_present
    end

    # MCP carries no session identifier, so GitLab mints one. The model requires
    # exactly one of workflow_id/external_xid, and an MCP session has no workflow.
    it 'mints an external_xid rather than reading one off the request' do
      session = service.execute

      expect(session.external_xid).to be_present
      expect(described_class.new(current_user: user, container: create(:group)).execute.external_xid)
        .not_to eq(session.external_xid)
    end

    it 'emits a session started audit event' do
      service.execute

      expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
        .with(hash_including(kind: :session_started))
    end

    context 'without any token context' do
      let(:token_info) { nil }

      it 'still resolves a session and records the agent as unknown' do
        expect(service.execute.agent_type).to eq(described_class::UNKNOWN_AGENT)
      end
    end

    # Gitlab::Json::SafeParser raises JSON::ParserError rather than returning
    # nil, so the rescue is load-bearing: without it a corrupted key would break
    # every tool call for that caller until the key expired.
    context 'when the stored window state is not valid JSON' do
      before do
        Gitlab::Redis::SharedState.with { |redis| redis.set(service.send(:lookup_key), 'not json') }
      end

      it 'discards it and mints a fresh session' do
        expect { service.execute }.to change { ::Ai::Governance::Session.count }.by(1)
      end
    end

    # The session started event reaches external destinations and nothing
    # retracts it, so it must not be queued for a row the lost-claim path
    # destroys. The claim is lost for real here: a key already holding unusable
    # state is discarded, read back as no session, then blocks the SET NX.
    context 'when the Redis claim is lost to a concurrent caller' do
      # Stands in for a concurrent caller writing the key between this one's
      # discard and its SET NX, which is the only way the claim is lost.
      before do
        allow(service).to receive(:discard_state)
        Gitlab::Redis::SharedState.with { |redis| redis.set(service.send(:lookup_key), '{}') }
      end

      it 'emits no session started event' do
        service.execute

        expect(::Mcp::Audit::CaptureEventService).not_to have_received(:new)
      end

      it 'leaves no session row behind' do
        expect { service.execute }.not_to change { ::Ai::Governance::Session.count }
      end

      # The loser returns the winner's session, so the tool call is still
      # audited against something rather than going unaudited.
      context 'when the winner has written its state' do
        let_it_be(:winner) { create(:ai_governance_session, :mcp, user: user, namespace: group) }

        before do
          allow(service).to receive(:read_state).and_return(
            nil,
            { 'session_id' => winner.id, 'started_at' => Time.current.to_i,
              'expires_at' => 1.hour.from_now.to_i }
          )
        end

        it "resumes the winner's session" do
          expect(service.execute).to eq(winner)
        end
      end
    end

    it 'returns nil without a container' do
      expect(described_class.new(current_user: user, container: nil).execute).to be_nil
    end

    context 'when scoped to a project' do
      let_it_be(:project) { create(:project, group: group) }

      # `namespace_id` is the sharding key and NOT NULL, so a project-scoped row
      # stores the project namespace id and records `project_id` alongside it.
      it 'records both the project and its project namespace' do
        session = described_class.new(current_user: user, container: project).execute

        expect(session).to have_attributes(
          project_id: project.id,
          namespace_id: project.project_namespace_id
        )
      end

      it 'keeps the session separate from a group-scoped one' do
        project_session = described_class.new(current_user: user, container: project).execute
        group_session = described_class.new(current_user: user, container: group).execute

        expect(group_session.id).not_to eq(project_session.id)
      end
    end

    context 'with an existing window' do
      it 'reuses the session on a later call' do
        first = service.execute
        second = described_class.new(current_user: user, container: group).execute

        expect(second.id).to eq(first.id)
        expect(::Ai::Governance::Session.count).to eq(1)
      end

      it 'extends the window on each call' do
        first = service.execute

        travel_to(14.minutes.from_now) do
          expect(described_class.new(current_user: user, container: group).execute.id).to eq(first.id)
        end
      end

      it 'mints a new session once the idle window lapses' do
        first = service.execute

        travel_to(described_class::IDLE_EXTENSION.from_now + 1.minute) do
          expect(described_class.new(current_user: user, container: group).execute.id).not_to eq(first.id)
        end
      end

      # The idle extension is capped, so a continuously active agent still rolls
      # over rather than holding one session open indefinitely.
      it 'mints a new session at the maximum duration even while active' do
        first = service.execute

        travel_to(10.minutes.from_now) { described_class.new(current_user: user, container: group).execute }

        travel_to(described_class::MAX_DURATION.from_now + 1.second) do
          expect(described_class.new(current_user: user, container: group).execute.id).not_to eq(first.id)
        end
      end

      it 'mints a new session when the stored session row no longer exists' do
        first = service.execute
        first.destroy!

        expect(described_class.new(current_user: user, container: group).execute).to be_present
      end
    end

    context 'with separate callers' do
      let_it_be(:other_group) { create(:group) }

      it 'keeps sessions separate per namespace' do
        first = service.execute
        second = described_class.new(current_user: user, container: other_group).execute

        expect(second.id).not_to eq(first.id)
      end

      it 'keeps sessions separate per OAuth application' do
        first = service.execute

        other_application = create(:oauth_application)
        allow(::Current).to receive(:token_info).and_return({ token_application_id: other_application.id })

        expect(described_class.new(current_user: user, container: group).execute.id).not_to eq(first.id)
      end
    end

    describe 'agent name' do
      def agent_type_for(application_name)
        app = create(:oauth_application, name: application_name)
        allow(::Current).to receive(:token_info).and_return({ token_application_id: app.id })

        described_class.new(current_user: user, container: group).execute.agent_type
      end

      # The declared name is client-supplied, so it is mapped onto a known slug
      # rather than stored verbatim.
      [
        ['OpenCode', 'opencode'],
        ['opencode', 'opencode'],
        ['open-code', 'opencode'],
        ['Claude Code (GitLab) — authorized by @root', 'claude-code'],
        ['claude_code', 'claude-code'],
        ['Cursor', 'cursor'],
        ['GitLab MCP for Cursor', 'cursor'],
        ['Codex CLI', 'codex']
      ].each do |declared, slug|
        it "maps #{declared.inspect} to #{slug}" do
          expect(agent_type_for("#{described_class::DYNAMIC_APP_NAME_PREFIX}#{declared}")).to eq(slug)
        end
      end

      # Without word boundaries these are real misattributions, not hypotheticals:
      # /cursor/ claims "Precursor AI" and /codex/ claims "Codexity".
      ['Precursor AI', 'Codexity'].each do |declared|
        it "does not claim #{declared.inspect}" do
          expect(agent_type_for("#{described_class::DYNAMIC_APP_NAME_PREFIX}#{declared}"))
            .to eq(described_class::UNKNOWN_AGENT)
        end
      end

      # Prevents an arbitrary caller-supplied label entering the agent_type dimension.
      it 'maps an unrecognised name to unknown' do
        expect(agent_type_for("#{described_class::DYNAMIC_APP_NAME_PREFIX}Totally Not Evil"))
          .to eq(described_class::UNKNOWN_AGENT)
      end

      it 'maps a name without the dynamic registration prefix' do
        expect(agent_type_for('opencode')).to eq('opencode')
      end

      it 'only records slugs that fit the agent_type constraint and slug form' do
        expect(described_class::AGENT_PATTERNS.keys).to all(match(/\A[a-z0-9-]{1,50}\z/))
      end

      context 'when authenticated with a personal access token' do
        let(:token_info) { { token_id: 1 } }

        it 'records the agent as unknown' do
          expect(service.execute.agent_type).to eq(described_class::UNKNOWN_AGENT)
        end
      end

      context 'when the OAuth application has been removed' do
        before do
          application.destroy!
        end

        it 'records the agent as unknown' do
          expect(service.execute.agent_type).to eq(described_class::UNKNOWN_AGENT)
        end
      end
    end
  end
end
