# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::Impact::Result, feature_category: :security_policy_management do
  it 'derives the compliant count from the other two' do
    result = described_class.new(
      projects_in_scope_count: 5, violating_count: 2, violating_projects: [], complete: true, unavailable_reason: nil
    )

    expect(result.compliant_count).to eq(3)
  end

  it 'builds an unavailable result with zero counts and the reason' do
    expect(described_class.unavailable('needs the engine')).to have_attributes(
      projects_in_scope_count: 0, violating_count: 0, compliant_count: 0, violating_projects: [], complete: false,
      unavailable_reason: 'needs the engine'
    )
  end
end
