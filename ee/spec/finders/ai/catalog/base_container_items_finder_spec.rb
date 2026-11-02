# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::BaseContainerItemsFinder, feature_category: :ai_catalog_curation do
  let(:finder) { described_class.new(build_stubbed(:user), build_stubbed(:project)) }

  describe 'abstract methods' do
    it 'raises NotImplementedError for #authorized?' do
      expect { finder.send(:authorized?) }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for #init_collection' do
      expect { finder.send(:init_collection) }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for #enabled_consumers' do
      expect { finder.send(:enabled_consumers, :direct) }.to raise_error(NotImplementedError)
    end
  end

  describe '#filter_items' do
    it 'returns the items unchanged by default' do
      items = Ai::Catalog::Item.all

      expect(finder.send(:filter_items, items)).to be(items)
    end
  end
end
