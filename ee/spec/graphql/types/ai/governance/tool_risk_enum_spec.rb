# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::ToolRiskEnum, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceToolRisk') }

  it 'exposes the expected values' do
    expect(described_class.values).to match(
      'READ' => have_attributes(value: :read),
      'WRITE' => have_attributes(value: :write),
      'DESTROY' => have_attributes(value: :destroy),
      'UNCLASSIFIED' => have_attributes(value: :unclassified)
    )
  end
end
