# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::ToolRuleAccessType, feature_category: :ai_agents do
  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiToolRuleAccess')
  end

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:web_access, :local_access, :background_access)
  end
end
