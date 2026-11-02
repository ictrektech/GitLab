# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Orbit admin settings groups query', :enable_admin_mode, :clean_gitlab_redis_rate_limiting,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:indexed_group) { create(:group, :private) }
  let_it_be(:available_group) { create(:group, :private) }
  let_it_be(:subgroup) { create(:group, :private, parent: available_group) }
  let_it_be(:pending_deletion_group) { create(:group_with_deletion_schedule, :private) }
  let_it_be(:archived_indexed_group) { create(:group, :private, :archived) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:query) do
    get_graphql_query_as_string('orbit/settings/admin/graphql/admin_groups.query.graphql', ee: true)
  end

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: indexed_group)
    create(:knowledge_graph_enabled_namespace, namespace: archived_indexed_group)
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

  def groups_for(variables)
    post_graphql(query, current_user: admin, variables: variables)

    expect_graphql_errors_to_be_empty
    graphql_data_at(:orbit, :groups, :nodes).index_by { |group| group['fullPath'] }
  end

  it 'returns indexed top-level groups that the admin is not a member of', :aggregate_failures do
    groups = groups_for(enabled: true)

    expect(groups.keys).to include(indexed_group.full_path, archived_indexed_group.full_path)
    expect(groups.keys).not_to include(available_group.full_path, subgroup.full_path)
    expect(groups[indexed_group.full_path]['orbit']).to include(
      'enabledAt' => indexed_group.knowledge_graph_enabled_namespace.created_at.iso8601,
      'indexing' => hash_including('state' => 'INDEXING')
    )
  end

  it 'returns all top-level groups that the admin is not a member of', :aggregate_failures do
    groups = groups_for({})

    expect(groups.keys).to include(indexed_group.full_path, available_group.full_path)
    expect(groups.keys).not_to include(subgroup.full_path, pending_deletion_group.full_path)
    expect(groups[available_group.full_path]['orbit']).to include('enabled' => false, 'enabledAt' => nil)
  end
end
