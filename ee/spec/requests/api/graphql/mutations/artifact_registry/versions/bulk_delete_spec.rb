# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting a batch of versions of an Artifact Registry package',
  feature_category: :artifact_registry do
  include GraphqlHelpers

  using RSpec::Parameterized::TableSyntax

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:namespace_mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:service_token) { 'ar-service-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-hosted' }
  let(:package_id) { 'c3d4e5f6-0000-4000-8000-000000000000' }
  let(:ids) { version_ids(2) }

  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}" }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:bulk_delete_url) { "#{repository_url}/#{format}/packages/#{package_id}/versions/bulk_delete" }

  let(:namespace_body) do
    { 'id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active' }
  end

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'downloads_count' => 0,
      'size_bytes' => 0
    }
  end

  let(:input) { { 'name' => repository_name, 'packageId' => package_id, 'ids' => ids } }

  let(:mutation) do
    graphql_mutation(:artifact_registry_versions_bulk_delete, input, <<~FIELDS)
      errors
      repository {
        name
        format
      }
    FIELDS
  end

  before do
    current_organization.clear_memoization(:artifact_registry_client)

    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
      allow(credential).to receive(:token).and_return(service_token)
    end

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end

    stub_request(:get, namespace_url).to_return(status: 200, headers: json_headers, body: namespace_body.to_json)
  end

  context 'when Artifact Registry accepts the batch' do
    where(:format, :repository_name) do
      'maven' | 'maven-hosted'
      'npm'   | 'npm-hosted'
    end

    with_them do
      it 'posts the ids as version_ids to the route the format selects, and resolves', :aggregate_failures do
        read = stub_repository_read
        # Pinned as a literal so a stray key, delete_all included, cannot ride along.
        deletion = stub_request(:post, bulk_delete_url)
          .with(body: %({"version_ids":#{ids.to_json}}), headers: { 'Authorization' => "Bearer #{token}" })
          .to_return(status: 202, body: '', headers: json_headers)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(read).to have_been_requested.once
        expect(deletion).to have_been_requested.once
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['repository']).to eq('name' => repository_name, 'format' => format.upcase)
      end
    end
  end

  context 'when the repository is remote rather than hosted' do
    let(:repository_body) { super().merge('kind' => 'remote') }

    it 'issues the same route, leaving the delete-or-evict choice to Artifact Registry',
      :aggregate_failures do
      stub_repository_read
      deletion = stub_bulk_delete(status: 202)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(mutation_response['errors']).to be_empty
    end
  end

  context 'when the repository is virtual' do
    let(:repository_body) { super().merge('kind' => 'virtual') }

    it 'returns the not-found Artifact Registry answers as a mutation error', :aggregate_failures do
      stub_repository_read
      deletion = stub_bulk_delete(status: 404,
        body: { error: { code: 'not_found', message: 'repository not found' } }.to_json)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect(mutation_response['errors']).to contain_exactly('repository not found')
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the ids fill the batch' do
    # Repeats count toward the cap as sent, so one id repeated fills it.
    let(:ids) { version_ids(1) * 1000 }

    it 'sends the batch unchanged' do
      stub_repository_read
      deletion = stub_request(:post, bulk_delete_url)
        .with(body: { version_ids: ids }.to_json)
        .to_return(status: 202, body: '', headers: json_headers)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
    end
  end

  context 'when the ids are not a list of 1 to 1000 entries' do
    # case_name labels the rows; without it rspec-parameterized names each example after the
    # inspected value, which for the over-cap row is 1001 ids.
    where(:case_name, :ids, :refusal) do
      [
        ['an empty list', [], 'ids is too short (minimum is 1)'],
        ['a list over the cap', ['a1b2c3d4-0000-4000-8000-000000000001'] * 1001, 'ids is too long (maximum is 1000)']
      ]
    end

    with_them do
      it 'refuses the batch as a validation error without calling Artifact Registry', :aggregate_failures do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(a_request(:any, /#{Regexp.escape(base_url)}/)).not_to have_been_made
        expect_graphql_errors_to_include(refusal)
      end
    end
  end

  context 'when the repository holds container images rather than packages' do
    let(:format) { 'docker' }
    let(:repository_name) { 'docker-hosted' }

    it 'refuses before any deletion is attempted with a payload error', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:post, /bulk_delete/)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(deletion).not_to have_been_requested
      expect(mutation_response['errors']).to contain_exactly('Only Maven and npm repositories have versions.')
      expect(mutation_response['repository']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when Artifact Registry refuses the batch' do
    # 400 is an entry that is not a canonical UUID, which only Artifact Registry checks. 404 is a
    # repository gone since the read, or a malformed package id; an unknown package is a 202.
    # 413 bounds the body's bytes, which a direct caller controls within the entry cap.
    where(:status, :code, :message) do
      400 | 'invalid_argument'         | 'version_ids[0] is not a canonical UUID'
      404 | 'not_found'                | 'repository not found'
      413 | 'request_entity_too_large' | 'request body too large'
    end

    with_them do
      it 'reports a mutation error rather than resolving as a success', :aggregate_failures do
        stub_repository_read
        deletion = stub_bulk_delete(status: status, body: { error: { code: code, message: message } }.to_json)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(deletion).to have_been_requested.once
        expect(mutation_response['errors']).to contain_exactly(message)
        expect(mutation_response['repository']).to be_nil
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the job backend cannot take the enqueue (503)' do
    it 'surfaces the service-unavailable error, so the caller may retry the whole batch',
      :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_repository_read
      deletion = stub_bulk_delete(status: 503, body: { error: { code: 'service_unavailable' } }.to_json)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).to have_been_requested.once
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when Artifact Registry denies the batch' do
    where(:status) { [401, 403] }

    with_them do
      it 'reports the refusal after the attempt rather than hiding the repository', :aggregate_failures do
        stub_repository_read
        deletion = stub_bulk_delete(status: status, body: '{}')

        post_graphql_mutation(mutation, current_user: current_user)

        expect(deletion).to have_been_requested.once
        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end
  end

  context 'when the repository does not exist' do
    it 'hides its absence and deletes nothing', :aggregate_failures do
      stub_repository_read(status: 404, body: { error: { code: 'not_found' } }.to_json)
      deletion = stub_bulk_delete(status: 202)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the repository read is denied (403)' do
    it 'is indistinguishable from a missing repository and deletes nothing', :aggregate_failures do
      stub_repository_read(status: 403, body: '{}')
      deletion = stub_bulk_delete(status: 202)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the package id is blank' do
    let(:package_id) { '' }

    it 'raises the client guard before any deletion is attempted', :aggregate_failures do
      stub_repository_read
      deletion = stub_request(:post, /bulk_delete/)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(deletion).not_to have_been_requested
      expect_graphql_errors_to_include('package_id is required')
    end
  end

  context 'when the user cannot read the organization registry' do
    it 'raises a top-level ResourceNotAvailable and acquires no client', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: non_member)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'raises a top-level ResourceNotAvailable and acquires no client', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def stub_bulk_delete(status:, body: '')
    stub_request(:post, bulk_delete_url).to_return(status: status, body: body, headers: json_headers)
  end

  # Canonical UUIDs, the only entries Artifact Registry accepts. Kernel.format, since let(:format)
  # shadows the helper.
  def version_ids(count)
    Array.new(count) { |i| Kernel.format('a1b2c3d4-0000-4000-8000-%012d', i) }
  end

  def mutation_response
    graphql_mutation_response(:artifact_registry_versions_bulk_delete)
  end
end
