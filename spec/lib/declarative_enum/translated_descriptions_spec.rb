# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeclarativeEnum::TranslatedDescriptions, feature_category: :internationalization do
  let(:enum_module) do
    Module.new do
      extend DeclarativeEnum
      extend DeclarativeEnum::TranslatedDescriptions

      define do
        foo value: 0, description: N_('description of foo')
        bar value: 1, description: N_('description of bar')
      end
    end
  end

  describe '#translated_descriptions' do
    subject(:translated_descriptions) { enum_module.translated_descriptions }

    it 'translates the description of each definition' do
      expect(translated_descriptions).to eq(
        foo: 'description of foo',
        bar: 'description of bar'
      )
    end

    context 'when a translation is available' do
      before do
        allow(enum_module).to receive(:_).with('description of foo').and_return('Beschreibung von foo')
        allow(enum_module).to receive(:_).with('description of bar').and_return('Beschreibung von bar')
      end

      it 'returns the translated descriptions' do
        expect(translated_descriptions).to eq(
          foo: 'Beschreibung von foo',
          bar: 'Beschreibung von bar'
        )
      end
    end

    it 'translates at call time rather than caching the result' do
      allow(enum_module).to receive(:_).and_call_original
      allow(enum_module).to receive(:_).with('description of foo').and_return('Beschreibung von foo')

      expect(enum_module.translated_descriptions[:foo]).to eq('Beschreibung von foo')

      allow(enum_module).to receive(:_).with('description of foo').and_return('description de foo')

      expect(enum_module.translated_descriptions[:foo]).to eq('description de foo')
    end
  end
end
