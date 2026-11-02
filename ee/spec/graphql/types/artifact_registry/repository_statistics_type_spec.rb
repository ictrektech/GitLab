# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryRepositoryStatistics'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRepositoryStatistics') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the two live counts alone, omitting the stored counters and the other live counts' do
    is_expected.to have_graphql_fields(:packages_count, :images_count)
  end

  it 'renders each count as a nullable BigInt, experiment since 19.5', :aggregate_failures do
    %w[packagesCount imagesCount].each do |field_name|
      field = described_class.fields[field_name]

      expect(field.type.unwrap.graphql_name).to eq('BigInt')
      expect(field.type).to be_nullable
      expect(field.deprecation_reason).to include('Status: Experiment.', 'Introduced in GitLab 19.5')
    end
  end
end
