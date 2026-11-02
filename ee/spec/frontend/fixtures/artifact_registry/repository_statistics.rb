# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository statistics (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  graphql_path = 'packages_and_registries/artifact_registry/graphql'
  query_path = "#{graphql_path}/queries/get_repository_statistics.query.graphql"

  let_it_be_with_refind(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, organization: organization).user }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:statistics_url) { "#{repository_url}/statistics" }

  let(:query) { get_graphql_query_as_string(query_path, ee: true) }
  let(:variables) { { organizationId: organization.to_global_id.to_s, name: name } }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'settings' => {}
    }
  end

  include_context 'with a resolved Artifact Registry handle'
  include_context 'with Artifact Registry fixture setup'

  before do
    stub_request(:get, repository_url)
      .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

    stub_request(:get, statistics_url)
      .to_return(status: 200, headers: json_headers, body: statistics_body.to_json)
  end

  describe GraphQL::Query, 'the statistics read of a hosted package family repository', type: :request do
    let(:name) { 'my-repository' }
    let(:format) { 'maven' }

    let(:statistics_body) do
      {
        'artifacts_count' => 3, 'size_bytes' => 2048, 'downloads_count' => 1234,
        'packages_count' => 1, 'versions_count' => 3, 'files_count' => 9
      }
    end

    it "ee/graphql/#{query_path}.json", :aggregate_failures do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'my-repository',
        'statistics' => {
          '__typename' => 'ArtifactRegistryRepositoryStatistics',
          'packagesCount' => '1',
          'imagesCount' => nil
        }
      )
    end
  end

  describe GraphQL::Query, 'the statistics read of a hosted container family repository', type: :request do
    fixture_path = "#{graphql_path}/queries/get_repository_statistics.container.query.graphql"

    let(:name) { 'docker-hosted' }
    let(:format) { 'docker' }

    let(:statistics_body) do
      {
        'artifacts_count' => 5, 'size_bytes' => 8192, 'downloads_count' => 0,
        'images_count' => 2, 'tags_count' => 4, 'manifests_count' => 5
      }
    end

    it "ee/graphql/#{fixture_path}.json", :aggregate_failures do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'docker-hosted',
        'statistics' => {
          '__typename' => 'ArtifactRegistryRepositoryStatistics',
          'packagesCount' => nil,
          'imagesCount' => '2'
        }
      )
    end
  end
end
