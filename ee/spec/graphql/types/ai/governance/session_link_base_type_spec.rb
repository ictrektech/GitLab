# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::SessionLinkBaseType, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceSessionLinkBase') }

  it 'exposes the expected fields without a workflow field' do
    expect(described_class).to have_graphql_fields(:id, :created_at)
  end

  it 'has no type-level authorization' do
    expect(described_class.authorization).to be_none
  end
end
