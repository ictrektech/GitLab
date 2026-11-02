# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Pipeline::BasePipeline do
  let(:upcase_filter) do
    Class.new(HTML::Pipeline::Filter) do
      def call
        doc.traverse { |node| node.content = "#{node.content.upcase}#{context[:suffix]}" if node.text? }
        doc
      end
    end
  end

  let(:pipeline) do
    filter = upcase_filter

    Class.new(described_class) do
      define_singleton_method(:name) { 'TestPipeline' }
      define_singleton_method(:filters) { Banzai::FilterArray[filter] }
      define_singleton_method(:transform_context) { |context| context.merge(suffix: '!') }
    end
  end

  it 'has no filters' do
    expect(described_class.filters).to be_empty
  end

  it 'returns the context unchanged' do
    context = { project: :foo }

    expect(described_class.transform_context(context)).to be(context)
  end

  it 'runs the filters with the transformed context' do
    expect(pipeline.to_html('<p>foo</p>', {})).to eq('<p>FOO!</p>')
  end

  it 'builds the pipeline once' do
    html_pipeline = pipeline.html_pipeline

    expect(pipeline.html_pipeline).to be(html_pipeline)
  end
end
