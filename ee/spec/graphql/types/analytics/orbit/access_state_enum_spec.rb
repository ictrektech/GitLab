# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['OrbitAccessState'], feature_category: :knowledge_graph do
  it 'maps every GraphQL value to its state symbol' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'NOT_CONFIGURED' => :not_configured,
      'UNLICENSED' => :unlicensed,
      'TRIAL_ELIGIBLE' => :trial_eligible,
      'TRIAL_ACTIVE' => :trial_active,
      'TRIAL_ENDED' => :trial_ended,
      'TRIAL_NOT_ELIGIBLE' => :trial_not_eligible,
      'TRIAL_STATUS_UNAVAILABLE' => :trial_status_unavailable,
      'LICENSED' => :licensed
    )
  end

  it 'covers every state the value object defines' do
    expect(described_class.values.values.map(&:value)).to match_array(::Analytics::Orbit::Access::STATES)
  end
end
