# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::Types::WorkItem, feature_category: :global_search do
  describe '#target' do
    it 'returns work_item class' do
      expect(described_class.target.class.name).to eq(WorkItem.class.name)
    end
  end

  describe '#index_name' do
    it 'returns correct environment based index name' do
      expect(described_class.index_name).to eq('gitlab-test-work_items')
    end
  end

  describe '#mappings' do
    let(:mappings) { described_class.mappings.to_hash[:properties] }

    it 'contains base mappings' do
      expect(mappings.keys).to include(:id, :title, :description)
    end

    describe 'title' do
      let(:title_mapping) { mappings[:title] }

      it 'keeps the relevance-side configuration untouched' do
        expect(title_mapping[:type]).to eq('text')
        expect(title_mapping[:index_options]).to eq('positions')
        expect(title_mapping[:analyzer]).to eq(:title_analyzer)
      end

      it 'adds a sortable keyword sub-field with an explicit ignore_above' do
        expect(title_mapping[:fields][:keyword]).to eq(
          type: 'keyword',
          normalizer: 'lower_case_normalizer',
          ignore_above: 1024
        )
      end

      it 'uses an ignore_above above the model title length limit' do
        expect(title_mapping.dig(:fields, :keyword, :ignore_above)).to be > Issuable::TITLE_LENGTH_MAX
      end
    end

    it 'does not contain embedding fields' do
      expect(mappings.keys).not_to include(:embedding_0, :embedding_1)
    end
  end

  describe '#settings' do
    let(:settings) { described_class.settings.to_hash[:index].keys }

    it 'contains base settings' do
      expect(settings).to include(:number_of_shards)
    end
  end
end
