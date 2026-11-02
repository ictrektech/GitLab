# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Types::WorkItems::RelativeDateInputType, feature_category: :team_planning do
  it { expect(described_class.graphql_name).to eq('WorkItemRelativeDateInput') }

  it { expect(described_class.arguments.keys).to match_array(%w[amount unit]) }

  it 'requires all arguments' do
    expect(described_class.arguments.values.map(&:type)).to all(be_non_null)
  end
end
