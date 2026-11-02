# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::ToolAccessTypeEnum, feature_category: :ai_agents do
  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiToolAccessType')
  end

  it 'maps each value to its rule attribute' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'WEB_ACCESS' => :web_access,
      'LOCAL_ACCESS' => :local_access,
      'BACKGROUND_ACCESS' => :background_access
    )
  end
end
