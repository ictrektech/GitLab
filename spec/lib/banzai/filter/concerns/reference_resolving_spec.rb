# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Banzai::Filter::Concerns::ReferenceResolving, feature_category: :markdown do
  let(:filter_class) do
    Class.new do
      include Banzai::Filter::Concerns::ReferenceResolving

      attr_reader :context, :result

      def initialize(context, result)
        @context = context
        @result = result
      end
    end
  end

  it 'builds the resolver from the context and shares it through the result for the whole run', :aggregate_failures do
    result = {}

    resolver = filter_class.new({ project: nil }, result).reference_resolver

    expect(resolver).to be_a(Banzai::ReferenceResolver)
    expect(filter_class.new({}, result).reference_resolver).to equal(resolver)
  end

  it 'takes a resolver given in the context before deriving one' do
    resolver = Banzai::ReferenceResolver.new

    expect(filter_class.new({ reference_resolver: resolver }, {}).reference_resolver).to equal(resolver)
  end
end
