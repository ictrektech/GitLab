# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::SessionSourceEnum, feature_category: :compliance_management do
  specify { expect(described_class.graphql_name).to eq('AiGovernanceSessionSource') }

  it 'exposes a value for every session source' do
    expect(described_class.values).to match(
      'GITLAB_DUO' => have_attributes(value: 'gitlab_duo'),
      'CLAUDE_CODE_COMPLIANCE_API' => have_attributes(value: 'claude_code_compliance_api'),
      'CLAUDE_CODE_GLAB' => have_attributes(value: 'claude_code_glab'),
      'MCP' => have_attributes(value: 'mcp')
    )
  end
end
