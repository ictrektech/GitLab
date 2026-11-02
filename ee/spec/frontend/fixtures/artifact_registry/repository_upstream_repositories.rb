# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository upstream repositories (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  graphql_path = 'packages_and_registries/artifact_registry/graphql'
  query_path = "#{graphql_path}/queries/get_repository_upstream_repositories.query.graphql"

  let_it_be_with_refind(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, organization: organization).user }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:list_url) { "#{repository_url}/#{format}/upstream_repositories" }

  let(:query) { get_graphql_query_as_string(query_path, ee: true) }
  let(:variables) { { organizationId: organization.to_global_id.to_s, name: name } }
  let(:permissions) { ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with { true } }
  let(:denied_permissions) { ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with { false } }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => format,
      'kind' => 'virtual',
      'visibility' => 'private',
      'description' => "A virtual #{format} repository",
      'artifacts_count' => 0,
      'downloads_count' => 0,
      'size_bytes' => 0,
      'created_at' => '2026-05-12T09:24:00Z',
      'last_updated_at' => '2026-06-01T00:00:00Z',
      'settings' => {}
    }
  end

  include_context 'with a resolved Artifact Registry handle'
  include_context 'with Artifact Registry fixture setup'

  before do
    stub_request(:get, repository_url)
      .to_return(status: 200, headers: json_headers, body: repository_body.to_json)

    stub_request(:get, list_url)
      .with(query: { include_permissions: 'true' })
      .to_return(status: 200, headers: json_headers, body: list_body.to_json)
  end

  describe GraphQL::Query, 'the upstream-list read of a package family repository', type: :request do
    let(:name) { 'maven-virtual' }
    let(:format) { 'maven' }

    let(:list_body) do
      [
        { 'id' => 'a1000000-0000-4000-8000-000000000001', 'position' => 1,
          'upstream_repository' => { 'id' => 'd1000000-0000-4000-8000-000000000001',
                                     'name' => 'maven-central-proxy', 'format' => 'maven',
                                     'kind' => 'remote', 'visibility' => 'private',
                                     'size_bytes' => 1_536_000,
                                     'settings' => { 'url' => 'https://repo.maven.apache.org/maven2',
                                                     'last_health_status' => 'healthy' },
                                     'permissions' => permissions } },
        { 'id' => 'a1000000-0000-4000-8000-000000000002', 'position' => 2,
          'upstream_repository' => { 'id' => 'd1000000-0000-4000-8000-000000000002',
                                     'name' => 'payments-releases', 'format' => 'maven',
                                     'kind' => 'hosted', 'visibility' => 'private',
                                     'size_bytes' => 0,
                                     'permissions' => permissions } },
        { 'id' => 'a1000000-0000-4000-8000-000000000003', 'position' => 3,
          'upstream_repository' => { 'id' => 'd1000000-0000-4000-8000-000000000003',
                                     'name' => 'vendor-mirror', 'format' => 'maven',
                                     'kind' => 'remote',
                                     'permissions' => denied_permissions } }
      ]
    end

    it "ee/graphql/#{query_path}.json", :aggregate_failures do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'maven-virtual',
        'kind' => 'VIRTUAL',
        'upstreamRepositories' => [
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'a1000000-0000-4000-8000-000000000001',
            'position' => 1,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'd1000000-0000-4000-8000-000000000001',
              'name' => 'maven-central-proxy',
              'kind' => 'REMOTE',
              'userPermissions' => {
                '__typename' => 'ArtifactRegistryRepositoryPermissions',
                'updateRepository' => true,
                'deleteArtifact' => true
              },
              'sizeBytes' => '1536000',
              'settings' => {
                '__typename' => 'ArtifactRegistryUpstreamRepositorySummarySettings',
                'url' => 'https://repo.maven.apache.org/maven2',
                'lastHealthStatus' => 'HEALTHY'
              }
            }
          },
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'a1000000-0000-4000-8000-000000000002',
            'position' => 2,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'd1000000-0000-4000-8000-000000000002',
              'name' => 'payments-releases',
              'kind' => 'HOSTED',
              'userPermissions' => {
                '__typename' => 'ArtifactRegistryRepositoryPermissions',
                'updateRepository' => true,
                'deleteArtifact' => true
              },
              'sizeBytes' => '0',
              'settings' => nil
            }
          },
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'a1000000-0000-4000-8000-000000000003',
            'position' => 3,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'd1000000-0000-4000-8000-000000000003',
              'name' => 'vendor-mirror',
              'kind' => 'REMOTE',
              'userPermissions' => {
                '__typename' => 'ArtifactRegistryRepositoryPermissions',
                'updateRepository' => false,
                'deleteArtifact' => false
              },
              'sizeBytes' => nil,
              'settings' => nil
            }
          }
        ]
      )
    end
  end

  describe GraphQL::Query, 'the upstream-list read of a container family repository', type: :request do
    fixture_path = "#{graphql_path}/queries/get_repository_upstream_repositories.container.query.graphql"

    let(:name) { 'docker-virtual' }
    let(:format) { 'docker' }

    let(:list_body) do
      [
        { 'id' => 'b1000000-0000-4000-8000-000000000001', 'position' => 1,
          'upstream_repository' => { 'id' => 'e1000000-0000-4000-8000-000000000001',
                                     'name' => 'docker-hub-proxy', 'format' => 'docker',
                                     'kind' => 'remote', 'visibility' => 'private',
                                     'size_bytes' => 52_428_800,
                                     'settings' => { 'url' => 'https://registry-1.docker.io',
                                                     'last_health_status' => 'unhealthy' },
                                     'permissions' => permissions } },
        { 'id' => 'b1000000-0000-4000-8000-000000000002', 'position' => 2,
          'upstream_repository' => { 'id' => 'e1000000-0000-4000-8000-000000000002',
                                     'name' => 'base-images', 'format' => 'oci',
                                     'kind' => 'hosted', 'visibility' => 'private',
                                     'size_bytes' => 2048,
                                     'permissions' => permissions } }
      ]
    end

    it "ee/graphql/#{fixture_path}.json", :aggregate_failures do
      post_graphql(query, current_user: user, variables: variables)

      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization, :artifact_registry_repository)).to eq(
        '__typename' => 'ArtifactRegistryRepositoryDetails',
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'docker-virtual',
        'kind' => 'VIRTUAL',
        'upstreamRepositories' => [
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'b1000000-0000-4000-8000-000000000001',
            'position' => 1,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'e1000000-0000-4000-8000-000000000001',
              'name' => 'docker-hub-proxy',
              'kind' => 'REMOTE',
              'userPermissions' => {
                '__typename' => 'ArtifactRegistryRepositoryPermissions',
                'updateRepository' => true,
                'deleteArtifact' => true
              },
              'sizeBytes' => '52428800',
              'settings' => {
                '__typename' => 'ArtifactRegistryUpstreamRepositorySummarySettings',
                'url' => 'https://registry-1.docker.io',
                'lastHealthStatus' => 'UNHEALTHY'
              }
            }
          },
          {
            '__typename' => 'ArtifactRegistryUpstreamRepositoryAssociation',
            'id' => 'b1000000-0000-4000-8000-000000000002',
            'position' => 2,
            'upstreamRepository' => {
              '__typename' => 'ArtifactRegistryUpstreamRepositorySummary',
              'id' => 'e1000000-0000-4000-8000-000000000002',
              'name' => 'base-images',
              'kind' => 'HOSTED',
              'userPermissions' => {
                '__typename' => 'ArtifactRegistryRepositoryPermissions',
                'updateRepository' => true,
                'deleteArtifact' => true
              },
              'sizeBytes' => '2048',
              'settings' => nil
            }
          }
        ]
      )
    end
  end
end
