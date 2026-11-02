# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying Orbit data of a group or project', :clean_gitlab_redis_rate_limiting,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:user) { create(:user, :with_namespace) }
  let_it_be(:group) { create(:group, :private) }
  let_it_be(:project) { create(:project, :private, group: group) }
  let_it_be(:personal_project) { create(:project, :private, namespace: user.namespace) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:out_of_scope_paths) { [] }
  let(:current_user) { user }

  let(:status_fields) { 'indexingStatus { phase projects { indexed totalKnown gaps } domains { name phase } }' }
  let(:item_counts_fields) { 'itemCounts { domains { name entities { name count } } }' }
  let(:indexing_fields) do
    'indexing { state lastCompletedAt projects { indexed notIndexed total } areas { name state } }'
  end

  let(:item_count_areas_fields) { 'itemCounts { areas { name itemTypes { name count } } }' }

  before_all do
    group.add_reporter(user)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })

    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    [:get_indexing_status, :get_item_counts].each do |grpc_method|
      allow(grpc_client).to receive(grpc_method) do |traversal_paths:, **|
        grpc_response(grpc_method, traversal_paths)
      end
    end

    authorization_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext)
    allow(authorization_context).to receive(:traversal_paths_in_scope) { |paths| paths - out_of_scope_paths }
    allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(authorization_context)
  end

  def indexing_status(traversal_path)
    {
      traversal_path: traversal_path,
      phase: 'syncing',
      last_completed_at: Time.utc(2026, 10, 22, 19, 0, 0),
      projects: { indexed: 1, total_known: 2, gaps: 1 },
      domains: [
        { name: 'ci', phase: 'ready' },
        { name: 'source_code', phase: 'syncing' }
      ]
    }
  end

  def item_counts(traversal_path)
    {
      traversal_path: traversal_path,
      domains: [{ name: 'source_code', entities: [{ name: 'File', count: 3_000_000_000 }] }]
    }
  end

  def grpc_response(grpc_method, traversal_paths)
    case grpc_method
    when :get_indexing_status then { statuses: traversal_paths.map { |path| indexing_status(path) } }
    when :get_item_counts then { namespaces: traversal_paths.map { |path| item_counts(path) } }
    end
  end

  def query_for(target, orbit_fields)
    graphql_query_for(target.is_a?(Project) ? :project : :group, { fullPath: target.full_path },
      "orbit { #{orbit_fields} }")
  end

  shared_examples 'an Orbit field' do
    let(:query) { query_for(target, "#{status_fields} #{item_counts_fields}") }

    it 'returns the Orbit data' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(parent, :orbit)).to be_present
    end

    it 'returns no Orbit data and makes no gRPC call when the Orbit license is not available' do
      stub_licensed_features(orbit: false)

      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(parent, :orbit)).to eq('indexingStatus' => nil, 'itemCounts' => nil)
      expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
    end

    context 'when the user cannot read the target' do
      let(:current_user) { create(:user) }

      it 'returns nil for the target' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(parent)).to be_nil
      end
    end
  end

  shared_examples 'an Orbit status field' do |field, rate_limit_key|
    let(:query) { query_for(target, fields) }

    context "when the target is out of the user's Orbit scope" do
      let(:out_of_scope_paths) { [traversal_path] }

      it 'returns nil without a gRPC call' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(parent, :orbit, field)).to be_nil
        expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
      end
    end

    context 'when the Orbit server does not have the RPC' do
      before do
        allow(grpc_client).to receive(grpc_method).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
            'boom', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
          )
        )
      end

      it 'returns nil without an error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(parent, :orbit, field)).to be_nil
      end
    end

    context 'when the gRPC call fails' do
      before do
        allow(grpc_client).to receive(grpc_method).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
            'boom', grpc_code: GRPC::Core::StatusCodes::UNAVAILABLE
          )
        )
      end

      it 'returns an error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include('Orbit request failed')
      end
    end

    context 'when the Orbit authorization header cannot be built' do
      before do
        allow(grpc_client).to receive(grpc_method).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::AuthorizationError, 'boom'
        )
      end

      it 'returns an error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include('Orbit request failed')
      end
    end

    context 'when the rate limit is exceeded' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(rate_limit_key, hash_including(scope: { user: current_user })).and_return(true)
      end

      it 'returns an error without a gRPC call' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include(/requested too many times/)
        expect(grpc_client).not_to have_received(grpc_method)
      end
    end

    context 'when the user is in the Orbit rate limit allowlist' do
      before do
        stub_application_setting(
          orbit_indexing_status_limit: 1,
          orbit_item_counts_limit: 1,
          orbit_rate_limit_allowlist: [current_user.username]
        )
      end

      it 'does not throttle the user' do
        2.times { post_graphql(query, current_user: current_user) }

        expect_graphql_errors_to_be_empty
      end
    end
  end

  shared_examples 'Orbit data of a target' do
    it_behaves_like 'an Orbit field'

    describe 'indexingStatus' do
      let(:fields) { status_fields }
      let(:grpc_method) { :get_indexing_status }

      it_behaves_like 'an Orbit status field', :indexing_status, :orbit_indexing_status

      it 'returns the indexing status' do
        post_graphql(query_for(target, status_fields), current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(parent, :orbit, :indexing_status)).to eq(
          'phase' => 'SYNCING',
          'projects' => { 'indexed' => 1, 'totalKnown' => 2, 'gaps' => 1 },
          'domains' => [
            { 'name' => 'ci', 'phase' => 'READY' },
            { 'name' => 'source_code', 'phase' => 'SYNCING' }
          ]
        )
        expect(grpc_client).to have_received(:get_indexing_status).with(
          user: current_user, traversal_paths: [traversal_path], request_context: an_instance_of(
            Analytics::KnowledgeGraph::RequestContext
          )
        )
      end
    end

    describe 'request context' do
      def expect_request_context_sent(**attributes)
        expect(grpc_client).to have_received(:get_indexing_status).with(
          hash_including(request_context: having_attributes(**attributes))
        )
      end

      it 'carries the personal access token type when authenticated with a PAT' do
        post_graphql(query_for(target, status_fields), current_user: current_user)

        expect_request_context_sent(token_type: 'personal_access_token', source_type: 'rest')
      end

      it 'carries no token type for a session-authenticated request' do
        login_as(current_user)

        post_graphql(query_for(target, status_fields))

        expect_request_context_sent(token_type: nil)
      end

      it 'carries the OAuth token type and the dws source type for an ai_workflows token' do
        token = create(:oauth_access_token, user: current_user, scopes: [:ai_workflows, :mcp])

        post_graphql(query_for(target, indexing_fields), token: { oauth_access_token: token })

        expect_request_context_sent(token_type: 'oauth_access_token', source_type: 'dws')
      end
    end

    describe 'indexing' do
      let(:fields) { indexing_fields }
      let(:grpc_method) { :get_indexing_status }

      it_behaves_like 'an Orbit status field', :indexing, :orbit_indexing_status

      it 'returns the indexing state with the new names' do
        post_graphql(query_for(target, indexing_fields), current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(parent, :orbit, :indexing)).to eq(
          'state' => 'INDEXING',
          'lastCompletedAt' => '2026-10-22T19:00:00Z',
          'projects' => { 'indexed' => 1, 'notIndexed' => 1, 'total' => 2 },
          'areas' => [
            { 'name' => 'ci', 'state' => 'READY' },
            { 'name' => 'source_code', 'state' => 'INDEXING' }
          ]
        )
      end

      it 'shares one gRPC call with indexingStatus' do
        post_graphql(query_for(target, "#{indexing_fields} #{status_fields}"), current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(grpc_client).to have_received(:get_indexing_status).once
      end
    end

    describe 'itemCounts' do
      let(:fields) { item_counts_fields }
      let(:grpc_method) { :get_item_counts }

      it_behaves_like 'an Orbit status field', :item_counts, :orbit_item_counts

      it 'returns the item counts' do
        post_graphql(query_for(target, item_counts_fields), current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(parent, :orbit, :item_counts)).to eq(
          'domains' => [{ 'name' => 'source_code', 'entities' => [{ 'name' => 'File', 'count' => '3000000000' }] }]
        )
        expect(grpc_client).to have_received(:get_item_counts).with(
          user: current_user, traversal_paths: [traversal_path], request_context: an_instance_of(
            Analytics::KnowledgeGraph::RequestContext
          )
        )
      end
    end
  end

  context 'with a group' do
    let(:target) { group }
    let(:parent) { :group }
    let(:traversal_path) { group.traversal_path(with_organization: true) }

    it_behaves_like 'Orbit data of a target'
  end

  describe 'itemCounts areas' do
    it 'returns the item counts with the new names' do
      post_graphql(query_for(group, item_count_areas_fields), current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :orbit, :item_counts)).to eq(
        'areas' => [{ 'name' => 'source_code', 'itemTypes' => [{ 'name' => 'File', 'count' => '3000000000' }] }]
      )
    end
  end

  describe 'enabled and access' do
    let_it_be(:owner) { create(:user, owner_of: group) }

    let(:fields) { 'enabled access { state reason }' }

    before do
      stub_licensed_features(orbit: true)
    end

    it 'returns the Orbit state and the access of the top-level group to an Owner' do
      create(:knowledge_graph_enabled_namespace, namespace: group)

      post_graphql(query_for(group, fields), current_user: owner)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :orbit)).to eq(
        'enabled' => true, 'access' => { 'state' => 'LICENSED', 'reason' => 'PLAN' }
      )
    end

    it 'returns the Orbit state but not the access to a member below Owner' do
      post_graphql(query_for(group, fields), current_user: user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :orbit)).to eq('enabled' => false, 'access' => nil)
    end

    it 'returns the Orbit state also when Orbit is not available to the user' do
      stub_licensed_features(orbit: false)

      post_graphql(query_for(group, 'enabled'), current_user: owner)

      expect(graphql_data_at(:group, :orbit, :enabled)).to be(false)
    end

    it 'returns null for a project' do
      post_graphql(query_for(project, fields), current_user: owner)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :orbit)).to eq('enabled' => nil, 'access' => nil)
    end
  end

  context 'with an instance license but no trial or purchase' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_feature_flags(orbit_promo_access_gate: true)
      create(:knowledge_graph_enabled_namespace, namespace: group)
    end

    it 'returns the indexing status and enabledAt' do
      post_graphql(query_for(group, 'enabledAt indexing { state }'), current_user: user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :orbit, :indexing)).to be_present
      expect(graphql_data_at(:group, :orbit, :enabled_at)).to be_present
    end
  end

  context 'with a project' do
    let(:target) { project }
    let(:parent) { :project }
    let(:traversal_path) { project.project_namespace.traversal_path(with_organization: true) }

    it_behaves_like 'Orbit data of a target'

    context 'when the project is in a personal namespace' do
      it 'returns nil for both fields without a gRPC call' do
        post_graphql(query_for(personal_project, "#{status_fields} #{item_counts_fields}"), current_user: current_user)

        expect(graphql_data_at(:project, :orbit, :indexing_status)).to be_nil
        expect(graphql_data_at(:project, :orbit, :item_counts)).to be_nil
        expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
      end
    end
  end

  context 'when an admin is not a member of the group', :enable_admin_mode do
    let(:current_user) { create(:admin) }
    let(:traversal_path) { group.traversal_path(with_organization: true) }

    before do
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_call_original
    end

    it 'returns the indexing status and item counts' do
      post_graphql(query_for(group, "#{status_fields} #{item_counts_fields}"), current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :orbit, :indexing_status, :phase)).to eq('SYNCING')
      expect(graphql_data_at(:group, :orbit, :item_counts)).to be_present
      expect(grpc_client).to have_received(:get_indexing_status)
        .with(hash_including(user: current_user, traversal_paths: [traversal_path]))
      expect(grpc_client).to have_received(:get_item_counts)
        .with(hash_including(user: current_user, traversal_paths: [traversal_path]))
    end
  end

  describe 'batching' do
    let_it_be(:other_group) { create(:group, :private, reporters: user) }

    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") { orbit { #{fields} } }
          otherGroup: group(fullPath: "#{other_group.full_path}") { orbit { #{fields} } }
          project(fullPath: "#{project.full_path}") { orbit { #{fields} } }
        }
      GRAPHQL
    end

    def results
      graphql_data.values.map { |target| target.dig('orbit', field) }
    end

    shared_examples 'a batched Orbit status field' do |grpc_method, rate_limit_key|
      it 'sends one gRPC call for all groups and projects' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(results).to all(be_present)
        expect(grpc_client).to have_received(grpc_method).once.with(
          user: current_user,
          traversal_paths: contain_exactly(
            group.traversal_path(with_organization: true),
            other_group.traversal_path(with_organization: true),
            project.project_namespace.traversal_path(with_organization: true)
          ),
          request_context: an_instance_of(Analytics::KnowledgeGraph::RequestContext)
        )
      end

      context 'when the gRPC call fails' do
        before do
          allow(grpc_client).to receive(grpc_method).and_raise(
            Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
              'boom', grpc_code: GRPC::Core::StatusCodes::UNAVAILABLE
            )
          )
        end

        it 'returns the error on each field after one gRPC call and one rate limit check' do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original

          post_graphql(query, current_user: current_user)

          expect(graphql_errors.pluck('path')).to contain_exactly(
            ['group', 'orbit', field], ['otherGroup', 'orbit', field], ['project', 'orbit', field]
          )
          expect(graphql_errors.pluck('message')).to all(eq('Orbit request failed'))
          expect(grpc_client).to have_received(grpc_method).once
          expect(Gitlab::ApplicationRateLimiter).to have_received(:throttled?).with(rate_limit_key, anything).once
        end
      end

      context "when one group is out of the user's Orbit scope" do
        let(:out_of_scope_paths) { [other_group.traversal_path(with_organization: true)] }

        it 'returns the data of the other targets' do
          post_graphql(query, current_user: current_user)

          expect_graphql_errors_to_be_empty
          expect(graphql_data_at(:group, :orbit, field)).to be_present
          expect(graphql_data_at(:other_group, :orbit, field)).to be_nil
          expect(graphql_data_at(:project, :orbit, field)).to be_present
          expect(grpc_client).to have_received(grpc_method).once.with(
            hash_including(traversal_paths: contain_exactly(
              group.traversal_path(with_organization: true),
              project.project_namespace.traversal_path(with_organization: true)
            ))
          )
        end
      end

      it 'sends more paths than the Orbit limit in more than one call' do
        stub_const("#{Resolvers::Analytics::Orbit::StatusResolvable}::MAX_TRAVERSAL_PATHS_PER_CALL", 2)

        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(results).to all(be_present)
        expect(grpc_client).to have_received(grpc_method).twice
      end

      it 'checks the rate limit before each gRPC call' do
        stub_const("#{Resolvers::Analytics::Orbit::StatusResolvable}::MAX_TRAVERSAL_PATHS_PER_CALL", 2)
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(rate_limit_key, hash_including(scope: { user: current_user })).and_return(false, true)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors.pluck('message')).to all(match(/requested too many times/))
        expect(graphql_errors.size).to eq(1)
        expect(results.compact.size).to eq(2)
        expect(grpc_client).to have_received(grpc_method).once
      end

      it 'keeps the data of a slice when a later slice fails' do
        stub_const("#{Resolvers::Analytics::Orbit::StatusResolvable}::MAX_TRAVERSAL_PATHS_PER_CALL", 2)
        calls = 0
        allow(grpc_client).to receive(grpc_method) do |traversal_paths:, **|
          calls += 1
          if calls == 2
            raise Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
              'boom', grpc_code: GRPC::Core::StatusCodes::UNAVAILABLE
            )
          end

          grpc_response(grpc_method, traversal_paths)
        end

        post_graphql(query, current_user: current_user)

        expect(graphql_errors.pluck('message')).to eq(['Orbit request failed'])
        expect(results.compact.size).to eq(2)
        expect(grpc_client).to have_received(grpc_method).twice
      end

      context "when the gRPC call fails and one group is out of the user's Orbit scope" do
        let(:out_of_scope_paths) { [other_group.traversal_path(with_organization: true)] }

        before do
          allow(grpc_client).to receive(grpc_method).and_raise(
            Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
              'boom', grpc_code: GRPC::Core::StatusCodes::UNAVAILABLE
            )
          )
        end

        it 'returns the error only on the fields of the paths in scope' do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors.pluck('path'))
            .to contain_exactly(['group', 'orbit', field], ['project', 'orbit', field])
          expect(graphql_data_at(:other_group, :orbit, field)).to be_nil
        end
      end
    end

    context 'with indexingStatus' do
      let(:fields) { 'indexingStatus { phase }' }
      let(:field) { 'indexingStatus' }

      it_behaves_like 'a batched Orbit status field', :get_indexing_status, :orbit_indexing_status

      it 'checks Orbit access once for all groups and projects', :request_store do
        expect(Analytics::KnowledgeGraph::OrbitLicense).to receive(:status_available_for?).once.and_call_original

        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(results).to all(be_present)
      end

      it 'does not run more SQL queries for more groups on the orbit.groups path' do
        fields = 'nodes { orbit { enabled enabledAt indexing { state } } ' \
          'userPermissions { updateKnowledgeGraphSetting } }'
        orbit_groups_query = graphql_query_for(:orbit, {}, query_graphql_field(:groups, {}, fields))

        control = ActiveRecord::QueryRecorder.new { post_graphql(orbit_groups_query, current_user: current_user) }

        create_list(:group, 2, :private, reporters: current_user)

        expect { post_graphql(orbit_groups_query, current_user: current_user) }.not_to exceed_query_limit(control)
        expect(graphql_data_at(:orbit, :groups, :nodes).size).to eq(4)
      end

      it 'does not run more SQL queries for more groups' do
        groups_query = graphql_query_for(:groups, {}, 'nodes { orbit { indexingStatus { phase } } }')

        control = ActiveRecord::QueryRecorder.new { post_graphql(groups_query, current_user: current_user) }

        create_list(:group, 2, :private, reporters: current_user)

        expect { post_graphql(groups_query, current_user: current_user) }.not_to exceed_query_limit(control)
        expect(graphql_data_at(:groups, :nodes).size).to eq(4)
      end
    end

    context 'with itemCounts' do
      let(:fields) { 'itemCounts { domains { name } }' }
      let(:field) { 'itemCounts' }

      it_behaves_like 'a batched Orbit status field', :get_item_counts, :orbit_item_counts

      it 'returns null, not zero counts, for a path that Orbit does not return' do
        missing_path = other_group.traversal_path(with_organization: true)
        allow(grpc_client).to receive(:get_item_counts) do |traversal_paths:, **|
          { namespaces: (traversal_paths - [missing_path]).map { |path| item_counts(path) } }
        end

        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:other_group, :orbit, :item_counts)).to be_nil
        expect(graphql_data_at(:group, :orbit, :item_counts)).to be_present
      end

      it 'keeps itemCounts and indexingStatus in separate gRPC calls' do
        post_graphql(query_for(group, "#{item_counts_fields} #{status_fields}"), current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(grpc_client).to have_received(:get_item_counts).once
        expect(grpc_client).to have_received(:get_indexing_status).once
      end
    end
  end

  describe 'itemCounts for many groups' do
    let_it_be(:member_groups) do
      create_list(:group, 49, :private, reporters: user) # rubocop:disable FactoryBot/ExcessiveCreateList -- one gRPC call for 50 groups is the behavior under test
    end

    let(:groups_query) do
      graphql_query_for(:groups, { first: group_count }, 'nodes { orbit { itemCounts { domains { name } } } }')
    end

    where(group_count: [1, 6, 50])

    with_them do
      it 'sends one gRPC call and checks the rate limit once' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original

        post_graphql(groups_query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:groups, :nodes, :orbit, :item_counts)).to all(be_present)
        expect(graphql_data_at(:groups, :nodes).size).to eq(group_count)
        expect(grpc_client).to have_received(:get_item_counts).once
          .with(hash_including(traversal_paths: an_object_having_attributes(size: group_count)))
        expect(Gitlab::ApplicationRateLimiter).to have_received(:throttled?).with(:orbit_item_counts, anything).once
      end
    end

    describe 'SQL queries' do
      let_it_be(:enabled_groups) { member_groups.first(6) }
      let_it_be(:projects) { enabled_groups.map { |member_group| create(:project, :private, group: member_group) } }

      before_all do
        enabled_groups.each { |member_group| create(:knowledge_graph_enabled_namespace, namespace: member_group) }
      end

      before do
        allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_call_original
      end

      def item_counts_query(root, count, orbit_fields = 'itemCounts { domains { name } }')
        nodes = query_graphql_field(:nodes, {}, "orbit { #{orbit_fields} }")
        return graphql_query_for(:projects, { first: count, membership: true }, nodes) if root == :projects

        graphql_query_for(:orbit, {}, query_graphql_field(:member_groups, { enabled: true, first: count }, nodes))
      end

      def record_queries(query)
        post_graphql(query, current_user: current_user)

        ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      end

      it 'runs the same number of SQL queries for itemCounts on 2 and 6 groups' do
        control = record_queries(item_counts_query(:groups, 2))

        expect { post_graphql(item_counts_query(:groups, 6), current_user: current_user) }
          .not_to exceed_query_limit(control)
        expect(graphql_data_at(:orbit, :member_groups, :nodes, :orbit, :item_counts).compact.size).to eq(6)
      end

      it 'runs no SQL query for each project for itemCounts' do
        added_queries = ->(orbit_fields) do
          record_queries(item_counts_query(:projects, 6, orbit_fields)).count -
            record_queries(item_counts_query(:projects, 2, orbit_fields)).count
        end

        expect(added_queries.call('itemCounts { domains { name } }')).to eq(added_queries.call('__typename'))
      end
    end
  end

  it 'sends an empty request context when the query has no HTTP request' do
    GitlabSchema.execute(query_for(group, item_counts_fields), context: { current_user: current_user })

    expect(grpc_client).to have_received(:get_item_counts).with(
      hash_including(request_context: Analytics::KnowledgeGraph::RequestContext.new)
    )
  end

  it 'limits itemCounts to the paths of one gRPC call' do
    expect(Resolvers::Analytics::Orbit::ItemCountsResolver.extensions)
      .to include(Gitlab::Graphql::Limit::FieldCallCount => { limit: 100 })
  end

  describe 'OAuth token scopes' do
    let_it_be(:owner) { create(:user, owner_of: group) }
    let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: group) }

    let(:status_fields) do
      'indexing { state areas { name state } projects { indexed totalKnown gaps } lastCompletedAt } ' \
        'itemCounts { domains { name entities { name count } } areas { name itemTypes { name count } } }'
    end

    let(:cli_query) do
      <<~GRAPHQL
        query($fullPath: ID!) {
          group(fullPath: $fullPath) { orbit { #{status_fields} } }
          project(fullPath: $fullPath) { orbit { #{status_fields} } }
        }
      GRAPHQL
    end

    def post_with_scopes(query, *scopes, variables: nil)
      token = create(:oauth_access_token, user: owner, scopes: scopes)

      post_graphql(query, variables: variables, token: { oauth_access_token: token })
    end

    def expect_no_nulls(value)
      case value
      when Hash then value.each_value { |item| expect_no_nulls(item) }
      when Array then value.each { |item| expect_no_nulls(item) }
      else expect(value).not_to be_nil
      end
    end

    [:group, :project].each do |root|
      it "returns the status fields of the CLI query to an ai_workflows token for a #{root}" do
        target = root == :group ? group : project

        post_with_scopes(cli_query, :ai_workflows, :mcp, variables: { fullPath: target.full_path })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(root, :orbit)).to be_present
        expect_no_nulls(graphql_data_at(root, :orbit))
      end
    end

    it 'returns no other Orbit field to an ai_workflows token' do
      closed_fields = 'enabled enabledAt access { state } trial { state } indexingStatus { phase }'

      post_with_scopes(query_for(group, closed_fields), :ai_workflows, :mcp)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :orbit).values).to all(be_nil)
    end

    it 'returns the other Orbit fields to a read_api token' do
      post_with_scopes(query_for(group, 'enabled enabledAt access { state } indexingStatus { phase }'), :read_api)

      expect(graphql_data_at(:group, :orbit).values).to all(be_present)
    end

    it 'returns no group to a composite identity token when the service account cannot read the group' do
      service_account = create(:user, :service_account, composite_identity_enforced: true)
      token = create(:oauth_access_token, user: service_account, scopes: [:ai_workflows, :mcp, "user:#{owner.id}"])

      post_graphql(cli_query, variables: { fullPath: group.full_path }, token: { oauth_access_token: token })
      expect(graphql_data_at(:group)).to be_nil

      group.add_reporter(service_account)
      post_graphql(cli_query, variables: { fullPath: group.full_path }, token: { oauth_access_token: token })
      expect(graphql_data_at(:group, :orbit, :indexing)).to be_present
    end

    it 'returns no status to an ai_workflows token of a user who is not a member of a public group' do
      public_group = create(:group, :public)
      create(:knowledge_graph_enabled_namespace, namespace: public_group)
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_call_original

      post_with_scopes(cli_query, :ai_workflows, :mcp, variables: { fullPath: public_group.full_path })

      expect(graphql_data_at(:group)).to be_present
      expect(graphql_data_at(:group, :orbit, :indexing)).to be_nil
      expect(graphql_data_at(:group, :orbit, :item_counts)).to be_nil
      expect(grpc_client).not_to have_received(:get_item_counts)
    end

    it 'rejects a token without a GraphQL scope' do
      post_with_scopes(query_for(group, status_fields), :read_user)

      expect(graphql_errors).to contain_exactly(include('message' => 'Invalid token'))
    end
  end

  describe 'granular token authorization' do
    let_it_be(:public_group) { create(:group, :public) }
    let_it_be(:public_project) { create(:project, :public, group: public_group) }

    let(:boundary_object) { :user }
    let(:orbit_fields) { "#{status_fields} #{item_counts_fields}" }

    def post_with_pat(target)
      post_graphql(query_for(target, orbit_fields), token: { personal_access_token: pat })
    end

    context 'with Group.orbit' do
      it_behaves_like 'authorizing granular token permissions for GraphQL', :read_orbit do
        let(:request) { post_with_pat(public_group) }
      end
    end

    context 'with Project.orbit' do
      it_behaves_like 'authorizing granular token permissions for GraphQL', :read_orbit do
        let(:request) { post_with_pat(public_project) }
      end
    end

    context 'when the token does not have read_orbit' do
      let(:pat) { create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(public_group)) }

      it 'returns the group but not the Orbit data' do
        post_with_pat(public_group)

        expect(graphql_data_at(:group)).to be_present
        expect(graphql_data_at(:group, :orbit)).to be_nil
      end
    end
  end
end
