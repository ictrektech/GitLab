# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Pipeline::CombinedPipeline do
  def pipeline_with(filter, key)
    Class.new(Banzai::Pipeline::BasePipeline) do
      define_singleton_method(:filters) { Banzai::FilterArray[filter] }
      define_singleton_method(:transform_context) { |context| context.merge(key => true) }
    end
  end

  let(:first_filter) { Class.new(HTML::Pipeline::Filter) }
  let(:second_filter) { Class.new(HTML::Pipeline::Filter) }
  let(:first) { pipeline_with(first_filter, :first) }
  let(:second) { pipeline_with(second_filter, :second) }

  subject(:combined) { described_class.new(first, second) }

  it 'is a pipeline' do
    expect(combined).to be < Banzai::Pipeline::BasePipeline
  end

  it 'keeps the pipelines in order' do
    expect(combined.pipelines).to eq([first, second])
  end

  it 'combines the filters in order' do
    expect(combined.filters).to eq([first_filter, second_filter])
  end

  it 'passes the context through each pipeline' do
    expect(combined.transform_context({})).to eq(first: true, second: true)
  end
end
