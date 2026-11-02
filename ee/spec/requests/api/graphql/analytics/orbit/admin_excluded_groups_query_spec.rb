# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Orbit admin settings excluded groups query', :enable_admin_mode, :clean_gitlab_redis_rate_limiting,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:enabled_group) { create(:group, :private, :with_avatar) }
  let_it_be(:other_group) { create(:group, :private) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:query) do
    get_graphql_query_as_string('orbit/settings/admin/graphql/admin_excluded_groups.query.graphql', ee: true)
  end

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: enabled_group)
    create(:knowledge_graph_excluded_namespace, namespace: enabled_group)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })

    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:get_indexing_status) do |traversal_paths:, **|
      { statuses: traversal_paths.map { |traversal_path| { traversal_path: traversal_path, phase: 'syncing' } } }
    end
  end

  def post_query(user = admin)
    post_graphql(query, current_user: user, variables: { first: 100 })
  end

  it 'returns the excluded groups with their Orbit data', :aggregate_failures do
    post_query

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :excluded_groups, :nodes)).to contain_exactly(
      hash_including(
        'fullPath' => enabled_group.full_path,
        'webPath' => enabled_group.web_url(only_path: true),
        'orbit' => hash_including(
          'enabled' => true,
          'enabledAt' => enabled_group.knowledge_graph_enabled_namespace.created_at.iso8601,
          'indexing' => hash_including('state' => 'INDEXING')
        )
      )
    )
  end

  it 'does not run more SQL queries for more excluded groups', :aggregate_failures do
    other_admin = create(:admin)
    control = ActiveRecord::QueryRecorder.new { post_query }

    create(:knowledge_graph_enabled_namespace, namespace: other_group)
    create(:knowledge_graph_excluded_namespace, namespace: other_group)
    create(:knowledge_graph_excluded_namespace, namespace: create(:group, :private, :with_avatar))

    expect { post_query(other_admin) }.not_to exceed_query_limit(control)
    expect(graphql_data_at(:orbit, :excluded_groups, :nodes).size).to eq(3)
  end
end
