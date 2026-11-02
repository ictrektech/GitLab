# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CI/CD Catalog Integration (GraphQL fixtures)', type: :request,
  feature_category: :pipeline_composition do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:namespace, freeze: false) { create(:group, developers: user) }
  let_it_be(:project, freeze: false) do
    create(:project, :public, :custom_repo, namespace: namespace, files: { 'README.md' => 'Readme for 1.0.0' })
  end

  let_it_be(:resource, freeze: false) { create(:ci_catalog_resource, :published, project: project) }

  before_all do
    project.repository.create_branch('branch_v2', project.default_branch)
    project.repository.update_file(user, 'README.md', 'Readme for 2.0.0',
      message: 'Update readme', branch_name: 'branch_v2')

    project.repository.add_tag(user, '1.0.0', project.default_branch)
    project.repository.add_tag(user, '2.0.0', 'branch_v2')

    { '1.0.0' => Time.zone.parse('2026-01-01'), '2.0.0' => Time.zone.parse('2026-02-01') }.each do |tag, released_at|
      release = create(:release, project: project, tag: tag, sha: project.commit(tag).sha, released_at: released_at)
      create(:ci_catalog_resource_version, semver: tag, catalog_resource: resource, release: release)
    end
  end

  before do
    sign_in(user)
  end

  base_output_path = 'graphql/ci/catalog/integration/'

  describe GraphQL::Query do
    {
      'get_ci_catalog_resource_versions' => [
        'get_ci_catalog_resource_versions.query.graphql', {}
      ],
      'get_ci_catalog_resource_shared_data' => [
        'get_ci_catalog_resource_shared_data.query.graphql', { version: '2.0.0' }
      ],
      'get_ci_catalog_resource_shared_data_previous_version' => [
        'get_ci_catalog_resource_shared_data.query.graphql', { version: '1.0.0' }
      ],
      'get_ci_catalog_resource_readme' => [
        'get_ci_catalog_resource_readme.query.graphql', { version: '2.0.0' }
      ],
      'get_ci_catalog_resource_readme_previous_version' => [
        'get_ci_catalog_resource_readme.query.graphql', { version: '1.0.0' }
      ],
      'get_ci_catalog_resource_components' => [
        'get_ci_catalog_resource_components.query.graphql', { version: '2.0.0' }
      ]
    }.each do |fixture_name, (query_file, variables)|
      it "#{base_output_path}#{fixture_name}.query.graphql.json" do
        query = get_graphql_query_as_string("ci/catalog/graphql/queries/#{query_file}")

        post_graphql(query, current_user: user, variables: { fullPath: project.full_path, **variables })

        expect_graphql_errors_to_be_empty
      end
    end

    {
      'get_catalog_resources' => 'get_ci_catalog_resources.query.graphql',
      'get_catalog_resources_count' => 'get_ci_catalog_resources_count.query.graphql'
    }.each do |fixture_name, query_file|
      it "#{base_output_path}#{fixture_name}.query.graphql.json" do
        query = get_graphql_query_as_string("ci/catalog/graphql/queries/#{query_file}")

        post_graphql(query, current_user: user)

        expect_graphql_errors_to_be_empty
      end
    end

    it "#{base_output_path}get_catalog_resource_usage_permissions.query.graphql.json" do
      query = get_graphql_query_as_string(
        'ci/catalog/graphql/queries/get_resource_usage_permissions.query.graphql', ee: true
      )

      post_graphql(query, current_user: user, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
    end
  end
end
