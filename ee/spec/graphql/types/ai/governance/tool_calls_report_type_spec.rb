# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::ToolCallsReportType, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceToolCallsReport') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:nodes, :approximate, :by_risk)
  end
end
