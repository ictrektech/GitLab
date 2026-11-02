# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.orbit', feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:orbit_on_group) { create(:group, :private, name: 'Orbit on', reporters: user) }
  let_it_be(:owned_group) { create(:group, :private, name: 'Owned', owners: user) }
  let_it_be(:subgroup_root) { create(:group, :private, name: 'Subgroup root') }
  let_it_be(:subgroup) { create(:group, :private, parent: subgroup_root, developers: user) }
  let_it_be(:other_group) { create(:group, :private) }

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: orbit_on_group)
    create(:knowledge_graph_enabled_namespace, namespace: subgroup_root)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  def full_paths(*path)
    expect_graphql_errors_to_be_empty

    graphql_data_at(*path, :nodes).pluck('fullPath')
  end

  it 'accepts the same token scopes as Query.groups' do
    expect(GitlabSchema.types['Query'].fields['orbit']).to include_graphql_scopes(:api, :read_api, :ai_workflows)
  end

  it 'returns no groups to an ai_workflows token' do
    token = create(:oauth_access_token, user: user, scopes: [:ai_workflows, :mcp])

    post_graphql(graphql_query_for(:orbit, {}, 'memberGroups { nodes { id } } groups { nodes { id } }'),
      token: { oauth_access_token: token })

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit)).to eq('memberGroups' => nil, 'groups' => nil)
  end

  context 'with an administrator token', :enable_admin_mode do
    let_it_be(:admin) { create(:admin) }

    let(:query) { graphql_query_for(:orbit, {}, 'access { state } excludedGroups { nodes { id } }') }

    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    def post_with_scopes(*scopes)
      post_graphql(query, token: { oauth_access_token: create(:oauth_access_token, user: admin, scopes: scopes) })
    end

    it 'returns no instance access or excluded groups to an ai_workflows token' do
      post_with_scopes(:ai_workflows, :mcp, :admin_mode)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit)).to eq('access' => nil, 'excludedGroups' => nil)
    end

    it 'returns the instance access and excluded groups to a read_api token' do
      post_with_scopes(:read_api, :admin_mode)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit).values).to all(be_present)
    end
  end

  it 'returns the groups but no excluded groups to a user who is not an administrator' do
    post_graphql(graphql_query_for(:orbit, {}, 'groups { nodes { id } } excludedGroups { nodes { id } }'),
      current_user: user)

    expect(graphql_data_at(:orbit, :groups, :nodes)).to be_present
    expect(graphql_data_at(:orbit, :excluded_groups)).to be_nil
  end

  describe 'granular token authorization' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_orbit do
      let(:boundary_object) { :user }
      let(:request) do
        post_graphql(graphql_query_for(:orbit, {}, 'groups { nodes { id } }'), token: { personal_access_token: pat })
      end
    end
  end

  it 'returns null when the user is not signed in' do
    post_graphql(graphql_query_for(:orbit, {}, 'groups { nodes { id } }'), current_user: nil)

    expect(graphql_data_at(:orbit)).to be_nil
  end

  describe 'groups' do
    where(:args) do
      [
        [{ top_level_only: true, all_available: false }],
        [{ top_level_only: true, all_available: false, search: 'Orbit' }],
        [{ top_level_only: true, owned_only: true }],
        [{ all_available: false }]
      ]
    end

    with_them do
      it 'returns the same groups as Query.groups for the same arguments' do
        [true, false].each do |enabled|
          groups_args = args.merge(with_knowledge_graph_enabled: enabled)
          post_graphql(graphql_query_for(:groups, groups_args, 'nodes { fullPath }'), current_user: user)
          expected = full_paths(:groups)

          orbit_groups = query_graphql_field(:groups, args.merge(enabled: enabled), 'nodes { fullPath }')
          post_graphql(graphql_query_for(:orbit, {}, orbit_groups), current_user: user)

          expect(full_paths(:orbit, :groups)).to eq(expected)
        end
      end
    end

    it 'returns only the groups with Orbit on when enabled is true' do
      orbit_groups = query_graphql_field(:groups, { top_level_only: true, all_available: false, enabled: true },
        'nodes { fullPath }')

      post_graphql(graphql_query_for(:orbit, {}, orbit_groups), current_user: user)

      expect(full_paths(:orbit, :groups)).to contain_exactly(orbit_on_group.full_path)
    end

    it 'returns every group of the user when enabled is false' do
      orbit_groups = query_graphql_field(:groups, { top_level_only: true, all_available: false }, 'nodes { fullPath }')

      post_graphql(graphql_query_for(:orbit, {}, orbit_groups), current_user: user)

      expect(full_paths(:orbit, :groups)).to contain_exactly(orbit_on_group.full_path, owned_group.full_path)
    end
  end

  describe 'memberGroups' do
    let_it_be(:project_member_root) { create(:group, :private, name: 'Project member root') }

    before_all do
      create(:knowledge_graph_enabled_namespace, namespace: project_member_root)
      create(:project, group: project_member_root, developers: user)
    end

    def member_groups_query(args, fields = 'nodes { fullPath }')
      graphql_query_for(:orbit, {}, query_graphql_field(:member_groups, args, fields))
    end

    def member_group_paths(args = {})
      post_graphql(member_groups_query(args), current_user: user)

      full_paths(:orbit, :member_groups)
    end

    it 'returns the highest Reporter+ group of each group tree with Orbit on when enabled is true' do
      expect(member_group_paths(enabled: true)).to contain_exactly(orbit_on_group.full_path, subgroup.full_path)
    end

    it 'adds the groups with Orbit off when enabled is false' do
      expect(member_group_paths)
        .to contain_exactly(orbit_on_group.full_path, subgroup.full_path, owned_group.full_path)
    end

    it 'finds a subgroup by the name of its parent group' do
      expect(member_group_paths(search: 'Subgroup root')).to contain_exactly(subgroup.full_path)
    end

    it 'searches only the member groups' do
      create(:group, :private, name: 'Orbit on other')

      expect(member_group_paths(search: 'Orbit on')).to contain_exactly(orbit_on_group.full_path)
    end

    it 'leaves out the groups where the user is a Guest' do
      guest_group = create(:group, :private, guests: user)

      expect(member_group_paths).not_to include(guest_group.full_path)
    end

    it 'returns only the member groups of an administrator', :enable_admin_mode do
      admin = create(:admin, reporter_of: owned_group)

      post_graphql(member_groups_query({}), current_user: admin)

      expect(full_paths(:orbit, :member_groups)).to contain_exactly(owned_group.full_path)
    end

    it 'pages through the groups in ID order without repeating a group' do
      paths = []
      cursor = nil
      3.times do
        page_args = { first: 1, after: cursor }.compact
        post_graphql(member_groups_query(page_args, 'nodes { fullPath } pageInfo { endCursor }'), current_user: user)
        paths += full_paths(:orbit, :member_groups)
        cursor = graphql_data_at(:orbit, :member_groups, :page_info, :end_cursor)
      end

      expect(paths).to eq([orbit_on_group, owned_group, subgroup].sort_by(&:id).map(&:full_path))
    end

    it 'returns the Orbit state of the top-level group, with no query per group' do
      query = member_groups_query({}, 'nodes { orbit { enabled enabledAt } }')

      post_graphql(query, current_user: user)
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }

      create_list(:group, 2, :private).each do |root|
        create(:knowledge_graph_enabled_namespace, namespace: root)
        create(:group, :private, parent: root, developers: user)
      end
      create(:group, :private, parent: create(:group, :private), developers: user)
      create(:group, :private, reporters: user)

      expect { post_graphql(query, current_user: user) }.not_to exceed_query_limit(control)

      states = graphql_data_at(:orbit, :member_groups, :nodes, :orbit)
      expect(states.pluck('enabled').tally).to eq(true => 4, false => 3)
      expect(states.reject { |state| state['enabled'] }.pluck('enabledAt')).to all(be_nil)
      expect(states.select { |state| state['enabled'] }.pluck('enabledAt')).to all(be_present)
    end
  end
end
