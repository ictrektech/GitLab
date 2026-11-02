# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Types::WorkItems::RelativeDateFiltersInputType, feature_category: :team_planning do
  it { expect(described_class.graphql_name).to eq('WorkItemRelativeDateFiltersInput') }

  it 'has one argument per absolute date filter' do
    expect(described_class.arguments.keys).to match_array(
      ::WorkItems::SharedFilterArguments::RELATIVE_DATE_FILTER_KEYS.map { |key| key.to_s.camelize(:lower) }
    )
  end

  it 'makes every argument an optional relative date' do
    expect(described_class.arguments.values.map(&:type)).to all(eq(::Types::WorkItems::RelativeDateInputType))
  end
end
