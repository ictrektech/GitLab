# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryNamespaceStatistics'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryNamespaceStatistics') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the two figures a surface renders, omitting the endpoint fields no surface reads' do
    is_expected.to have_graphql_fields(:repositories_count, :deduplicated_size_bytes)
  end

  describe 'the figures' do
    it 'renders repositoriesCount as a nullable BigInt', :aggregate_failures do
      field = described_class.fields['repositoriesCount']

      expect(field.type.unwrap.graphql_name).to eq('BigInt')
      expect(field.type).to be_nullable
    end

    it 'renders deduplicatedSizeBytes as a nullable BigInt', :aggregate_failures do
      field = described_class.fields['deduplicatedSizeBytes']

      expect(field.type.unwrap.graphql_name).to eq('BigInt')
      expect(field.type).to be_nullable
    end
  end
end
