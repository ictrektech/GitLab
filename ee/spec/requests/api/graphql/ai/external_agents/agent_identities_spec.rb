# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying aiAgentIdentities', feature_category: :software_composition_analysis do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:other_project) { create(:project) }

  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:authorized_user) { create(:user) }
  let_it_be(:group_membership) do
    create(:group_member, :guest, member_role: member_role, user: authorized_user, group: group)
  end

  let_it_be(:developer) { create(:user) }
  let_it_be(:active_identity) do
    create(:ai_agent_identity, user: developer, project: project, agent_type: 'claude-code',
      last_synced_at: 1.day.ago)
  end

  let_it_be(:inactive_identity) do
    create(:ai_agent_identity, user: authorized_user, project: subgroup_project, agent_type: 'cursor',
      last_synced_at: 40.days.ago)
  end

  let_it_be(:revoked_identity) do
    create(:ai_agent_identity, user: developer, project: project, agent_type: 'codex', revoked_at: 1.hour.ago)
  end

  let_it_be(:other_project_identity) { create(:ai_agent_identity, project: other_project) }

  let_it_be(:sessions) do
    create_list(:ai_governance_session, 2, :external, namespace: project.project_namespace, project: project,
      user: developer, agent_identity_id: active_identity.id)
  end

  let(:fields) do
    <<~FIELDS
      nodes {
        id
        agentType
        user { username }
        project { fullPath }
        createdAt
        lastSyncedAt
        revokedAt
        status
        sessionCount
      }
    FIELDS
  end

  let(:args) { {} }
  let(:current_user) { authorized_user }
  let(:query) do
    graphql_query_for(parent_type, { full_path: parent.full_path },
      query_graphql_field(:ai_agent_identities, args, fields))
  end

  let(:nodes) { graphql_data_at(parent_type, :ai_agent_identities, :nodes) }
  let(:node_ids) { nodes.pluck('id') }

  before do
    stub_licensed_features(
      custom_roles: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )
  end

  shared_examples 'denies access' do
    it 'returns null' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(parent_type, :ai_agent_identities)).to be_nil
    end
  end

  def global_ids(*identities)
    identities.map { |identity| global_id_of(identity).to_s }
  end

  context 'for a group' do
    let(:parent_type) { :group }
    let(:parent) { group }

    it 'returns the identities in the group and its subgroups, most recently synced first', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(node_ids).to eq(global_ids(active_identity, inactive_identity, revoked_identity))
      expect(nodes.first).to include(
        'agentType' => 'CLAUDE_CODE',
        'user' => { 'username' => developer.username },
        'project' => { 'fullPath' => project.full_path },
        'status' => 'ACTIVE',
        'sessionCount' => 2,
        'revokedAt' => nil
      )
      expect(nodes.pluck('status')).to eq(%w[ACTIVE INACTIVE REVOKED])
      expect(nodes.pluck('sessionCount')).to eq([2, 0, 0])
    end

    it 'counts sessions up to the limit, plus one' do
      stub_const('::Types::Ai::ExternalAgents::AgentIdentityType::SESSION_COUNT_LIMIT', 1)
      create(:ai_governance_session, :external, namespace: project.project_namespace, project: project,
        user: developer, agent_identity_id: active_identity.id)

      post_graphql(query, current_user: current_user)

      expect(nodes.pluck('sessionCount')).to eq([2, 0, 0])
    end

    it 'avoids N+1 queries' do
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_graphql(query, current_user: current_user) }

      # A new project adds ProjectType's own authorization queries, as for aiGovernanceSessions.
      create(:ai_agent_identity, project: subgroup_project, user: create(:user),
        last_synced_at: 2.days.ago).tap do |identity|
        create(:ai_governance_session, :external, namespace: subgroup_project.project_namespace,
          project: subgroup_project, user: identity.user, agent_identity_id: identity.id)
      end

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)
    end

    context 'with filters' do
      using RSpec::Parameterized::TableSyntax

      where(:filter_args, :expected) do
        { agent_types: [:CURSOR] } | [ref(:inactive_identity)]
        { status: :ACTIVE } | [ref(:active_identity)]
        { status: :INACTIVE } | [ref(:inactive_identity)]
        { status: :REVOKED } | [ref(:revoked_identity)]
      end

      with_them do
        let(:args) { filter_args }

        it 'returns the matching identities' do
          post_graphql(query, current_user: current_user)

          expect(node_ids).to eq(global_ids(*expected))
        end
      end

      context 'when filtering by user' do
        let(:args) { { user_id: global_id_of(developer).to_s } }

        it 'returns the identities the user connected' do
          post_graphql(query, current_user: current_user)

          expect(node_ids).to eq(global_ids(active_identity, revoked_identity))
        end
      end
    end

    it 'pages through identities, including those that never synced' do
      ids = []
      cursor = nil
      3.times do
        page_args = { first: 1, after: cursor }.compact
        post_graphql(graphql_query_for(:group, { full_path: group.full_path },
          query_graphql_field(:ai_agent_identities, page_args, 'nodes { id } pageInfo { endCursor }')),
          current_user: current_user)
        ids += graphql_data_at(:group, :ai_agent_identities, :nodes).pluck('id')
        cursor = graphql_data_at(:group, :ai_agent_identities, :page_info, :end_cursor)
      end

      expect(ids).to eq(global_ids(active_identity, inactive_identity, revoked_identity))
    end

    context 'without read_agent_artifacts' do
      let(:current_user) { create(:user, developer_of: group) }

      it_behaves_like 'denies access'
    end

    context 'with read_agent_artifacts on a subgroup only' do
      let_it_be(:subgroup_user) { create(:user) }
      let(:current_user) { subgroup_user }

      before_all do
        create(:group_member, :guest, member_role: member_role, user: subgroup_user, group: subgroup)
      end

      it_behaves_like 'denies access'

      context 'when querying the subgroup' do
        let(:parent) { subgroup }

        it 'returns the identities in the subgroup' do
          post_graphql(query, current_user: current_user)

          expect(node_ids).to eq(global_ids(inactive_identity))
        end
      end
    end

    context 'when the ai_governance_sessions_api feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_sessions_api: false)
      end

      it 'returns no identities' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(nodes).to eq([])
      end
    end
  end

  context 'for a project' do
    let(:parent_type) { :project }
    let(:parent) { project }

    it 'returns only the identities in the project' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(node_ids).to eq(global_ids(active_identity, revoked_identity))
    end

    context 'without read_agent_artifacts' do
      let(:current_user) { create(:user, developer_of: project) }

      it_behaves_like 'denies access'
    end
  end
end
