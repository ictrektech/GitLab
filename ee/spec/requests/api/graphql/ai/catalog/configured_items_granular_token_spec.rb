# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting consumed AI catalog items with a granular token', feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:agent) do
    create(:ai_catalog_agent, project: project, versions: [build(:ai_catalog_agent_version, :released, item: nil)])
  end

  let_it_be(:project_consumer) { create(:ai_catalog_item_consumer, project: project, item: agent) }
  let_it_be(:group_consumer) { create(:ai_catalog_item_consumer, group: group, item: agent) }

  let(:fields) { 'id enabled' }
  let(:query) { "{ #{query_nodes('aiCatalogConfiguredItems', fields, args: args)} }" }
  let(:nodes) { graphql_data_at(:ai_catalog_configured_items, :nodes) }
  let(:request) { post_graphql(query, current_user: user, token: { personal_access_token: pat }) }

  before do
    enable_ai_catalog
  end

  context 'when querying by project' do
    let(:args) { { projectId: project.to_global_id } }

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_ai_catalog_item_consumer do
      let(:boundary_object) { project }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_ai_catalog_item_consumer do
      let(:boundary_object) { project }
      let(:skipped_data_path) { [:ai_catalog_configured_items, :nodes, 0, :id] }
    end

    context 'when selecting user permissions' do
      let(:fields) { 'id userPermissions { executeAiCatalogItem }' }

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        :read_ai_catalog_item_consumer do
        let(:boundary_object) { project }
        let(:skipped_data_path) do
          [:ai_catalog_configured_items, :nodes, 0, :user_permissions, :execute_ai_catalog_item]
        end
      end
    end

    context 'when selecting an item owned by another project' do
      let_it_be(:item_project) { create(:project, group: group) }
      let_it_be(:other_project_item) { create(:ai_catalog_agent, :restricted, project: item_project) }
      let_it_be(:consumer_project) { create(:project, group: group) }
      let_it_be(:consumer) { create(:ai_catalog_item_consumer, project: consumer_project, item: other_project_item) }

      let(:args) { { projectId: consumer_project.to_global_id } }
      let(:fields) { 'id item { id name }' }
      let(:additional_scopes) { [] }
      let(:pat) do
        create(:granular_pat,
          user: user,
          boundary: ::Authz::Boundary.for(consumer_project),
          permissions: [:read_ai_catalog_item_consumer],
          additional_scopes: additional_scopes
        )
      end

      context 'when the token grants item access at the user boundary' do
        let(:additional_scopes) do
          [{ boundary: ::Authz::Boundary.for(:user), permissions: [:read_ai_catalog_item] }]
        end

        it 'returns the consumer with its item' do
          request

          expect(graphql_errors).to be_nil
          expect(nodes).to contain_exactly(
            a_graphql_entity_for(consumer, item: a_graphql_entity_for(other_project_item, :name))
          )
        end
      end

      context 'when the token does not grant item access at the user boundary' do
        it 'returns the consumer without its item' do
          request

          expect(nodes).to contain_exactly(a_graphql_entity_for(consumer, item: nil))
        end
      end
    end
  end

  context 'when querying by group' do
    let(:args) { { groupId: group.to_global_id } }

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_ai_catalog_item_consumer do
      let(:boundary_object) { group }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_ai_catalog_item_consumer do
      let(:boundary_object) { group }
      let(:skipped_data_path) { [:ai_catalog_configured_items, :nodes, 0, :id] }
    end
  end
end
