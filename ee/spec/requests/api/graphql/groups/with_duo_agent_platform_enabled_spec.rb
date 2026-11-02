# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying groups with withDuoAgentPlatformEnabled', :saas_gitlab_com_subscriptions,
  feature_category: :value_stream_management do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  # Disabled groups sort between enabled ones, so a filter applied after paging would leave short pages.
  let_it_be(:enabled_groups) { %w[a-enabled c-enabled e-enabled].map { |name| create(:group, :private, name: name) } }
  let_it_be(:disabled_groups) { %w[b-disabled d-disabled].map { |name| create(:group, :private, name: name) } }

  let(:filters) { { allAvailable: false, topLevelOnly: true, withDuoAgentPlatformEnabled: true, first: 2 } }

  let(:fields) do
    <<~FIELDS
      nodes { name }
      pageInfo { hasNextPage endCursor }
    FIELDS
  end

  let(:query) { graphql_query_for(:groups, filters, fields) }

  before_all do
    disabled_groups.each do |group|
      create(:namespace_ai_settings, namespace: group, duo_agent_platform_enabled: false)
    end

    (enabled_groups + disabled_groups).each { |group| group.add_developer(user) }
  end

  it 'paginates over enabled groups only' do
    post_graphql(query, current_user: user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:groups, :nodes, :name)).to eq(%w[a-enabled c-enabled])
    expect(graphql_data_at(:groups, :page_info, :has_next_page)).to be(true)

    end_cursor = graphql_data_at(:groups, :page_info, :end_cursor)
    post_graphql(graphql_query_for(:groups, filters.merge(after: end_cursor), fields), current_user: user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:groups, :nodes, :name)).to eq(%w[e-enabled])
    expect(graphql_data_at(:groups, :page_info, :has_next_page)).to be(false)
  end

  context 'without withDuoAgentPlatformEnabled' do
    let(:filters) { { allAvailable: false, topLevelOnly: true } }

    it 'returns all member groups' do
      post_graphql(query, current_user: user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:groups, :nodes, :name))
        .to eq(%w[a-enabled b-disabled c-enabled d-disabled e-enabled])
    end
  end
end
