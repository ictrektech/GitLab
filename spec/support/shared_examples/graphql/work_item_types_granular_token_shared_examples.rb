# frozen_string_literal: true

# WorkItemType skips granular token authorization, and the parent Project/Group types
# only gate read_project/read_group, so workItemTypes carries its own read_work_item_type
# directive. A token needs both permissions to reach the work item types.
RSpec.shared_examples 'authorizing granular token permissions for work item type list' do |parent_permission|
  include GraphqlHelpers

  let(:parent_key) { parent.to_ability_name.to_sym }
  let(:query) do
    graphql_query_for(
      parent_key.to_s,
      { 'fullPath' => parent.full_path },
      query_nodes('WorkItemTypes', 'id name')
    )
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', [parent_permission, :read_work_item_type] do
    let(:boundary_object) { parent }
    let(:request) { post_graphql(query, current_user: user, token: { personal_access_token: pat }) }
  end

  context 'when the token authorizes the parent and work items' do
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(parent),
        permissions: [parent_permission, :read_work_item])
    end

    it 'returns the work item types' do
      post_graphql(query, current_user: user, token: { personal_access_token: pat })

      expect(graphql_data_at(parent_key, :work_item_types, :nodes)).not_to be_empty
    end
  end

  context 'when the token authorizes only the parent' do
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(parent), permissions: [parent_permission])
    end

    it 'returns the parent but not its work item types', :aggregate_failures do
      post_graphql(query, current_user: user, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(parent_key)).to be_present
      expect(graphql_data_at(parent_key, :work_item_types)).to be_nil
    end
  end
end
