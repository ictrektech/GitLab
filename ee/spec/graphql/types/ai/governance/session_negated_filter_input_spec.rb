# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::SessionNegatedFilterInput, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceSessionNegatedFilterInput') }

  it 'has the expected arguments' do
    expect(described_class.arguments.keys).to match_array(%w[flowType projectPath triggeredByUserId])
  end
end
