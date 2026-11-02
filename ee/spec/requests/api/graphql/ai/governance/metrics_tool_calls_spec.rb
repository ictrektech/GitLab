# frozen_string_literal: true

require 'spec_helper'

# The toolCalls KPI reads ClickHouse, so these examples live apart from
# metrics_spec.rb, which the graphql-document-integration job runs without a
# ClickHouse service because it reads the dashboard query document.
RSpec.describe 'Querying the aiGovernanceMetrics toolCalls KPI', :click_house,
  feature_category: :compliance_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let(:parent_type) { :group }
  let(:container) { group }
  let(:metrics_fields) do
    'toolCalls { count previousCount trend { bucketStart count } cumulativeTrend { bucketStart count } }'
  end

  let(:query) do
    graphql_query_for(parent_type, { full_path: container.full_path },
      query_graphql_field(:ai_governance_metrics, { timeframe: timeframe }, metrics_fields))
  end

  # The dashboard reads tool calls from ClickHouse wherever analytics is enabled,
  # so the KPI examples seed the ClickHouse tables directly.
  let(:workflow_created_at) { '2026-01-15 09:00:00' }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }
  let_it_be(:project) { create(:project, group: group) }

  # :read_agent_artifacts is a custom ability granted via member roles (requires
  # the custom_roles license), mirroring the duoWorkflowSessionArtifacts field on
  # the same dashboard. A group-level role cascades to the group's projects.
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:authorized_user) { create(:user) }
  let_it_be(:group_membership) do
    create(:group_member, :guest, member_role: member_role, user: authorized_user, group: group)
  end

  let_it_be(:unauthorized_user) { create(:user) }

  let(:timeframe) { :LAST_7_DAYS }

  before do
    stub_licensed_features(
      custom_roles: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )
    allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)

    insert_workflows([
      { id: 1 },                             # internal DAP: no agent type
      { id: 2, agent_type: 'claude_code' }   # external
    ])

    insert_events([
      { id: 1, workflow_id: 1, created_at: '2026-07-01 10:00:00' },
      { id: 2, workflow_id: 1, created_at: '2026-07-02 09:00:00' },
      { id: 3, workflow_id: 2, created_at: '2026-07-02 14:00:00' },
      # previous window, also the cumulative baseline
      { id: 4, workflow_id: 1, created_at: '2026-06-20 10:00:00' }
    ])
  end

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  it 'returns the invocation KPI with a cumulative trend', :aggregate_failures do
    post_graphql(query, current_user: authorized_user)

    kpi = graphql_data_at(parent_type, :ai_governance_metrics, :tool_calls)
    expect(graphql_errors).to be_nil
    expect(kpi).to include('count' => 3, 'previousCount' => 1)
    expect(kpi['trend'].length).to eq(8)
    # seeded with the pre-window invocation, then monotonic across the window
    expect(kpi['cumulativeTrend'].first['count']).to eq(1)
    expect(kpi['cumulativeTrend'].last['count']).to eq(4)
  end

  context 'with an EXTERNAL agentClass' do
    let(:query) do
      graphql_query_for(parent_type, { full_path: container.full_path },
        query_graphql_field(:ai_governance_metrics,
          { timeframe: timeframe, agent_class: :EXTERNAL }, metrics_fields))
    end

    it 'counts only invocations from workflows with an agent type', :aggregate_failures do
      post_graphql(query, current_user: authorized_user)

      kpi = graphql_data_at(parent_type, :ai_governance_metrics, :tool_calls)
      expect(graphql_errors).to be_nil
      expect(kpi).to include('count' => 1, 'previousCount' => 0)
    end
  end

  it 'buckets hourly for LAST_24_HOURS rather than assuming a daily 7-day window' do
    hourly = graphql_query_for(parent_type, { full_path: container.full_path },
      query_graphql_field(:ai_governance_metrics,
        { timeframe: :LAST_24_HOURS }, metrics_fields))
    post_graphql(hourly, current_user: authorized_user)

    trend = graphql_data_at(parent_type, :ai_governance_metrics, :tool_calls, :trend)
    expect(trend.length).to eq(25)
  end

  it 'skips the aggregate entirely when the field is not selected' do
    allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(false)
    unselected = graphql_query_for(parent_type, { full_path: container.full_path },
      query_graphql_field(:ai_governance_metrics, { timeframe: timeframe }, 'sessions { count }'))

    expect(::Ai::Governance::PostgresqlMetricsService).to receive(:new)
      .with(anything, hash_including(tool_calls: false)).and_call_original

    post_graphql(unselected, current_user: authorized_user)
  end

  context 'when toolCalls is selected while ai_governance_tool_calls is off' do
    before do
      stub_feature_flags(ai_governance_tool_calls: false)
    end

    it 'returns null for toolCalls and never asks the backend for it', :aggregate_failures do
      # The query selects toolCalls { cumulativeTrend }, so the gate must also keep
      # a flag-off request from triggering the history scans.
      expect(::Ai::Governance::MetricsService).to receive(:new)
        .with(anything, hash_including(tool_calls: false, cumulative_trend: false)).and_call_original

      post_graphql(query, current_user: authorized_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(parent_type, :ai_governance_metrics, :tool_calls)).to be_nil
    end
  end

  def insert_workflows(rows)
    rows.each do |row|
      agent_type = row[:agent_type] ? "'#{row[:agent_type]}'" : 'NULL'

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_duo_workflows_workflows
          (id, user_id, created_at, workflow_definition, agent_type, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, #{authorized_user.id}, '#{workflow_created_at}', 'software_development', #{agent_type},
           '#{project_path}', '#{workflow_created_at}', false)
      SQL
    end
  end

  def insert_events(rows)
    rows.each do |row|
      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO ai_audit_events
          (id, event_name, created_at, author_id, workflow_id, details, traversal_path)
        VALUES
          ('#{format('00000000-0000-0000-0000-%012d', row[:id])}', 'ai_tool_invoked', '#{row[:created_at]}',
           #{authorized_user.id}, #{row[:workflow_id]}, '{"tool_name":"Bash"}', '#{project_path}')
      SQL
    end
  end
end
