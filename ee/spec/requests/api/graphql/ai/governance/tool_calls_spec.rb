# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying aiGovernanceToolCalls', :click_house, feature_category: :compliance_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }

  # :read_agent_artifacts is a custom ability granted via member roles (requires
  # the custom_roles license), mirroring the aiGovernanceMetrics field on the
  # same dashboard. A group-level role cascades to the group's projects.
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:authorized_user) { create(:user) }
  let_it_be(:group_membership) do
    create(:group_member, :guest, member_role: member_role, user: authorized_user, group: group)
  end

  let_it_be(:unauthorized_user) { create(:user) }

  # Well before the window and its previous period, so any lower bound added to
  # the workflow lookup would drop these sessions and their events with them.
  let(:workflow_created_at) { '2026-01-15 09:00:00' }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }
  let(:timeframe) { :LAST_7_DAYS }
  let(:tool_calls_fields) { 'nodes { toolName count } approximate' }

  before do
    stub_licensed_features(
      custom_roles: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )

    # The dispatcher reads from ClickHouse only when analytics is enabled for
    # the namespace, and refuses otherwise; both parents route through it.
    allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)

    insert_workflows([
      { id: 1 },                             # internal DAP: no agent type
      { id: 2, agent_type: 'claude_code' }   # external
    ])

    insert_events([
      { id: 1, workflow_id: 2, tool_name: 'Bash', created_at: '2026-07-01 10:00:00' },
      { id: 2, workflow_id: 2, tool_name: 'Bash', created_at: '2026-07-01 11:00:00' },
      { id: 3, workflow_id: 1, tool_name: 'create_issue', created_at: '2026-07-01 12:00:00' },
      # not a tool invocation
      { id: 4, workflow_id: 2, tool_name: 'Bash', created_at: '2026-07-01 11:30:00',
        event_name: 'ai_tool_execution_failed' },
      # before the 7 day window, inside the 30 day one
      { id: 5, workflow_id: 2, tool_name: 'Bash', created_at: '2026-06-20 10:00:00' }
    ])
  end

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  shared_examples 'an aiGovernanceToolCalls field' do
    let(:query_args) { { timeframe: timeframe } }

    let(:query) do
      graphql_query_for(parent_type, { full_path: container.full_path },
        query_graphql_field(:ai_governance_tool_calls, query_args, tool_calls_fields))
    end

    let(:tool_calls) { graphql_data_at(parent_type, :ai_governance_tool_calls) }

    context 'when the user is authorized and the feature flag is enabled' do
      it 'returns per-tool counts from ClickHouse', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to be_nil
        expect(tool_calls['nodes']).to eq([
          { 'toolName' => 'Bash', 'count' => 2 },
          { 'toolName' => 'create_issue', 'count' => 1 }
        ])
        expect(tool_calls['approximate']).to be(false)
      end
    end

    context 'when the title and action type are selected' do
      let(:tool_calls_fields) { 'nodes { toolName title actionType count } approximate' }

      it 'names each tool like the Tool management tab, keeping unknown names as recorded' do
        post_graphql(query, current_user: authorized_user)

        expect(tool_calls['nodes']).to eq([
          { 'toolName' => 'Bash', 'title' => 'Bash', 'actionType' => nil, 'count' => 2 },
          { 'toolName' => 'create_issue', 'title' => 'Create Issue', 'actionType' => 'WRITE', 'count' => 1 }
        ])
      end
    end

    # The UI only offers LAST_7_DAYS today, so the other two windows are covered
    # here to keep the API from growing a 7-day assumption.
    context 'when timeframe is LAST_24_HOURS' do
      let(:timeframe) { :LAST_24_HOURS }

      it 'returns no tools, since the window starts after the seeded events' do
        post_graphql(query, current_user: authorized_user)

        expect(tool_calls['nodes']).to be_empty
      end
    end

    context 'when timeframe is LAST_30_DAYS' do
      let(:timeframe) { :LAST_30_DAYS }

      it 'includes the event that LAST_7_DAYS excludes', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls['nodes']).to eq([
          { 'toolName' => 'Bash', 'count' => 3 },
          { 'toolName' => 'create_issue', 'count' => 1 }
        ])
      end
    end

    context 'when agentClass is INTERNAL_DAP' do
      let(:query_args) { { timeframe: timeframe, agent_class: :INTERNAL_DAP } }

      it 'returns only tools invoked from workflows without an agent type', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls['nodes']).to eq([{ 'toolName' => 'create_issue', 'count' => 1 }])
      end
    end

    context 'when agentClass is EXTERNAL' do
      let(:query_args) { { timeframe: timeframe, agent_class: :EXTERNAL } }

      it 'returns only tools invoked from workflows with an agent type', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls['nodes']).to eq([{ 'toolName' => 'Bash', 'count' => 2 }])
      end
    end

    context 'when agentClass is omitted' do
      let(:query_args) { { timeframe: timeframe } }

      it 'defaults to ALL and returns every tool' do
        post_graphql(query, current_user: authorized_user)

        expect(tool_calls['nodes'].pluck('toolName')).to eq(%w[Bash create_issue])
      end
    end

    context 'when only byRisk is selected' do
      let(:tool_calls_fields) { 'byRisk { total slices { risk count } }' }

      it 'returns the calls per risk level without running the top tools query', :aggregate_failures do
        expect(::Ai::Governance::ToolCallsService).not_to receive(:new)

        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        # create_issue is a registry write tool; Bash is not in the registry
        expect(tool_calls['byRisk']).to eq(
          'total' => 3,
          'slices' => [
            { 'risk' => 'READ', 'count' => 0 },
            { 'risk' => 'WRITE', 'count' => 1 },
            { 'risk' => 'DESTROY', 'count' => 0 },
            { 'risk' => 'UNCLASSIFIED', 'count' => 2 }
          ]
        )
      end

      context 'when ClickHouse is not enabled for analytics' do
        before do
          allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(false)
        end

        it 'returns null' do
          post_graphql(query, current_user: authorized_user)

          expect(tool_calls).to be_nil
        end
      end

      context 'when the ai_governance_tool_calls feature flag is disabled' do
        before do
          stub_feature_flags(ai_governance_tool_calls: false)
        end

        it 'returns null without errors', :aggregate_failures do
          post_graphql(query, current_user: authorized_user)

          expect(graphql_errors).to be_nil
          expect(tool_calls).to be_nil
        end
      end
    end

    context 'when only the top tools are selected' do
      it 'does not run the risk query' do
        expect(::Ai::Governance::ToolCallsByRiskService).not_to receive(:new)

        post_graphql(query, current_user: authorized_user)
      end
    end

    context 'when both the top tools and byRisk are selected' do
      let(:tool_calls_fields) { 'nodes { toolName count } byRisk { total }' }

      it 'returns both', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls['nodes'].pluck('toolName')).to eq(%w[Bash create_issue])
        expect(tool_calls['byRisk']).to eq('total' => 3)
      end
    end

    context 'when ClickHouse is not enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(false)
      end

      it 'returns null rather than an empty list', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls).to be_nil
      end
    end

    context 'when the service fails' do
      before do
        allow_next_instance_of(::Ai::Governance::ToolCallsService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'backend unavailable'))
        end
      end

      it 'returns null rather than an empty list', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls).to be_nil
      end
    end

    context 'when the ai_governance_dashboard feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_dashboard: false)
      end

      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls).to be_nil
      end
    end

    context 'when the ai_governance_tool_calls feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_tool_calls: false)
      end

      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: authorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls).to be_nil
      end
    end

    context 'when the user is not authorized' do
      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: unauthorized_user)

        expect(graphql_errors).to be_nil
        expect(tool_calls).to be_nil
      end
    end

    context 'when the user is anonymous' do
      it 'returns null without errors', :aggregate_failures do
        post_graphql(query, current_user: nil)

        expect(graphql_errors).to be_nil
        expect(tool_calls).to be_nil
      end
    end
  end

  context 'for a group' do
    let(:parent_type) { :group }
    let(:container) { group }

    it_behaves_like 'an aiGovernanceToolCalls field'
  end

  context 'for a project' do
    let(:parent_type) { :project }
    let(:container) { project }

    it_behaves_like 'an aiGovernanceToolCalls field'
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
      details = row[:tool_name] ? %({"tool_name":"#{row[:tool_name]}"}) : '{}'

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO ai_audit_events
          (id, event_name, created_at, author_id, workflow_id, details, traversal_path)
        VALUES
          ('#{event_uuid(row[:id])}', '#{row.fetch(:event_name, 'ai_tool_invoked')}', '#{row[:created_at]}',
           #{authorized_user.id}, #{row[:workflow_id]}, '#{details}', '#{project_path}')
      SQL
    end
  end

  def event_uuid(number)
    format('00000000-0000-0000-0000-%012d', number)
  end
end
