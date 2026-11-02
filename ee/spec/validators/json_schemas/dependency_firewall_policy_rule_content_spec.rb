# frozen_string_literal: true

require 'fast_spec_helper'
require_relative './risk_severity_rule_shared_examples'
require_relative './package_version_rule_shared_examples'

# This schema validates `Security::DependencyFirewallPolicyRule#typed_content`, a single rule
# object rather than a whole policy. It is the only guard on this file's `risk_severity` branch:
# the main-schema integrity example in orchestration_policy_configuration_spec.rb compares only
# `properties.type` for this partial, so drift in the root-level `allOf` is invisible to it.
RSpec.describe 'dependency_firewall_policy_rule_content.json', feature_category: :dependency_firewall do
  let(:schema_path) do
    Rails.root.join("ee/app/validators/json_schemas/dependency_firewall_policy_rule_content.json")
  end

  let(:schema) { JSONSchemer.schema(schema_path) }
  let(:validation_result) { schema.validate(rule, output_format: 'basic') }

  context 'when the rule is a risk_severity rule' do
    let(:denied_pointer) { '/denied/0' }

    it_behaves_like 'a risk_severity rule schema'
  end

  context 'when the rule is a package_version rule' do
    let(:denied_pointer) { '/denied/0' }

    it_behaves_like 'a package_version rule schema'
  end

  context 'when the rule is a removed vulnerability rule' do
    let(:rule) { { type: 'vulnerability', denied: [{ severity: 'critical' }] } }

    it 'is invalid since the type is no longer supported' do
      expect(validation_result['valid']).to be false
      expect(validation_result['errors'].pluck('error')).to include(
        'value at `/type` is not one of: ["license", "malicious", "age", "risk_severity", "package_version"]')
    end
  end
end
