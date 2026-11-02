# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::SettingValidationRule, feature_category: :security_policy_management do
  describe '.for_policy' do
    it 'reads each setting_validation rule of the policy and skips the custom ones', :aggregate_failures do
      policy = build_stubbed(:govern_policy, rules: [
        { 'type' => 'setting_validation', 'value' => { 'setting' => 'request_access_enabled', 'value' => false } },
        { 'type' => 'custom', 'rego' => 'package governance' }
      ])

      rules = described_class.for_policy(policy)

      expect(rules.size).to eq(1)
      expect(rules.first.setting).to eq('request_access_enabled')
      expect(rules.first.expected).to be(false)
    end
  end

  describe '.from_rule' do
    it 'is nil for a custom rule, which has no persisted shape' do
      expect(described_class.from_rule('type' => 'custom', 'rego' => 'x')).to be_nil
    end

    it 'is nil for a value that is not a hash or names no setting', :aggregate_failures do
      expect(described_class.from_rule('type' => 'setting_validation', 'value' => 'oops')).to be_nil
      expect(described_class.from_rule('type' => 'setting_validation', 'value' => { 'value' => true })).to be_nil
    end
  end
end
