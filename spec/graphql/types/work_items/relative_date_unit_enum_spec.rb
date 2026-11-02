# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Types::WorkItems::RelativeDateUnitEnum, feature_category: :team_planning do
  it { expect(described_class.graphql_name).to eq('WorkItemRelativeDateUnit') }

  it 'exposes the relative date units' do
    expect(described_class.values.keys).to match_array(%w[DAY WEEK MONTH YEAR])
  end

  it 'uses the GraphQL names as values, so saved views can send them back unchanged' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'DAY' => 'DAY', 'WEEK' => 'WEEK', 'MONTH' => 'MONTH', 'YEAR' => 'YEAR'
    )
  end

  it 'covers every unit supported by Gitlab::RelativeDate' do
    expect(described_class.values.keys).to match_array(::Gitlab::RelativeDate::UNITS.keys)
  end
end
