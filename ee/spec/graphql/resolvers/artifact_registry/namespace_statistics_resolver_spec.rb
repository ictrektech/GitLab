# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::NamespaceStatisticsResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:presented_registry) { ArtifactRegistry::RegistryPresenter.new(registry, organization: organization) }

  let(:statistics) do
    ArtifactRegistry::NamespaceStatistics.new(
      'repositories_count' => 7, 'deduplicated_size_bytes' => 987_654
    )
  end

  let(:client) { instance_double(ArtifactRegistry::Client, namespace_statistics: statistics) }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
  end

  subject(:resolve_statistics) do
    resolve(described_class, obj: presented_registry, ctx: { current_user: current_user })
  end

  it 'resolves the namespace statistics type, nullable', :aggregate_failures do
    expect(described_class.type).not_to be_non_null
    expect(described_class.type.unwrap).to eq(::Types::ArtifactRegistry::NamespaceStatisticsType)
  end

  it 'reads the statistics as the user for the presenter slug, without re-resolving the mapping',
    :aggregate_failures do
    expect(organization).not_to receive(:artifact_registry_namespace_mapping)

    expect(resolve_statistics).to be(statistics)
    expect(client).to have_received(:namespace_statistics).with(slug: slug)
  end

  it 'memoizes the read per request, so a second resolution in the same request issues no second AR call' do
    Gitlab::SafeRequestStore.ensure_request_store do
      resolve(described_class, obj: presented_registry, ctx: { current_user: current_user })
      resolve(described_class, obj: presented_registry, ctx: { current_user: current_user })
    end

    expect(client).to have_received(:namespace_statistics).once
  end

  context 'when the read fails' do
    where(:client_error) do
      [
        ArtifactRegistry::Client::UnavailableError.new('down', status: 503),
        ArtifactRegistry::Client::ConfigurationError.new('no base url'),
        ArtifactRegistry::Client::ApiError.new('bad request', status: 400),
        ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403),
        ArtifactRegistry::Client::AuthorizationError.new('closed', status: nil)
      ]
    end

    with_them do
      it 'resolves null rather than surfacing a GraphQL error, and tracks the failure',
        :aggregate_failures do
        allow(client).to receive(:namespace_statistics).and_raise(client_error)
        expect(::Gitlab::ErrorTracking).to receive(:log_exception).with(client_error, request_id: anything)

        expect(resolve_statistics).to be_nil
      end
    end
  end

  context 'when the client maps a 404 to nil' do
    let(:statistics) { nil }

    it 'resolves null' do
      expect(resolve_statistics).to be_nil
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'gates on the organization the presenter carries and makes no client call', :aggregate_failures do
      expect(resolve_statistics).to be_nil
      expect(client).not_to have_received(:namespace_statistics)
    end
  end
end
