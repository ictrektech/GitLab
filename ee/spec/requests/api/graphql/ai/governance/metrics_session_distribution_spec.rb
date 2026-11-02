# frozen_string_literal: true

require 'spec_helper'

# The sessionDistribution slices read ClickHouse, so these examples live apart
# from metrics_spec.rb, which the graphql-document-integration job runs without
# a ClickHouse service because it reads the dashboard query document. Same
# separation as metrics_tool_calls_spec.rb.
RSpec.describe 'Querying the aiGovernanceMetrics session distribution', :click_house,
  feature_category: :compliance_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  # :read_agent_artifacts is a custom ability granted via member roles (requires
  # the custom_roles license), mirroring the duoWorkflowSessionArtifacts field on
  # the same dashboard. A group-level role cascades to the group's projects.
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:authorized_user) { create(:user) }
  let_it_be(:group_membership) do
    create(:group_member, :guest, member_role: member_role, user: authorized_user, group: group)
  end

  let(:timeframe) { :LAST_7_DAYS }

  let(:metrics_fields) do
    'sessionDistribution { totalSessions totalDevelopers slices { name sessions developers } }'
  end

  before do
    stub_licensed_features(
      custom_roles: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )

    allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)

    path = project.project_namespace.traversal_path(with_organization: true)
    ClickHouse::Client.execute(<<~SQL, :main)
      INSERT INTO siphon_ai_governance_sessions
        (id, namespace_id, user_id, created_at, updated_at, session_started_at, source, flow_type, agent_type, traversal_path, _siphon_replicated_at)
      VALUES
        (1, 1, 1, '2026-07-01 10:00:00', '2026-07-01 10:00:00', '2026-07-01 10:00:00', 0, 'software_development/v1', NULL, '#{path}', '2026-07-01 10:00:00'),
        (2, 1, 1, '2026-07-02 10:00:00', '2026-07-02 10:00:00', '2026-07-02 10:00:00', 2, NULL, 'claude-code', '#{path}', '2026-07-02 10:00:00'),
        (3, 1, 2, '2026-07-02 11:00:00', '2026-07-02 11:00:00', '2026-07-02 11:00:00', 2, NULL, 'claude-code', '#{path}', '2026-07-02 11:00:00')
    SQL
  end

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  shared_examples 'a sessionDistribution field' do
    let(:query_args) { { timeframe: timeframe } }

    let(:query) do
      graphql_query_for(parent_type, { full_path: container.full_path },
        query_graphql_field(:ai_governance_metrics, query_args, metrics_fields))
    end

    let(:distribution) { graphql_data_at(parent_type, :ai_governance_metrics, :session_distribution) }

    it 'returns sessions and distinct developers per slice with totals', :aggregate_failures do
      post_graphql(query, current_user: authorized_user)

      expect(graphql_errors).to be_nil
      expect(distribution).to eq(
        'totalSessions' => 3,
        'totalDevelopers' => 2,
        'slices' => [
          { 'name' => 'claude-code', 'sessions' => 2, 'developers' => 2 },
          { 'name' => 'gitlab_duo', 'sessions' => 1, 'developers' => 1 }
        ]
      )
    end

    context 'with an INTERNAL_DAP agentClass' do
      let(:query_args) { { timeframe: timeframe, agent_class: :INTERNAL_DAP } }

      it 'returns GitLab Duo sessions by flow type' do
        post_graphql(query, current_user: authorized_user)

        expect(distribution).to eq(
          'totalSessions' => 1,
          'totalDevelopers' => 1,
          'slices' => [{ 'name' => 'software_development', 'sessions' => 1, 'developers' => 1 }]
        )
      end
    end

    context 'with a LAST_24_HOURS timeframe' do
      let(:timeframe) { :LAST_24_HOURS }

      it 'counts sessions inside the shorter window only' do
        post_graphql(query, current_user: authorized_user)

        expect(distribution).to eq('totalSessions' => 0, 'totalDevelopers' => 0, 'slices' => [])
      end
    end
  end

  context 'for a group' do
    let(:parent_type) { :group }
    let(:container) { group }

    it_behaves_like 'a sessionDistribution field'
  end

  context 'for a project' do
    let(:parent_type) { :project }
    let(:container) { project }

    it_behaves_like 'a sessionDistribution field'
  end
end
