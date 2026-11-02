# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AiCatalogItem.hasDirectProjectConfigurationsInGroup', :with_current_organization,
  feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:group) { create(:group, maintainers: maintainer, developers: developer) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:item) { create(:ai_catalog_flow, :public) }

  let(:current_user) { maintainer }
  let(:group_gid) { group.to_global_id }
  let(:value) { graphql_data_at(:ai_catalog_item, :has_direct_project_configurations_in_group) }

  let(:query) do
    <<~GRAPHQL
      {
        aiCatalogItem(id: "#{item.to_global_id}") {
          hasDirectProjectConfigurationsInGroup(groupId: "#{group_gid}")
        }
      }
    GRAPHQL
  end

  subject(:execute_query) { post_graphql(query, current_user: current_user) }

  before do
    enable_ai_catalog
  end

  context 'when a project in the group has a configuration of the item' do
    before_all do
      create(:ai_catalog_item_consumer, :child_item_consumer, item: item, project: project)
    end

    it 'returns true' do
      execute_query

      expect_graphql_errors_to_be_empty
      expect(value).to be(true)
    end

    context 'when user is a developer of the group' do
      let(:current_user) { developer }

      it 'returns null' do
        execute_query

        expect(value).to be_nil
      end
    end

    context 'when user is not a member of the group' do
      let(:current_user) { create(:user) }

      it 'returns null' do
        execute_query

        expect(value).to be_nil
      end
    end
  end

  context 'when no project in the group has a configuration of the item' do
    it 'returns false' do
      execute_query

      expect_graphql_errors_to_be_empty
      expect(value).to be(false)
    end
  end

  context 'when the group is not a top-level group' do
    let_it_be(:subgroup) { create(:group, parent: group) }

    let(:group_gid) { subgroup.to_global_id }

    it 'returns null' do
      execute_query

      expect_graphql_errors_to_be_empty
      expect(value).to be_nil
    end
  end

  context 'when the group does not exist' do
    let(:group_gid) { "gid://gitlab/Group/#{non_existing_record_id}" }

    it 'returns null' do
      execute_query

      expect(value).to be_nil
    end
  end

  context 'when the field is requested for more than one item' do
    let_it_be(:other_item) { create(:ai_catalog_flow, :public) }

    let(:query) do
      <<~GRAPHQL
        {
          first: aiCatalogItem(id: "#{item.to_global_id}") {
            hasDirectProjectConfigurationsInGroup(groupId: "#{group_gid}")
          }
          second: aiCatalogItem(id: "#{other_item.to_global_id}") {
            hasDirectProjectConfigurationsInGroup(groupId: "#{group_gid}")
          }
        }
      GRAPHQL
    end

    it 'returns an error' do
      execute_query

      expect_graphql_errors_to_include(
        '"hasDirectProjectConfigurationsInGroup" field can be requested only for 1 AiCatalogItem(s) at a time.'
      )
    end
  end
end
