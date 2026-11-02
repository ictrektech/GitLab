# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Govern::PolicyEngine::ViolationDetails, feature_category: :security_policy_management do
  def decision_with(reasons)
    { matched: true, reasons: reasons }
  end

  it 'carries the reason message alongside the details of each violation' do
    details = described_class.from_decision(
      decision_with([{ message: 'drift', details: { 'path' => 'squash_option', 'expected' => 'never' } }])
    )

    expect(details.to_a).to contain_exactly(
      { 'path' => 'squash_option', 'expected' => 'never', 'message' => 'drift' }
    )
  end

  it 'drops a nil message rather than storing it' do
    details = described_class.from_decision(
      decision_with([{ message: nil, details: { 'path' => 'squash_option' } }])
    )

    expect(details.to_a.sole).to eq({ 'path' => 'squash_option' })
  end

  it 'tolerates a reason whose details are not a hash' do
    details = described_class.from_decision(decision_with([{ message: 'rego said no', details: nil }]))

    expect(details.to_a.sole).to eq({ 'message' => 'rego said no' })
    expect(details.settings).to be_empty
  end

  it 'is empty for a decision that did not match' do
    details = described_class.from_decision({ matched: false, reasons: [] })

    expect(details.to_a).to be_empty
  end

  describe '#settings and #joined_settings' do
    it 'names every setting a violation reports, in order' do
      details = described_class.from_decision(
        decision_with([
          { message: 'drift', details: { 'path' => 'request_access_enabled' } },
          { message: 'rego said no', details: {} },
          { message: 'drift', details: { 'path' => 'squash_option' } }
        ])
      )

      expect(details.settings).to eq(%w[request_access_enabled squash_option])
      expect(details.joined_settings).to eq('request_access_enabled,squash_option')
    end
  end
end
