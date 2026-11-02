# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository upstream list', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-virtual' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:upstreams_url) { "#{repository_url}/#{format}/upstream_repositories" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'virtual',
      'visibility' => 'private',
      'description' => 'A virtual repository',
      'settings' => {}
    }
  end

  let(:first_upstream) do
    {
      'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
      'position' => 1,
      'upstream_repository' => {
        'id' => 'aaaa1111-0000-0000-0000-000000000000',
        'name' => "#{format}-hosted",
        'format' => format,
        'kind' => 'hosted',
        'visibility' => 'public',
        'size_bytes' => 0
      }
    }
  end

  let(:second_upstream) do
    {
      'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
      'position' => 2,
      'upstream_repository' => {
        'id' => 'bbbb2222-0000-0000-0000-000000000000',
        'name' => "#{format}-remote",
        'format' => format,
        'kind' => 'remote',
        'visibility' => 'private',
        'size_bytes' => 9_876_543_210,
        'settings' => { 'url' => 'https://registry.example.com/upstream', 'last_health_status' => 'healthy' }
      }
    }
  end

  let(:upstreams_body) { [first_upstream, second_upstream] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryRepositoryUpstreams(
        $id: OrganizationsOrganizationID!
        $name: String!
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            upstreamRepositories {
              id
              position
              upstreamRepository {
                id
                name
                format
                kind
                visibility
                sizeBytes
                settings {
                  url
                  lastHealthStatus
                }
              }
            }
          }
        }
      }
    QUERY
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end
  end

  subject(:post_query) do
    post_graphql(query, current_user: current_user,
      variables: { id: organization.to_global_id.to_s, name: repository_name })
  end

  shared_examples 'resolving the list null while the repository still renders' do
    it 'renders a null list, no error, and the repository around it', :aggregate_failures do
      stub_repository_read

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(upstreams_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'rendering the service-unavailable error beside the loaded repository' do
    it 'renders the service-unavailable error and keeps the repository rendered', :aggregate_failures do
      stub_repository_read

      post_query

      expect(upstreams_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the repository is virtual' do
    where(:format, :repository_name) do
      [
        %w[maven maven-virtual],
        %w[npm npm-virtual],
        %w[docker docker-virtual],
        %w[oci oci-virtual]
      ]
    end

    with_them do
      it 'renders each association in position order, with its upstream summary discriminated by kind',
        :aggregate_failures do
        stub_repository_read
        stub_upstreams_list

        post_query

        expect(upstreams_response).to eq(
          [
            {
              'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
              'position' => 1,
              'upstreamRepository' => {
                'id' => 'aaaa1111-0000-0000-0000-000000000000',
                'name' => "#{format}-hosted",
                'format' => format.upcase,
                'kind' => 'HOSTED',
                'visibility' => 'PUBLIC',
                'sizeBytes' => '0',
                'settings' => nil
              }
            },
            {
              'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
              'position' => 2,
              'upstreamRepository' => {
                'id' => 'bbbb2222-0000-0000-0000-000000000000',
                'name' => "#{format}-remote",
                'format' => format.upcase,
                'kind' => 'REMOTE',
                'visibility' => 'PRIVATE',
                'sizeBytes' => '9876543210',
                'settings' => {
                  'url' => 'https://registry.example.com/upstream',
                  'lastHealthStatus' => 'HEALTHY'
                }
              }
            }
          ]
        )
        expect(graphql_errors).to be_nil
      end
    end
  end

  describe 'the upstream repository user permissions block' do
    let(:query_with_permissions) do
      <<~QUERY
        query organizationArtifactRegistryRepositoryUpstreamPermissions(
          $id: OrganizationsOrganizationID!
          $name: String!
        ) {
          organization(id: $id) {
            id
            artifactRegistryRepository(name: $name) {
              name
              upstreamRepositories {
                upstreamRepository {
                  name
                  userPermissions {
                    readRepository
                    updateRepository
                    deleteRepository
                    createRepositoryUpstream
                    updateRepositoryUpstream
                    deleteRepositoryUpstream
                    readArtifact
                    createArtifact
                    deleteArtifact
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    let(:first_upstream_permissions) do
      {
        'read_repository' => true,
        'update_repository' => true,
        'delete_repository' => false,
        'create_repository_upstream' => false,
        'update_repository_upstream' => false,
        'delete_repository_upstream' => false,
        'read_artifact' => true,
        'create_artifact' => false,
        'delete_artifact' => true
      }
    end

    let(:second_upstream_permissions) do
      first_upstream_permissions.merge('update_repository' => false, 'delete_artifact' => false)
    end

    let(:upstreams_body_with_permissions) do
      [
        with_upstream_permissions(first_upstream, first_upstream_permissions),
        with_upstream_permissions(second_upstream, second_upstream_permissions)
      ]
    end

    def with_upstream_permissions(association, permissions)
      association.merge(
        'upstream_repository' => association['upstream_repository'].merge('permissions' => permissions)
      )
    end

    def stub_upstreams_list_with_permissions(body)
      stub_request(:get, upstreams_url).with(query: { include_permissions: 'true' })
        .to_return(status: 200, headers: json_headers, body: body.to_json)
    end

    def post_query_with_permissions
      post_graphql(query_with_permissions, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name })
    end

    it 'sends include_permissions=true on the upstream list alone and resolves each row its own upstream verdicts',
      :aggregate_failures do
      stub_repository_read
      list = stub_upstreams_list_with_permissions(upstreams_body_with_permissions)

      post_query_with_permissions

      expect(response).to have_gitlab_http_status(:ok)
      expect(list).to have_been_requested.once
      expect(a_request(:any, /include_permissions/)).to have_been_made.once
      expect(upstreams_response).to eq(
        [
          {
            'upstreamRepository' => {
              'name' => 'maven-hosted',
              'userPermissions' => {
                'readRepository' => true,
                'updateRepository' => true,
                'deleteRepository' => false,
                'createRepositoryUpstream' => false,
                'updateRepositoryUpstream' => false,
                'deleteRepositoryUpstream' => false,
                'readArtifact' => true,
                'createArtifact' => false,
                'deleteArtifact' => true
              }
            }
          },
          {
            'upstreamRepository' => {
              'name' => 'maven-remote',
              'userPermissions' => {
                'readRepository' => true,
                'updateRepository' => false,
                'deleteRepository' => false,
                'createRepositoryUpstream' => false,
                'updateRepositoryUpstream' => false,
                'deleteRepositoryUpstream' => false,
                'readArtifact' => true,
                'createArtifact' => false,
                'deleteArtifact' => false
              }
            }
          }
        ]
      )
      expect(graphql_errors).to be_nil
    end

    it 'sends no include_permissions when the block is not selected', :aggregate_failures do
      stub_repository_read
      list = stub_upstreams_list

      post_query

      expect(list).to have_been_requested.once
      expect(a_request(:any, /include_permissions/)).not_to have_been_made
    end

    context 'when the rows carry no permissions object' do
      before do
        allow(Gitlab::ErrorTracking).to receive(:track_exception)

        stub_repository_read
        stub_upstreams_list_with_permissions(upstreams_body)
      end

      it 'resolves every permission false, keeps the rows populated, and adds no error', :aggregate_failures do
        post_query_with_permissions

        expect(response).to have_gitlab_http_status(:ok)
        expect(upstreams_response.map { |row| row['upstreamRepository']['name'] })
          .to eq(%w[maven-hosted maven-remote])
        expect(upstreams_response.flat_map { |row| row['upstreamRepository']['userPermissions'].values })
          .to all(be(false))
        expect(upstreams_response.first['upstreamRepository']['userPermissions'].keys).to contain_exactly(
          'readRepository', 'updateRepository', 'deleteRepository', 'createRepositoryUpstream',
          'updateRepositoryUpstream', 'deleteRepositoryUpstream', 'readArtifact', 'createArtifact',
          'deleteArtifact'
        )
        expect(graphql_errors).to be_nil
      end

      it 'reports the absence once for the read and the slug, not once per row or field' do
        post_query_with_permissions

        expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
          instance_of(ArtifactRegistry::Permissions::VerdictReport::AbsentError),
          { read: :upstream_repositories, slug: 'resolved-handle' }
        ).once
      end
    end
  end

  context 'when the repository holds no upstreams yet' do
    let(:upstreams_body) { [] }

    it 'renders an empty list rather than a null one or an error', :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response).to eq([])
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository resolves its full upstream set' do
    let(:upstreams_body) do
      Array.new(20) do |i|
        {
          'id' => "assoc-#{i}-0000-0000-0000-000000000000",
          'position' => i + 1,
          'upstream_repository' => {
            'id' => "up-#{i}-0000-0000-0000-000000000000",
            'name' => "upstream-#{i}",
            'format' => format,
            'kind' => 'remote',
            'visibility' => 'private',
            'size_bytes' => 1024,
            'settings' => { 'url' => 'https://registry.example.com/upstream', 'last_health_status' => 'healthy' }
          }
        }
      end
    end

    it 'reads the whole list, with visibility, size, and settings, in exactly one Artifact Registry request',
      :aggregate_failures do
      stub_repository_read
      list = stub_upstreams_list

      post_query

      summaries = upstreams_response.pluck('upstreamRepository')

      expect(summaries.size).to eq(20)
      expect(summaries.pluck('visibility')).to all(eq('PRIVATE'))
      expect(summaries.pluck('sizeBytes')).to all(eq('1024'))
      expect(summaries.pluck('settings')).to all(eq(
        'url' => 'https://registry.example.com/upstream', 'lastHealthStatus' => 'HEALTHY'
      ))
      expect(list).to have_been_requested.once
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the user can read no upstream repository, so every summary carries only id, name, format, and kind' do
    let(:upstreams_body) do
      [first_upstream, second_upstream].map do |association|
        association.merge(
          'upstream_repository' => association['upstream_repository'].except('visibility', 'size_bytes', 'settings')
        )
      end
    end

    it 'resolves visibility, sizeBytes, and settings null on every row and keeps the rest of each element',
      :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response).to eq(expected_maven_upstreams)
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the user cannot read one upstream repository, so its summary carries only id, name, format, and kind' do
    let(:second_upstream) do
      association = super()

      association.merge(
        'upstream_repository' => association['upstream_repository'].except('visibility', 'size_bytes', 'settings')
      )
    end

    it 'resolves that row visibility, sizeBytes, and settings null and leaves the readable row intact',
      :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response).to eq(
        expected_maven_upstreams(
          hosted_read_fields: { 'visibility' => 'PUBLIC', 'sizeBytes' => '0', 'settings' => nil },
          remote_read_fields: unreadable_read_fields
        )
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when a remote upstream reports a health status outside the enum' do
    let(:second_upstream) do
      association = super()
      summary = association['upstream_repository']
      settings = summary['settings'].merge('last_health_status' => 'degraded')

      association.merge('upstream_repository' => summary.merge('settings' => settings))
    end

    it 'resolves the status UNKNOWN without an error', :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response.second.dig('upstreamRepository', 'settings')).to eq(
        'url' => 'https://registry.example.com/upstream', 'lastHealthStatus' => 'UNKNOWN'
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository is hosted or remote' do
    where(:kind) { %w[hosted remote] }

    with_them do
      let(:repository_body) { super().merge('kind' => kind) }

      it 'resolves the list null without asking Artifact Registry for upstreams', :aggregate_failures do
        stub_repository_read
        list = stub_upstreams_list

        post_query

        expect(upstreams_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(list).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository was deleted between the two reads (404 on the list)' do
    before do
      stub_upstreams_list(status: 404, body: error_envelope(code: 'not_found').to_json)
    end

    it_behaves_like 'resolving the list null while the repository still renders'
  end

  context 'when Artifact Registry answers the list read with a server error' do
    before do
      stub_upstreams_list(status: 503, body: error_envelope(code: 'service_unavailable').to_json)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read fails in transport' do
    before do
      stub_request(:get, upstreams_url).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read times out' do
    before do
      stub_request(:get, upstreams_url).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when Artifact Registry breaches the kind contract on an upstream' do
    where(:scenario, :kind_attributes, :reported) do
      [
        ['a kind outside the contract', { 'kind' => 'virtual' }, 'virtual'],
        ['a null kind', { 'kind' => nil }, 'none'],
        ['a blank kind', { 'kind' => '' }, 'none'],
        ['no kind at all', {}, 'none']
      ]
    end

    with_them do
      let(:first_upstream) do
        association = super()
        summary = association['upstream_repository'].except('kind').merge(kind_attributes)

        association.merge('upstream_repository' => summary)
      end

      it 'nulls that row kind with a top-level error and keeps the list and repository', :aggregate_failures do
        stub_repository_read
        stub_upstreams_list

        post_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_response['name']).to eq(repository_name)
        expect(upstreams_response).to be_present
        expect(upstreams_response.map { |row| row['upstreamRepository']['kind'] })
          .to contain_exactly(nil, 'REMOTE')
        expect_graphql_errors_to_include("unsupported upstream kind: #{reported}")
      end
    end
  end

  context 'when Artifact Registry breaches the visibility contract on an upstream' do
    let(:first_upstream) do
      association = super()

      association.merge(
        'upstream_repository' => association['upstream_repository'].merge('visibility' => 'restricted')
      )
    end

    it 'nulls that row visibility with a top-level error and keeps the list and repository', :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(repository_response['name']).to eq(repository_name)
      expect(upstreams_response.map { |row| row['upstreamRepository']['visibility'] }).to eq([nil, 'PRIVATE'])
      expect_graphql_errors_to_include('Artifact Registry returned an unsupported upstream visibility: restricted.')
    end
  end

  # Aliases would otherwise let one operation resolve the list repeatedly on the same repository,
  # each resolution its own Artifact Registry request. `FieldCallCount` raises on the second before
  # its resolve body runs, so the operation costs one list read rather than two.
  context 'when one operation selects the list twice under aliases' do
    let(:aliased_query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              name
              a: upstreamRepositories { id }
              b: upstreamRepositories { id }
            }
          }
        }
      QUERY
    end

    it 'rejects the second selection and issues one list read, not two', :aggregate_failures do
      stub_repository_read
      list = stub_upstreams_list

      post_graphql(aliased_query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(list).to have_been_requested.once
    end
  end

  context 'when the list read renders without leaking the Artifact Registry credential' do
    it 'keeps the token and scheme out of the response body', :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response.pluck('position')).to eq([1, 2])
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      list = stub_upstreams_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(list).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the user is not a member of the organization' do
    let(:current_user) { non_member }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  describe 'granular PAT authorization' do
    before do
      stub_repository_read
      stub_upstreams_list
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_organization do
      let(:user) { current_user }
      let(:boundary_object) { :instance }
      let(:request) do
        post_graphql(query, current_user: user, token: { personal_access_token: pat },
          variables: { id: organization.to_global_id.to_s, name: repository_name })
      end

      let(:skipped_data_path) do
        [:organization, :artifact_registry_repository, :upstream_repositories, 1, :upstream_repository, :settings]
      end
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_upstreams_list(status: 200, body: upstreams_body.to_json, headers: json_headers)
    stub_request(:get, upstreams_url).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def upstreams_response
    repository_response&.dig('upstreamRepositories')
  end

  def expected_maven_upstreams(
    hosted_read_fields: unreadable_read_fields,
    remote_read_fields: unreadable_read_fields
  )
    [
      {
        'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
        'position' => 1,
        'upstreamRepository' => {
          'id' => 'aaaa1111-0000-0000-0000-000000000000',
          'name' => 'maven-hosted',
          'format' => 'MAVEN',
          'kind' => 'HOSTED'
        }.merge(hosted_read_fields)
      },
      {
        'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
        'position' => 2,
        'upstreamRepository' => {
          'id' => 'bbbb2222-0000-0000-0000-000000000000',
          'name' => 'maven-remote',
          'format' => 'MAVEN',
          'kind' => 'REMOTE'
        }.merge(remote_read_fields)
      }
    ]
  end

  def unreadable_read_fields
    { 'visibility' => nil, 'sizeBytes' => nil, 'settings' => nil }
  end
end
