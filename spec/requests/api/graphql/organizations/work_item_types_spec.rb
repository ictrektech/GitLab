# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization.workItemTypes', :with_current_organization, feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user, organizations: [current_organization]) }
  let_it_be(:all_system_defined_types) { ::WorkItems::TypesFramework::Provider.new(current_organization).available_types }
  let_it_be(:all_system_defined_type_names) { all_system_defined_types.map(&:name) }

  let(:query_param) { { 'id' => current_organization.to_gid } }
  let(:query) do
    graphql_query_for('organization', query_param,
      'workItemTypes { nodes { id name widgetDefinitions { type } } }')
  end

  it 'returns work item types for the organization' do
    post_graphql(query, current_user: current_user)
    expect(graphql_data_at('organization', 'workItemTypes', 'nodes')).not_to be_empty
  end

  it 'returns system-defined work item types' do
    post_graphql(query, current_user: current_user)

    returned_types = graphql_data_at('organization', 'workItemTypes', 'nodes')
    type_names = returned_types.pluck('name')

    expect(type_names).to all(be_in(all_system_defined_type_names))

    expect(returned_types.size).to eq(all_system_defined_types.count)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_organization do
    let(:user) { current_user }
    let(:boundary_object) { :instance }
    let(:additional_scope_requirements) { [{ boundary_object: :user, permissions: [:read_work_item] }] }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end

  context 'when the token authorizes the organization and user-level work items' do
    let(:pat) do
      create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(:instance),
        permissions: [:read_organization],
        additional_scopes: [{ boundary: ::Authz::Boundary.for(:user), permissions: [:read_work_item] }])
    end

    it 'returns the work item types' do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_data_at(:organization, :work_item_types, :nodes)).not_to be_empty
    end
  end

  context 'when the token authorizes only the organization' do
    let(:pat) do
      create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(:instance),
        permissions: [:read_organization])
    end

    it 'returns the organization but not its work item types', :aggregate_failures do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:organization)).to be_present
      expect(graphql_data_at(:organization, :work_item_types)).to be_nil
    end
  end

  context 'when organization id is not set' do
    let(:query_param) { {} }

    it 'returns work item types for the organization' do
      post_graphql(query, current_user: current_user)
      expect(graphql_data_at('organization', 'workItemTypes', 'nodes')).not_to be_empty
    end
  end
end
