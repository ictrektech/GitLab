# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::RepositoryStatistics, feature_category: :artifact_registry do
  let(:attributes) { { 'packages_count' => 1, 'images_count' => 5 } }

  subject(:statistics) { described_class.new(attributes) }

  describe '#packages_count' do
    it 'exposes the count' do
      expect(statistics.packages_count).to eq(1)
    end

    context 'when packages_count is absent' do
      let(:attributes) { { 'images_count' => 5 } }

      it 'reads nil rather than raising' do
        expect(statistics.packages_count).to be_nil
      end
    end
  end

  describe '#images_count' do
    it 'exposes the count' do
      expect(statistics.images_count).to eq(5)
    end

    context 'when images_count is absent' do
      let(:attributes) { { 'packages_count' => 1 } }

      it 'reads nil rather than raising' do
        expect(statistics.images_count).to be_nil
      end
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) do
      super().merge(
        'artifacts_count' => 3, 'size_bytes' => 987_654, 'downloads_count' => 11,
        'versions_count' => 2, 'files_count' => 6, 'tags_count' => 7, 'manifests_count' => 9,
        'dist_tags_count' => 12, 'newly_added_ar_field' => 'x'
      )
    end

    it 'exposes no reader for the stored counters, the other live counts, nor an unknown key',
      :aggregate_failures do
      expect(statistics.packages_count).to eq(1)
      expect(statistics.images_count).to eq(5)

      %i[
        artifacts_count size_bytes downloads_count
        versions_count files_count tags_count manifests_count dist_tags_count
        newly_added_ar_field
      ].each do |field|
        expect(statistics).not_to respond_to(field)
      end
    end
  end

  context 'when constructed with nil attributes' do
    subject(:statistics) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(statistics.packages_count).to be_nil
      expect(statistics.images_count).to be_nil
    end
  end
end
