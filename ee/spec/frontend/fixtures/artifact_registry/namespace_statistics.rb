# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry namespace statistics (JavaScript fixtures)', feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  describe GraphQL::Query, type: :request do
    query_path = 'packages_and_registries/artifact_registry/graphql/queries/get_namespace_statistics.query.graphql'

    let_it_be(:user) { create(:user) }
    let_it_be(:organization) { user.organization }

    let(:base_url) { 'https://artifact-registry.example.test' }
    let(:slug) { 'resolved-handle' }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }
    let(:query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:variables) { { organizationId: organization.to_global_id.to_s } }

    # A count past a thousand, so a rendering that forgets to format the figure is visible.
    let(:statistics_body) do
      {
        'repositories_count' => 1234,
        'deduplicated_size_bytes' => 987_654,
        'components_count' => 3,
        'downloads_count' => 0
      }
    end

    include_context 'with a resolved Artifact Registry handle'
    include_context 'with Artifact Registry fixture setup'

    before do
      stub_request(:get, "#{base_url}/api/v1/#{slug}/statistics")
        .to_return(status: 200, headers: json_headers, body: statistics_body.to_json)
    end

    it "ee/graphql/#{query_path}.json" do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry)).to eq(
        '__typename' => 'ArtifactRegistry',
        'id' => namespace_mapping.ar_namespace_id,
        'statistics' => {
          '__typename' => 'ArtifactRegistryNamespaceStatistics',
          'repositoriesCount' => '1234',
          'deduplicatedSizeBytes' => '987654'
        }
      )
    end
  end
end
