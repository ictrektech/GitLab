# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository statistics', :with_current_organization,
  feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { current_organization }
  let_it_be(:organization_user) { create(:user) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:non_member) { create(:user, organization: other_organization) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }

  let(:format) { 'maven' }
  let(:kind) { 'hosted' }
  let(:repository_name) { 'maven-releases' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:statistics_url) { "#{repository_url}/statistics" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => kind,
      'visibility' => 'private',
      'settings' => {}
    }
  end

  let(:package_statistics_body) do
    {
      'artifacts_count' => 7, 'size_bytes' => 4096, 'downloads_count' => 11,
      'packages_count' => 3, 'versions_count' => 7, 'files_count' => 21
    }
  end

  let(:image_statistics_body) do
    {
      'artifacts_count' => 9, 'size_bytes' => 8192, 'downloads_count' => 13,
      'images_count' => 4, 'tags_count' => 6, 'manifests_count' => 9
    }
  end

  let(:statistics_body) { package_statistics_body }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryRepositoryStatistics(
        $id: OrganizationsOrganizationID!
        $name: String!
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            statistics {
              packagesCount
              imagesCount
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

  shared_examples 'resolving the statistics null while the repository still renders' do
    it 'renders null statistics, no error, and the repository around it, after issuing the read',
      :aggregate_failures do
      stub_repository_read

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(repository_response['name']).to eq(repository_name)
      expect(repository_response.fetch('statistics')).to be_nil
      expect(a_request(:get, statistics_url)).to have_been_made.once
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'rendering the service-unavailable error beside the loaded repository' do
    it 'renders null statistics with the service-unavailable error and keeps the repository rendered',
      :aggregate_failures do
      stub_repository_read

      post_query

      expect(repository_response['name']).to eq(repository_name)
      expect(repository_response.fetch('statistics')).to be_nil
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the repository is hosted and holds packages' do
    where(:format, :repository_name) do
      'maven' | 'maven-releases'
      'npm'   | 'npm-releases'
    end

    with_them do
      it 'renders packagesCount from the live count, with imagesCount null, in one statistics read',
        :aggregate_failures do
        stub_repository_read
        statistics = stub_statistics_read

        post_query

        expect(repository_response['statistics']).to eq('packagesCount' => '3', 'imagesCount' => nil)
        expect(statistics).to have_been_requested.once
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository is hosted and holds images' do
    where(:format, :repository_name) do
      'docker' | 'docker-images'
      'oci'    | 'oci-images'
    end

    with_them do
      let(:statistics_body) { image_statistics_body }

      it 'renders imagesCount from the live count, with packagesCount null, in one statistics read',
        :aggregate_failures do
        stub_repository_read
        statistics = stub_statistics_read

        post_query

        expect(repository_response['statistics']).to eq('packagesCount' => nil, 'imagesCount' => '4')
        expect(statistics).to have_been_requested.once
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository is not hosted (statistics are hosted-only)' do
    where(:kind) { %w[remote virtual] }

    with_them do
      it 'resolves the field null without asking Artifact Registry for statistics', :aggregate_failures do
        stub_repository_read
        statistics = stub_statistics_read

        post_query

        expect(repository_response['name']).to eq(repository_name)
        expect(repository_response.fetch('statistics')).to be_nil
        expect(statistics).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository was deleted between the two reads (404 on the statistics read)' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_statistics_read(status: 404, body: error_envelope(code: 'not_found').to_json)
    end

    it_behaves_like 'resolving the statistics null while the repository still renders'

    it 'reports nothing to error tracking for the issued read' do
      stub_repository_read

      post_query

      expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
    end
  end

  context 'when Artifact Registry rejects the statistics read' do
    where(:status, :request_id) do
      401 | 'req-401'
      403 | 'req-403'
    end

    with_them do
      before do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_statistics_read(status: status, body: error_envelope(code: 'denied', request_id: request_id).to_json)
      end

      it_behaves_like 'resolving the statistics null while the repository still renders'

      it 'logs the rejection once, with the Artifact Registry request_id', :aggregate_failures do
        stub_repository_read

        post_query

        expect(Gitlab::ErrorTracking).to have_received(:log_exception).once
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(an_instance_of(ArtifactRegistry::Client::AuthorizationError), hash_including(request_id: request_id))
      end
    end
  end

  context 'when the statistics read maps to a service-unavailable error' do
    where(:status, :error_code, :request_id) do
      429 | 'rate_limited' | 'req-429'
      500 | 'internal'     | 'req-500'
      503 | 'unavailable'  | 'req-503'
    end

    with_them do
      before do
        stub_statistics_read(status: status, body: error_envelope(code: error_code, request_id: request_id).to_json)
      end

      it_behaves_like 'rendering the service-unavailable error beside the loaded repository'

      it 'preserves the Artifact Registry request_id on the error' do
        stub_repository_read

        post_query

        expect(graphql_errors.first.dig('extensions', 'request_id')).to eq(request_id)
      end
    end
  end

  context 'when the statistics read returns a non-404 client error' do
    it 'renders null statistics with a top-level error carrying the code and request_id', :aggregate_failures do
      stub_repository_read
      stub_statistics_read(status: 409, body: error_envelope(code: 'conflict', request_id: 'req-409').to_json)

      post_query

      expect(repository_response['name']).to eq(repository_name)
      expect(repository_response.fetch('statistics')).to be_nil
      expect(graphql_errors.size).to eq(1)
      expect(graphql_errors.first['extensions']).to include('code' => 'conflict', 'request_id' => 'req-409')
    end
  end

  context 'when a 200 statistics body lacks the count for the repository format family' do
    where(:scenario, :format, :repository_name, :body_key) do
      'an empty Maven body'                 | 'maven'  | 'maven-releases' | :empty
      'a Maven body of the image family'    | 'maven'  | 'maven-releases' | :image
      'an empty Docker body'                | 'docker' | 'docker-images'  | :empty
      'a Docker body of the package family' | 'docker' | 'docker-images'  | :package
    end

    with_them do
      let(:statistics_body) do
        { empty: {}, image: image_statistics_body, package: package_statistics_body }.fetch(body_key)
      end

      before do
        stub_statistics_read
      end

      it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
    end
  end

  context 'when the statistics read fails in transport' do
    before do
      stub_request(:get, statistics_url).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the statistics read times out' do
    before do
      stub_request(:get, statistics_url).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the statistics read renders without leaking the Artifact Registry credential' do
    it 'keeps the token and scheme out of the response body', :aggregate_failures do
      stub_repository_read
      stub_statistics_read

      post_query

      expect(repository_response['statistics']).to eq('packagesCount' => '3', 'imagesCount' => nil)
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  # Aliases would otherwise let one operation read the statistics repeatedly on the same repository,
  # each resolution its own Artifact Registry request.
  context 'when one operation selects the statistics twice under aliases' do
    let(:aliased_query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              name
              a: statistics { packagesCount }
              b: statistics { packagesCount }
            }
          }
        }
      QUERY
    end

    it 'rejects the second selection and issues one statistics read, not two', :aggregate_failures do
      stub_repository_read
      statistics = stub_statistics_read

      post_graphql(aliased_query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(statistics).to have_been_requested.once
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      statistics = stub_statistics_read

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(statistics).not_to have_been_requested
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
      stub_statistics_read
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_organization do
      let(:user) { current_user }
      let(:boundary_object) { :instance }
      let(:request) do
        post_graphql(query, current_user: user, token: { personal_access_token: pat },
          variables: { id: organization.to_global_id.to_s, name: repository_name })
      end

      let(:skipped_data_path) { %i[organization artifact_registry_repository statistics] }
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_statistics_read(status: 200, body: statistics_body.to_json, headers: json_headers)
    stub_request(:get, statistics_url).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end
end
