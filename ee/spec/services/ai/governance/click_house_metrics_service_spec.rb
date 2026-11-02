# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ClickHouseMetricsService, :click_house,
  feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }

  let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_7_days) }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  before do
    stub_feature_flags(ai_governance_sessions_api: false)
    insert_rows([
      { id: 1, definition: 'software_development', created_at: '2026-07-01 10:00:00', path: project_path },
      { id: 2, definition: 'software_development', created_at: '2026-07-01 12:00:00', path: project_path,
        environment: 2 },
      { id: 3, definition: 'convert_to_gitlab_ci', created_at: '2026-06-28 09:00:00', path: project_path },
      { id: 4, definition: 'software_development', created_at: '2026-06-20 09:00:00', path: project_path },
      { id: 5, definition: 'chat', created_at: '2026-07-01 09:00:00', path: project_path },
      { id: 6, definition: 'software_development', created_at: '2026-07-01 09:00:00', path: '0/999/' },
      { id: 7, definition: 'software_development', created_at: '2026-07-01 11:00:00', path: project_path,
        project_id: 12345 },
      # older than the cumulative lookback; another user, so it would mint an
      # extra agent instance if the seed read all history
      { id: 8, definition: 'software_development', created_at: '2026-05-20 09:00:00', path: project_path,
        user_id: 999_999 }
    ])
    # duplicate version of id 1 (siphon update) - must not double-count
    insert_rows([{ id: 1, definition: 'software_development', created_at: '2026-07-01 10:00:00',
                   path: project_path, replicated_at: '2026-07-02 00:00:00' }])
  end

  subject(:payload) { described_class.new(group, current_user: user, timeframe: timeframe).execute.payload }

  it 'counts deduplicated sessions of every definition, chat included', :aggregate_failures do
    expect(payload[:sessions][:count]).to eq(5)
    expect(payload[:sessions][:previous_count]).to eq(1)
  end

  it 'counts distinct agent instances', :aggregate_failures do
    # ids 1 and 3 share (user, project, environment) across two definitions =>
    # one instance; id 2 differs on environment => a second instance; id 7
    # differs only on project_id => a third instance.
    expect(payload[:agents][:count]).to eq(3)
    expect(payload[:agents][:previous_count]).to eq(1)
  end

  it 'returns a zero-filled ascending trend', :aggregate_failures do
    trend = payload[:sessions][:trend]

    # every timeframe bucket is present, in ascending order (matches bucket_starts exactly)
    expect(trend.map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
    # populated bucket carries its count...
    expect(trend.find { |point| point[:bucket_start] == Time.utc(2026, 7, 1) }[:count]).to eq(4)
    # ...and a bucket with no sessions is zero-filled rather than absent
    expect(trend.find { |point| point[:bucket_start] == Time.utc(2026, 7, 2) }[:count]).to eq(0)
  end

  it 'omits cumulative trends unless requested', :aggregate_failures do
    expect(payload[:sessions]).not_to have_key(:cumulative_trend)
    expect(payload[:agents]).not_to have_key(:cumulative_trend)
  end

  context 'with cumulative trends requested' do
    subject(:payload) do
      described_class.new(group, current_user: user, timeframe: timeframe, cumulative_trend: true)
        .execute.payload
    end

    it 'returns running totals seeded with the lookback period before the window', :aggregate_failures do
      sessions = payload[:sessions][:cumulative_trend]
      agents = payload[:agents][:cumulative_trend]

      expect(sessions.map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
      # id 4 (2026-06-20) predates the window and seeds every point; id 8
      # (2026-05-20) is older than the lookback and is not counted
      expect(sessions.first[:count]).to eq(1)
      expect(sessions.last[:count]).to eq(6)
      # ids 1/3/4 share one instance first seen before the window; ids 2 and 7
      # mint new instances on 2026-07-01; the chat row (id 5) adds none
      expect(agents.first[:count]).to eq(1)
      expect(agents.last[:count]).to eq(3)
    end
  end

  context 'with a project container' do
    subject(:payload) { described_class.new(project, current_user: user, timeframe: timeframe).execute.payload }

    it 'scopes by the project namespace traversal path' do
      expect(payload[:sessions][:count]).to eq(5)
    end
  end

  context 'with environments renamed in 18.6' do
    # ide (1) normalizes to chat (4), web (2) to ambient (5). Base row 1 is environment
    # NULL, row 2 is web (2). Adding ide, chat, and ambient rows for the same
    # (user, project) must not create one instance per spelling.
    before do
      insert_rows([
        { id: 20, definition: 'software_development', created_at: '2026-07-02 06:00:00',
          path: project_path, environment: 1 },
        { id: 21, definition: 'software_development', created_at: '2026-07-02 07:00:00',
          path: project_path, environment: 4 },
        { id: 22, definition: 'software_development', created_at: '2026-07-02 08:00:00',
          path: project_path, environment: 5 }
      ])
    end

    it 'collapses each renamed pair onto one agent instance' do
      # NULL environment (rows 1, 3), chat from ide+chat (20, 21), ambient from web+ambient
      # (2, 22), and row 7 which differs on project_id => 4 instances.
      expect(payload[:agents][:count]).to eq(4)
    end
  end

  context 'with agent-class segmentation' do
    using RSpec::Parameterized::TableSyntax

    # Base current-window rows have no agent_type (internal). Add external
    # sessions: two agent types, one of them twice, all sharing the
    # (user_id, project_id, environment) of internal rows 1 and 3.
    before do
      stub_feature_flags(ai_governance_sessions_api: false)
      insert_rows([
        { id: 10, definition: 'software_development', created_at: '2026-07-02 09:00:00',
          path: project_path, agent_type: 'claude_code' },
        { id: 11, definition: 'software_development', created_at: '2026-07-02 10:00:00',
          path: project_path, agent_type: 'cursor' },
        { id: 12, definition: 'convert_to_gitlab_ci', created_at: '2026-07-02 11:00:00',
          path: project_path, agent_type: 'claude_code' }
      ])
    end

    where(:agent_class, :expected_sessions, :expected_agents) do
      :all          | 8 | 5
      :internal_dap | 5 | 3
      :external     | 3 | 2
    end

    with_them do
      it 'filters sessions and keys agent instances by class', :aggregate_failures do
        payload = described_class.new(group, current_user: user, timeframe: timeframe,
          agent_class: agent_class).execute.payload

        expect(payload[:sessions][:count]).to eq(expected_sessions)
        expect(payload[:agents][:count]).to eq(expected_agents)
      end
    end

    context 'with the same agent type registered on two machines' do
      before do
        insert_rows([
          { id: 13, definition: 'software_development', created_at: '2026-07-02 12:00:00',
            path: project_path, agent_type: 'claude-code', agent_identity_id: 501 },
          { id: 14, definition: 'software_development', created_at: '2026-07-02 13:00:00',
            path: project_path, agent_type: 'claude-code', agent_identity_id: 502 }
        ])
      end

      it 'counts one instance per identity, not one per agent type', :aggregate_failures do
        payload = described_class.new(group, current_user: user, timeframe: timeframe,
          agent_class: :external).execute.payload

        expect(payload[:sessions][:count]).to eq(5)
        expect(payload[:agents][:count]).to eq(4)
      end
    end
  end

  context 'with chat conversations from otherwise-unseen agent instance keys' do
    before do
      insert_rows([
        { id: 40, definition: 'chat', created_at: '2026-07-02 09:00:00', path: project_path,
          user_id: 77701 },
        { id: 41, definition: 'chat', created_at: '2026-07-02 10:00:00', path: project_path,
          environment: 4 },
        { id: 42, definition: 'agentic_chat/v1', created_at: '2026-07-02 11:00:00', path: project_path,
          user_id: 77702 },
        # a chat version the registry has never shipped: the reference-based
        # guard must exclude it, an exact-definition list would count it
        { id: 43, definition: 'agentic_chat/v2', created_at: '2026-07-02 12:00:00', path: project_path,
          user_id: 77703 },
        # previous window: the guard applies on both sides of the boundary
        { id: 44, definition: 'chat', created_at: '2026-06-20 09:00:00', path: project_path,
          user_id: 77704 }
      ])
    end

    it 'counts them as sessions but never as agent instances', :aggregate_failures do
      # Each row's (user, environment) combo is unique across fixtures, so a
      # broken agents guard would mint new instances here, not hide silently.
      # agentic_chat/v1 is chat's flow-registry successor; guard it the same way.
      expect(payload[:sessions][:count]).to eq(9)
      expect(payload[:sessions][:previous_count]).to eq(2)
      expect(payload[:agents][:count]).to eq(3)
      expect(payload[:agents][:previous_count]).to eq(1)
    end
  end

  context 'with top user and project activity requested' do
    before do
      insert_rows([
        { id: 50, definition: 'software_development', created_at: '2026-07-02 09:00:00',
          path: project_path, user_id: 88801, project_id: 777 },
        { id: 51, definition: 'chat', created_at: '2026-07-02 10:00:00',
          path: project_path, user_id: 88801, project_id: 777 },
        { id: 53, definition: 'software_development', created_at: '2026-07-02 11:00:00',
          path: project_path, user_id: 88802 },
        { id: 54, definition: 'software_development', created_at: '2026-07-02 12:00:00',
          path: project_path, user_id: 88802 },
        # previous window: outside the rankings
        { id: 52, definition: 'software_development', created_at: '2026-06-20 10:00:00',
          path: project_path, user_id: 88801, project_id: 777 }
      ])
    end

    subject(:payload) do
      described_class.new(group, current_user: user, timeframe: timeframe,
        top_users_limit: 5, top_projects_limit: 5).execute.payload
    end

    it 'ranks users by deduplicated session count, chat included, ties broken by id' do
      expect(payload[:top_users]).to eq([
        { user_id: user.id, session_count: 5 },
        { user_id: 88801, session_count: 2 },
        { user_id: 88802, session_count: 2 }
      ])
    end

    it 'ranks projects, not counting rows without a project' do
      expect(payload[:top_projects]).to eq([
        { project_id: 777, session_count: 2 },
        { project_id: 12345, session_count: 1 }
      ])
    end

    it 'applies the agent class filter to the rankings' do
      payload = described_class.new(group, current_user: user, timeframe: timeframe,
        agent_class: :external, top_users_limit: 5).execute.payload

      expect(payload[:top_users]).to eq([])
    end

    it 'caps the rankings at the limit' do
      payload = described_class.new(group, current_user: user, timeframe: timeframe,
        top_users_limit: 1).execute.payload

      expect(payload[:top_users]).to match_array([{ user_id: user.id, session_count: 5 }])
    end
  end

  it 'omits the rankings unless requested', :aggregate_failures do
    expect(payload).not_to have_key(:top_users)
    expect(payload).not_to have_key(:top_projects)
  end

  context 'with namespace-attached sessions in two namespaces' do
    # num_nonnulls(namespace_id, project_id) = 1, so these carry a NULL project_id.
    # Without namespace_id in the key they collapse onto one agent instance.
    before do
      insert_rows([
        { id: 30, definition: 'software_development', created_at: '2026-07-02 06:00:00',
          path: project_path, project_id: 'NULL', namespace_id: 8001 },
        { id: 31, definition: 'software_development', created_at: '2026-07-02 07:00:00',
          path: project_path, project_id: 'NULL', namespace_id: 8002 }
      ])
    end

    it 'keeps the two namespaces as separate agent instances', :aggregate_failures do
      expect(payload[:sessions][:count]).to eq(7)
      # the three baseline instances plus one per namespace
      expect(payload[:agents][:count]).to eq(5)
    end
  end

  it 'omits tool calls unless requested' do
    expect(payload).not_to have_key(:tool_calls)
  end

  context 'with tool calls requested' do
    subject(:payload) do
      described_class.new(group, current_user: user, timeframe: timeframe, tool_calls: true).execute.payload
    end

    before do
      # the only workflow carrying an agent_type, so events on it are EXTERNAL
      insert_rows([{ id: 9, definition: 'software_development', created_at: '2026-07-01 09:00:00',
                     path: project_path, agent_type: 'claude-code' }])

      insert_audit_events([
        { event_name: 'ai_tool_invoked', created_at: '2026-07-01 10:00:00', path: project_path, workflow_id: 1 },
        { event_name: 'ai_tool_invoked', created_at: '2026-07-01 11:00:00', path: project_path, workflow_id: 1 },
        { event_name: 'ai_tool_invoked', created_at: '2026-07-02 09:00:00', path: project_path, workflow_id: 3 },
        { event_name: 'ai_tool_invoked', created_at: '2026-07-01 14:00:00', path: project_path, workflow_id: 9 },
        { event_name: 'ai_tool_invoked', created_at: '2026-07-02 15:00:00', path: project_path, workflow_id: 9 },
        # re-ingested duplicate of the first invocation; ReplacingMergeTree collapses it only on merge
        { event_name: 'ai_tool_invoked', created_at: '2026-07-01 10:00:00', path: project_path, workflow_id: 1,
          id: 0 },
        # an invocation that recorded no tool name, which the card also drops
        { event_name: 'ai_tool_invoked', created_at: '2026-07-01 15:00:00', path: project_path, workflow_id: 1,
          details: '{}' },
        # previous window
        { event_name: 'ai_tool_invoked', created_at: '2026-06-20 09:00:00', path: project_path, workflow_id: 1 },
        # excluded: a failure is not an invocation
        { event_name: 'ai_tool_execution_failed', created_at: '2026-07-01 12:00:00', path: project_path,
          workflow_id: 1 },
        # excluded: outside the hierarchy
        { event_name: 'ai_tool_invoked', created_at: '2026-07-01 13:00:00', path: '0/999/', workflow_id: 1 }
      ])
    end

    it 'counts invocations in the current and previous windows', :aggregate_failures do
      expect(payload[:tool_calls][:count]).to eq(5)
      expect(payload[:tool_calls][:previous_count]).to eq(1)
    end

    it 'returns a zero-filled ascending trend covering every bucket', :aggregate_failures do
      trend = payload[:tool_calls][:trend]

      expect(trend.map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
      expect(trend.find { |point| point[:bucket_start] == Time.utc(2026, 7, 1) }[:count]).to eq(3)
      expect(trend.find { |point| point[:bucket_start] == Time.utc(2026, 7, 3) }[:count]).to eq(0)
    end

    context 'with an event at timeframe.to' do
      before do
        insert_audit_events([
          { event_name: 'ai_tool_invoked', created_at: '2026-07-03 15:30:00', path: project_path, workflow_id: 1 }
        ])
      end

      it 'leaves it out, because the window end is exclusive', :aggregate_failures do
        expect(payload[:tool_calls][:count]).to eq(5)
        expect(payload[:tool_calls][:trend].last[:count]).to eq(0)
      end
    end

    context 'with a Claude Code invocation, which names the tool in details.name' do
      before do
        insert_audit_events([
          { event_name: 'ai_claude_tool_invoked', created_at: '2026-07-01 16:00:00', path: project_path,
            workflow_id: 1, details: '{"name":"Read"}' }
        ])
      end

      it 'counts it with the Duo invocations' do
        expect(payload[:tool_calls][:count]).to eq(6)
      end
    end

    context 'with a Claude Code event that has a session but no workflow' do
      before do
        insert_sessions([{ id: 1, source: :claude_code_glab, agent_type: 'claude-code',
                           created_at: '2026-07-01 09:00:00' }])
        insert_audit_events([
          { event_name: 'ai_claude_tool_invoked', created_at: '2026-07-01 16:00:00', path: project_path,
            workflow_id: 0, session_id: 1, details: '{"name":"Glob"}' }
        ])
      end

      def external_count(sessions:)
        stub_feature_flags(ai_governance_sessions_api: sessions)

        described_class.new(group, current_user: user, timeframe: timeframe, agent_class: :external,
          tool_calls: true).execute.payload[:tool_calls][:count]
      end

      it 'counts it as external with or without sessions', :aggregate_failures do
        expect(external_count(sessions: true)).to eq(3)
        expect(external_count(sessions: false)).to eq(3)
      end
    end

    context 'with a Duo session event that has no workflow' do
      before do
        insert_sessions([{ id: 2, source: :gitlab_duo, created_at: '2026-07-01 09:00:00' }])
        insert_audit_events([
          { event_name: 'ai_tool_invoked', created_at: '2026-07-01 17:00:00', path: project_path,
            workflow_id: 0, session_id: 2 }
        ])
      end

      def internal_count(sessions:)
        stub_feature_flags(ai_governance_sessions_api: sessions)

        described_class.new(group, current_user: user, timeframe: timeframe, agent_class: :internal_dap,
          tool_calls: true).execute.payload[:tool_calls][:count]
      end

      it 'counts it as DAP only when sessions are enabled', :aggregate_failures do
        expect(internal_count(sessions: true)).to eq(4)
        expect(internal_count(sessions: false)).to eq(3)
      end
    end

    it 'omits the cumulative trend unless requested' do
      expect(payload[:tool_calls]).not_to have_key(:cumulative_trend)
    end

    context 'with cumulative trends requested' do
      subject(:payload) do
        described_class.new(group, current_user: user, timeframe: timeframe, tool_calls: true,
          cumulative_trend: true).execute.payload
      end

      it 'returns a running total seeded with the invocations before the window', :aggregate_failures do
        cumulative = payload[:tool_calls][:cumulative_trend]

        expect(cumulative.map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
        # the 2026-06-20 invocation predates the window and seeds every point
        expect(cumulative.first[:count]).to eq(1)
        # seed plus the 5 invocations inside the window
        expect(cumulative.last[:count]).to eq(6)
      end
    end

    context 'with an INTERNAL_DAP agent class' do
      subject(:payload) do
        described_class.new(group, current_user: user, timeframe: timeframe, agent_class: :internal_dap,
          tool_calls: true).execute.payload
      end

      it 'counts only invocations from workflows without an agent type', :aggregate_failures do
        expect(payload[:tool_calls][:count]).to eq(3)
        expect(payload[:tool_calls][:previous_count]).to eq(1)
      end
    end

    context 'with an EXTERNAL agent class' do
      subject(:payload) do
        described_class.new(group, current_user: user, timeframe: timeframe, agent_class: :external,
          tool_calls: true, cumulative_trend: true).execute.payload
      end

      it 'counts only invocations from workflows with an agent type', :aggregate_failures do
        expect(payload[:tool_calls][:count]).to eq(2)
        expect(payload[:tool_calls][:previous_count]).to eq(0)
        expect(payload[:tool_calls][:trend].map { |point| point[:bucket_start] }).to eq(timeframe.bucket_starts)
        expect(payload[:tool_calls][:cumulative_trend].last[:count]).to eq(2)
      end
    end
  end

  context 'with the ai_governance_sessions_api feature flag enabled' do
    using RSpec::Parameterized::TableSyntax

    # Timeframe is 2026-06-26 to 2026-07-03 15:30; previous window from 2026-06-19,
    # cumulative lookback from 2026-05-27. Every class now reads the sessions table.
    before do
      stub_feature_flags(ai_governance_sessions_api: true)
      # the sync mirrors workflows 1 to 8 one to one; 61 has no mirror, so it never counts
      insert_rows([{ id: 61, definition: 'software_development', created_at: '2026-07-02 08:00:00',
                     path: project_path }])
      insert_session_rows([
        { id: 1, source: 0, flow_type: 'software_development', started_at: '2026-07-01 10:00:00',
          user_id: user.id, project_id: 'NULL' },
        # workflow 2 ran under another environment; the sessions table does not know
        { id: 2, source: 0, flow_type: 'software_development', started_at: '2026-07-01 12:00:00',
          user_id: user.id, project_id: 'NULL' },
        { id: 3, source: 0, flow_type: 'convert_to_gitlab_ci', started_at: '2026-06-28 09:00:00',
          user_id: user.id, project_id: 'NULL' },
        { id: 4, source: 0, flow_type: 'software_development', started_at: '2026-06-20 09:00:00',
          user_id: user.id, project_id: 'NULL' },
        { id: 5, source: 0, flow_type: 'chat', started_at: '2026-07-01 09:00:00',
          user_id: user.id, project_id: 'NULL' },
        { id: 6, source: 0, flow_type: 'software_development', started_at: '2026-07-01 09:00:00',
          user_id: user.id, project_id: 'NULL', path: '0/999/' },
        { id: 7, source: 0, flow_type: 'software_development', started_at: '2026-07-01 11:00:00',
          user_id: user.id, project_id: 12345 },
        { id: 8, source: 0, flow_type: 'software_development', started_at: '2026-05-20 09:00:00',
          user_id: 999_999, project_id: 'NULL' }
      ])
      # a legacy glab session synced from a workflow: Duo source, external agent type
      insert_rows([{ id: 60, definition: 'software_development', created_at: '2026-07-02 09:00:00',
                     path: project_path, agent_type: 'claude-code', user_id: 88801, project_id: 777 }])
      insert_session_rows([
        { id: 60, source: 0, agent_type: 'claude-code', flow_type: 'software_development',
          started_at: '2026-07-02 09:00:00' },
        { id: 101, agent_type: 'claude-code', agent_identity_id: 501, started_at: '2026-07-02 09:00:00' },
        { id: 102, agent_type: 'claude-code', agent_identity_id: 501, started_at: '2026-07-02 10:00:00' },
        { id: 103, source: 1, agent_type: 'claude-code', agent_identity_id: 502, started_at: '2026-07-01 12:00:00' },
        # chat flow type: a session, never an agent instance
        { id: 108, agent_type: 'claude-code', flow_type: 'chat', started_at: '2026-07-02 11:00:00',
          user_id: 88804, project_id: 779 },
        { id: 104, agent_type: 'opencode', started_at: '2026-06-20 09:00:00', user_id: 88802, project_id: 778 },
        { id: 106, agent_type: 'claude-code', agent_identity_id: 503, started_at: '2026-07-02 12:00:00' },
        { id: 109, agent_type: 'claude-code', started_at: '2026-07-02 12:00:00', path: '0/999/' },
        { id: 110, agent_type: 'opencode', started_at: '2026-05-20 09:00:00', user_id: 88805 }
      ])
      # newer versions: id 101 must count once, id 106 is deleted
      insert_session_rows([
        { id: 101, agent_type: 'claude-code', agent_identity_id: 501, started_at: '2026-07-02 09:00:00',
          replicated_at: '2026-07-03 00:00:00' },
        { id: 106, agent_type: 'claude-code', agent_identity_id: 503, started_at: '2026-07-02 12:00:00',
          replicated_at: '2026-07-03 00:00:00', deleted: true }
      ])
    end

    def execute(agent_class, **options)
      described_class.new(group, current_user: user, timeframe: timeframe, agent_class: agent_class, **options)
        .execute.payload
    end

    def trend_counts(kpi)
      kpi[:trend].filter_map { |point| [point[:bucket_start].day, point[:count]] if point[:count] > 0 }
    end

    # INTERNAL_DAP: the mirrors of workflows 1, 2, 3, 5 and 7; 4 in the previous window. Sessions 1
    # and 2 are one agent instance here, where the workflows path split them by environment.
    # EXTERNAL: 101/102 (one instance), 103 (a second identity), the legacy 60 and chat 108;
    # 104 in the previous window.
    where(:agent_class, :sessions, :previous_sessions, :agents, :previous_agents, :sessions_trend, :agents_trend) do
      :external     | 5  | 1 | 3 | 1 | [[1, 1], [2, 4]]          | [[1, 1], [2, 2]]
      :internal_dap | 5  | 1 | 2 | 1 | [[28, 1], [1, 4]]         | [[28, 1], [1, 2]]
      :all          | 10 | 2 | 5 | 2 | [[28, 1], [1, 5], [2, 4]] | [[28, 1], [1, 3], [2, 2]]
    end

    with_them do
      it 'reads every agent class from the sessions table', :aggregate_failures do
        payload = execute(agent_class)

        expect(payload[:sessions].slice(:count, :previous_count))
          .to eq(count: sessions, previous_count: previous_sessions)
        expect(payload[:agents].slice(:count, :previous_count)).to eq(count: agents, previous_count: previous_agents)
        expect(trend_counts(payload[:sessions])).to eq(sessions_trend)
        expect(trend_counts(payload[:agents])).to eq(agents_trend)
      end
    end

    where(:agent_class, :sessions_cumulative, :agents_cumulative) do
      :external     | [1, 6]  | [1, 4]
      :internal_dap | [1, 6]  | [1, 2]
      :all          | [2, 12] | [2, 6]
    end

    with_them do
      it 'seeds cumulative trends from the lookback period of the sessions table', :aggregate_failures do
        payload = execute(agent_class, cumulative_trend: true)

        expect(payload[:sessions][:cumulative_trend].values_at(0, -1).pluck(:count)).to eq(sessions_cumulative)
        expect(payload[:agents][:cumulative_trend].values_at(0, -1).pluck(:count)).to eq(agents_cumulative)
      end
    end

    where(:agent_class, :top_users, :top_projects) do
      :external     | [[88801, 4], [88804, 1]]                    | [[777, 4], [779, 1]]
      :internal_dap | [[ref(:user_id), 5]]                        | [[12345, 1]]
      :all          | [[ref(:user_id), 5], [88801, 4], [88804, 1]] | [[777, 4], [779, 1], [12345, 1]]
    end

    with_them do
      let(:user_id) { user.id }

      it 'ranks users and projects over the sessions table', :aggregate_failures do
        payload = execute(agent_class, top_users_limit: 5, top_projects_limit: 5)

        expect(payload[:top_users]).to eq(top_users.map { |id, count| { user_id: id, session_count: count } })
        expect(payload[:top_projects])
          .to eq(top_projects.map { |id, count| { project_id: id, session_count: count } })
      end
    end

    it 'applies the ranking limit' do
      expect(execute(:all, top_projects_limit: 1)[:top_projects]).to eq([{ project_id: 777, session_count: 4 }])
    end

    it 'scopes a project container by its traversal path' do
      payload = described_class.new(project, current_user: user, timeframe: timeframe, agent_class: :external)
        .execute.payload

      expect(payload[:sessions][:count]).to eq(5)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_sessions_api: false)
      end

      it 'ignores sessions and reads every class from workflows', :aggregate_failures do
        expect(execute(:all)[:sessions][:count]).to eq(7)
        expect(execute(:external)[:sessions][:count]).to eq(1)
      end
    end
  end

  def insert_audit_events(rows)
    rows.each_with_index do |row, index|
      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO ai_audit_events
          (id, event_name, created_at, author_id, workflow_id, ai_governance_session_id, details, traversal_path)
        VALUES ('#{format('00000000-0000-0000-0000-%012d', row.fetch(:id, index))}', '#{row[:event_name]}',
                '#{row[:created_at]}', #{user.id}, #{row[:workflow_id]}, #{row.fetch(:session_id, 0)},
                '#{row.fetch(:details, '{"tool_name":"Bash"}')}', '#{row[:path]}')
      SQL
    end
  end

  def insert_session_rows(rows)
    rows.each do |row|
      flow_type = row.key?(:flow_type) ? "'#{row[:flow_type]}'" : 'NULL'
      agent_type = row.key?(:agent_type) ? "'#{row[:agent_type]}'" : 'NULL'

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_ai_governance_sessions
          (id, namespace_id, project_id, user_id, created_at, updated_at, session_started_at, source, flow_type, agent_type, agent_identity_id, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, 1, #{row.fetch(:project_id, 777)}, #{row.fetch(:user_id, 88801)}, '#{row[:started_at]}', '#{row[:started_at]}', '#{row[:started_at]}', #{row.fetch(:source, 2)}, #{flow_type}, #{agent_type}, #{row.fetch(:agent_identity_id, 'NULL')},
           '#{row.fetch(:path, project_path)}', '#{row.fetch(:replicated_at, row[:started_at])}', #{row.fetch(:deleted, false)})
      SQL
    end
  end

  def insert_sessions(rows)
    rows.each do |row|
      agent_type = row[:agent_type] ? "'#{row[:agent_type]}'" : 'NULL'
      source = Ai::Governance::Session.sources.fetch(row[:source])

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_ai_governance_sessions
          (id, namespace_id, user_id, created_at, updated_at, session_started_at, source, agent_type,
           traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, #{project.project_namespace_id}, #{user.id}, '#{row[:created_at]}', '#{row[:created_at]}',
           '#{row[:created_at]}', #{source}, #{agent_type}, '#{project_path}', '#{row[:created_at]}', false)
      SQL
    end
  end

  def insert_rows(rows)
    rows.each do |row|
      agent_type = row.key?(:agent_type) ? "'#{row[:agent_type]}'" : 'NULL'
      agent_identity_id = row.fetch(:agent_identity_id, 'NULL')
      namespace_id = row.fetch(:namespace_id, 'NULL')

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_duo_workflows_workflows
          (id, user_id, project_id, namespace_id, environment, agent_type, agent_identity_id, created_at, workflow_definition, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, #{row.fetch(:user_id, user.id)}, #{row.fetch(:project_id, 'NULL')}, #{namespace_id}, #{row.fetch(:environment, 'NULL')}, #{agent_type}, #{agent_identity_id}, '#{row[:created_at]}', '#{row[:definition]}',
           '#{row[:path]}', '#{row.fetch(:replicated_at, row[:created_at])}', false)
      SQL
    end
  end
end
