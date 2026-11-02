# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::RepositoryStatisticsResolver, :with_current_organization,
  feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:current_user) { create(:user) }

  let(:format) { 'maven' }
  let(:kind) { 'hosted' }
  let(:repository_name) { 'maven-releases' }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format, 'kind' => kind) }
  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: current_organization) }

  let(:statistics) { ArtifactRegistry::RepositoryStatistics.new('packages_count' => 3) }
  let(:client) { instance_double(ArtifactRegistry::Client, repository_statistics: statistics) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }

  before do
    allow(current_organization).to receive(:artifact_registry_client)
      .with(current_user: current_user).and_return(client)
    allow(current_organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_statistics) do
    resolve(
      described_class,
      obj: presented_repository,
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] }
    )
  end

  it 'limits the field to one resolution per request, ahead of any client call' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  context 'when the repository is hosted' do
    where(:format) { %w[maven npm docker oci] }

    with_them do
      it 'reads the statistics through the organization the presenter carries, with the repository format' do
        resolve_statistics

        expect(client).to have_received(:repository_statistics)
          .with(slug: slug, repository_name: repository_name, format: format)
      end

      it 'returns the statistics value object' do
        expect(resolve_statistics).to be(statistics)
      end
    end
  end

  context 'when the repository is not hosted (statistics are hosted-only)' do
    where(:kind) { %w[remote virtual] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_statistics).to be_nil
        expect(client).not_to have_received(:repository_statistics)
      end
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_statistics).to be_nil
      expect(client).not_to have_received(:repository_statistics)
    end
  end
end
