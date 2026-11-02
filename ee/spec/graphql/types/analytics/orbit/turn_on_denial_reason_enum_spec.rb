# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['OrbitTurnOnDenialReason'], feature_category: :knowledge_graph do
  it 'maps every GraphQL value to its denial reason symbol' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'FORBIDDEN' => :forbidden,
      'TRIAL_REQUIRED' => :trial_required,
      'PURCHASE_REQUIRED' => :purchase_required,
      'TRIAL_ENDED' => :trial_ended,
      'UNAVAILABLE' => :unavailable
    )
  end

  it 'covers every denial reason the value object defines' do
    expect(described_class.values.values.map(&:value)).to match_array(::Analytics::Orbit::Access::TURN_ON_DENIAL_REASONS)
  end
end
