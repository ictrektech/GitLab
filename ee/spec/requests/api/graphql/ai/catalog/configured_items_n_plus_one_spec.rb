# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'aiCatalogConfiguredItems N+1', feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }
  let_it_be(:project) { create(:project, :public, group: group, developers: user) }
  let_it_be(:items_group) { create(:group, :public) }

  let(:fields) do
    <<~FIELDS
      id
      item {
        id
        project { id nameWithNamespace }
        latestVersion(released: true) { id humanVersionName }
      }
      pinnedItemVersion { id humanVersionName }
    FIELDS
  end

  let(:query) do
    "{ #{query_nodes('aiCatalogConfiguredItems', fields, args: { projectId: project.to_global_id })} }"
  end

  before do
    enable_ai_catalog
  end

  # Public items in separate projects, so the item fields resolve for every row.
  # Pinned prefixes are left out: each one is a per-row lookup, capped at 20.
  def create_consumer
    item = create(:ai_catalog_agent, :public, :with_released_version,
      project: create(:project, :public, group: items_group))
    create(:ai_catalog_item_consumer, project: project, item: item)
  end

  it 'does not grow the query count with the page size' do
    create_consumer

    # Warm up, then record the baseline for a page with one consumer. Each
    # request uses a fresh user so request-scoped caches (policy cache,
    # allowed_to_use memoization) do not hide per-row queries.
    post_graphql(query, current_user: user)
    control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
      post_graphql(query, current_user: create(:user, developer_of: project))
    end

    3.times { create_consumer }

    expect do
      post_graphql(query, current_user: create(:user, developer_of: project))
    end.not_to exceed_all_query_limit(control)

    # A request that errors runs few queries, so a flat count alone proves nothing.
    expect_graphql_errors_to_be_empty
    nodes = graphql_data_at(:ai_catalog_configured_items, :nodes)
    expect(nodes.size).to eq(4)
    expect(nodes).to all(include('item' => be_present, 'pinnedItemVersion' => be_present))
  end
end
