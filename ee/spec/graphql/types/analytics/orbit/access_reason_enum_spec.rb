# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['OrbitAccessReason'], feature_category: :knowledge_graph do
  it 'maps every GraphQL value to its reason symbol' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'FREE_PLAN' => :free_plan,
      'NO_LICENSE' => :no_license,
      'NO_ACCESS' => :no_access,
      'TRIAL_EXPIRED' => :trial_expired,
      'CREDITS_EXHAUSTED' => :credits_exhausted,
      'PLAN' => :plan,
      'PROMO_ADD_ON' => :promo_add_on,
      'BETA' => :beta
    )
  end

  it 'covers every reason the value object defines' do
    expect(described_class.values.values.map(&:value)).to match_array(::Analytics::Orbit::Access::REASONS)
  end
end
