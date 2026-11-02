# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ViolationMessage, feature_category: :security_policy_management do
  def message_for(reasons, policy_name: 'Baseline')
    policy = build_stubbed(:govern_policy, name: policy_name)
    details = Govern::PolicyEngine::ViolationDetails.from_decision({ matched: true, reasons: reasons })

    described_class.new(policy: policy, details: details).to_s
  end

  it 'names the policy and reports the expected and the actual value of each setting' do
    text = message_for([
      { message: 'drift', details: { 'path' => 'request_access_enabled', 'expected' => false,
                                     'actual' => true } }
    ])

    expect(text).to eq(
      "Settings enforcement policy 'Baseline' detected a violation: " \
        'request_access_enabled expected false actual true'
    )
  end

  it 'omits a value the violation does not report' do
    text = message_for([{ message: 'drift', details: { 'path' => 'squash_option', 'actual' => 'always' } }])

    expect(text).to end_with('squash_option actual "always"')
  end

  it 'names the path alone for a violation that reports no value at all' do
    text = message_for([{ message: 'drift', details: { 'path' => 'squash_option' } }])

    expect(text).to end_with('detected a violation: squash_option')
  end

  it 'falls back to the reason message for a violation that names no setting' do
    text = message_for([{ message: 'rego denied', details: {} }])

    expect(text).to include('rego denied')
  end

  it 'reports the violation alone when the decision gives no reason for it' do
    expect(message_for([])).to eq("Settings enforcement policy 'Baseline' detected a violation")
  end

  it 'reports the violation alone when no reason describes itself' do
    expect(message_for([{ message: nil, details: {} }]))
      .to eq("Settings enforcement policy 'Baseline' detected a violation")
  end

  it 'joins several violations' do
    text = message_for([
      { message: 'drift', details: { 'path' => 'squash_option', 'expected' => 'never', 'actual' => 'always' } },
      { message: 'drift', details: { 'path' => 'visibility', 'expected' => 'private', 'actual' => 'internal' } }
    ])

    expect(text).to include('squash_option expected "never" actual "always"; visibility expected "private"')
  end
end
