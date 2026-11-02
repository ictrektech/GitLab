# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Pipeline do
  describe '.[]' do
    let(:full) { Class.new(Banzai::Pipeline::BasePipeline) }
    let(:label) { Class.new(Banzai::Pipeline::BasePipeline) }

    before do
      stub_const('Banzai::Pipeline::FullPipeline', full)
      stub_const('Banzai::Pipeline::LabelPipeline', label)
    end

    it 'resolves nil to the full pipeline' do
      expect(described_class[nil]).to eq(full)
    end

    it 'resolves a symbol by name' do
      expect(described_class[:label]).to eq(label)
    end

    it 'returns a pipeline class as is' do
      expect(described_class[label]).to eq(label)
    end

    it 'raises for an unknown symbol' do
      expect { described_class[:unknown] }
        .to raise_error(NameError, /uninitialized constant Banzai::Pipeline::UnknownPipeline/)
    end

    it 'raises for a class that is not a pipeline' do
      stub_const('Foo', Class.new)

      expect { described_class[Foo] }.to raise_error(ArgumentError, 'unsupported pipeline name Foo (Class)')
    end

    it 'raises for other types' do
      expect { described_class['label'] }.to raise_error(ArgumentError, 'unsupported pipeline name "label" (String)')
    end
  end
end
