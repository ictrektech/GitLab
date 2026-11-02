# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reading the organization Artifact Registry namespace statistics', :use_clean_rails_memory_store_caching, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }
  let_it_be(:mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:service_token) { 'ar-service-credential-value' }
  let(:namespace_uuid) { mapping.ar_namespace_id }
  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_uuid}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:slug) { 'acme' }
  let(:statistics_url) { "#{base_url}/api/v1/#{slug}/statistics" }
  let(:repositories_url) { "#{base_url}/api/v1/#{slug}/repositories" }

  let(:namespace_body) do
    {
      'id' => namespace_uuid, 'slug' => slug, 'platform' => 'gitlab', 'entity_type' => 'group',
      'entity_id' => '42', 'status' => 'active', 'created_at' => '2026-07-01T10:00:00Z'
    }
  end

  let(:statistics_body) do
    { 'repositories_count' => 7, 'deduplicated_size_bytes' => 987_654, 'components_count' => 3, 'downloads_count' => 0 }
  end

  let(:repositories_body) { { 'repositories' => [] } }

  let(:statistics_fields) { 'statistics { repositoriesCount deduplicatedSizeBytes }' }

  let(:query) do
    graphql_query_for(
      :organization,
      { id: organization.to_global_id.to_s },
      query_graphql_field(:artifact_registry, {}, statistics_fields)
    )
  end

  let(:registry_data) { graphql_data.dig('organization', 'artifactRegistry') }
  let(:statistics_data) { registry_data&.dig('statistics') }

  before do
    stub_config(artifact_registry: { api_url: base_url })
    allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
      allow(credential).to receive(:token).and_return(service_token)
    end
    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for) { |user, _org| "token-for-#{user.id}" }
    end
  end

  def stub_namespace(status: 200, body: namespace_body.to_json)
    stub_request(:get, namespace_url)
      .with(headers: { ArtifactRegistry::Transport::SERVICE_TOKEN_HEADER => service_token })
      .to_return(status: status, headers: json_headers, body: body)
  end

  def stub_statistics(status:, body: statistics_body.to_json)
    stub_request(:get, statistics_url)
      .with(headers: { 'Authorization' => "Bearer token-for-#{current_user.id}" })
      .to_return(status: status, headers: json_headers, body: body)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      stub_namespace
    end

    it 'issues one statistics GET per query and exposes both figures', :aggregate_failures do
      read = stub_statistics(status: 200)

      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(read).to have_been_requested.once
      expect(graphql_errors).to be_nil
      # BigInt serializes as a string on the wire, so both figures arrive quoted.
      expect(statistics_data).to eq('repositoriesCount' => '7', 'deduplicatedSizeBytes' => '987654')
    end

    context 'when the read fails on a status the header must not surface as an error' do
      where(:http_status) { [401, 403, 500, 503, 400, 501] }

      with_them do
        it 'resolves statistics null with no errors entry, and the sibling status still renders',
          :aggregate_failures do
          stub_statistics(status: http_status, body: {}.to_json)

          post_graphql(
            graphql_query_for(:organization, { id: organization.to_global_id.to_s },
              query_graphql_field(:artifact_registry, {}, "status #{statistics_fields}")),
            current_user: current_user
          )

          expect(graphql_errors).to be_nil
          expect(registry_data['status']).to eq('active')
          expect(statistics_data).to be_nil
        end
      end
    end

    context 'when the statistics read times out at the transport' do
      it 'resolves null on a transport failure' do
        stub_request(:get, statistics_url).to_timeout

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(statistics_data).to be_nil
      end
    end

    context 'when the mapped namespace is unknown to AR (404 on both reads)' do
      it 'resolves the field null, since the same slug 404s the statistics read' do
        stub_statistics(status: 404, body: {}.to_json)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(statistics_data).to be_nil
      end
    end

    context 'when AR answers 404 for the namespace read' do
      before do
        stub_namespace(status: 404, body: {}.to_json)
      end

      it 'resolves statistics null without an error or a statistics call', :aggregate_failures do
        read = stub_statistics(status: 200)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(read).not_to have_been_requested
        expect(statistics_data).to be_nil
      end
    end

    context 'when the organization has no mapped namespace' do
      before do
        allow_next_found_instance_of(Organizations::Organization) do |org|
          allow(org).to receive(:artifact_registry_namespace_mapping).and_return(nil)
        end
      end

      it 'resolves null without an AR statistics call', :aggregate_failures do
        read = stub_statistics(status: 200)

        post_graphql(query, current_user: current_user)

        expect(read).not_to have_been_requested
        expect(statistics_data).to be_nil
      end
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves the parent registry null without any AR call', :aggregate_failures do
      namespace_read = stub_namespace
      statistics_read = stub_statistics(status: 200)

      post_graphql(query, current_user: current_user)

      expect(namespace_read).not_to have_been_requested
      expect(statistics_read).not_to have_been_requested
      expect(registry_data).to be_nil
    end
  end
end
