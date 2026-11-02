# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting the available deploy keys of a project', feature_category: :source_code_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }
  let_it_be(:deploy_key) { create(:deploy_keys_project, :write_access, project: project).deploy_key }

  let(:query) do
    graphql_query_for(
      :project,
      { full_path: project.full_path },
      query_nodes(:available_deploy_keys, 'id title user { username }')
    )
  end

  let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

  let(:user) { maintainer }
  let(:boundary_object) { project }

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_deploy_key]

  it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
    let(:parent_data_path) { %i[project] }
    let(:field_data_path) { %i[project available_deploy_keys] }
  end

  context 'when a granular token authorizes the project and its deploy keys' do
    let(:pat) do
      create(:granular_pat, user: maintainer, boundary: ::Authz::Boundary.for(project),
        permissions: [:read_project, :read_deploy_key])
    end

    it 'returns the deploy keys with their users', :aggregate_failures do
      request

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project, :available_deploy_keys, :nodes)).to contain_exactly(
        'id' => deploy_key.to_global_id.to_s,
        'title' => deploy_key.title,
        'user' => { 'username' => deploy_key.user.username }
      )
    end
  end
end
