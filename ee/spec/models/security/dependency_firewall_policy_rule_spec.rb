# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewallPolicyRule, feature_category: :security_policy_management do
  it_behaves_like 'policy rule' do
    let(:rule_hash) { build(:dependency_firewall_policy)[:rules].first }
    let(:policy_type) { :dependency_firewall_policy }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:security_policy).inverse_of(:dependency_firewall_policy_rules).required }
  end

  describe 'enum type' do
    it 'defines license, malicious, risk_severity, and package_version types' do
      expect(described_class.types).to eq(
        'license' => 0, 'malicious' => 2, 'risk_severity' => 4, 'package_version' => 5
      )
    end

    it 'leaves 1 and 3 unassigned for the removed vulnerability and the in-flight age rule types' do
      expect(described_class.types.values).not_to include(1, 3)
    end
  end

  describe '.severity_carrying_types' do
    it 'names the types whose findings carry a severity', :aggregate_failures do
      expect(described_class.severity_carrying_types).to contain_exactly('risk_severity')
      # Every entry must be a real type, or consumers branching on it silently match nothing.
      expect(described_class.types.keys).to include(*described_class.severity_carrying_types)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:type) }
    it { is_expected.to validate_presence_of(:rule_index) }

    describe 'content' do
      subject(:rule) { build(:dependency_firewall_policy_rule, content: content) }

      context 'with denied licenses' do
        let(:content) { { denied: [{ name: 'MIT License' }] } }

        it { is_expected.to be_valid }
      end

      context 'with allowed licenses' do
        let(:content) { { allowed: [{ name: 'Apache-2.0' }] } }

        it { is_expected.to be_valid }
      end

      context 'with exceptions' do
        context 'with denied' do
          let(:content) do
            { denied: [{ name: 'MIT License' }], exceptions: [{ purl: 'pkg:npm/myinternallib' }] }
          end

          it { is_expected.to be_valid }
        end

        context 'with allowed' do
          let(:content) do
            { allowed: [{ name: 'MIT License' }], exceptions: [{ purl: 'pkg:npm/myinternallib' }] }
          end

          it { is_expected.to be_valid }
        end
      end

      context 'with both denied and allowed (mutually exclusive)' do
        let(:content) do
          { denied: [{ name: 'MIT License' }], allowed: [{ name: 'Apache License 2.0' }] }
        end

        it { is_expected.to be_invalid }
      end

      context 'with neither denied nor allowed' do
        let(:content) { {} }

        it { is_expected.to be_invalid }
      end

      context 'with empty denied list' do
        let(:content) { { denied: [] } }

        it { is_expected.to be_invalid }
      end

      context 'with denied license missing name' do
        let(:content) { { denied: [{}] } }

        it { is_expected.to be_invalid }
      end

      context 'with exception missing pkg: prefix' do
        let(:content) do
          { denied: [{ name: 'MIT License' }], exceptions: [{ purl: 'npm/myinternallib' }] }
        end

        it { is_expected.to be_invalid }
      end

      context 'with additional unknown property' do
        let(:content) { { denied: [{ name: 'MIT License' }], unknown: 'value' } }

        it { is_expected.to be_invalid }
      end
    end

    describe 'malicious rule content' do
      subject(:rule) do
        build(:dependency_firewall_policy_rule,
          type: described_class.types[:malicious],
          content: content)
      end

      context 'with denied is_malicious flag' do
        let(:content) { { denied: [{ is_malicious: true }] } }

        it { is_expected.to be_valid }
      end

      context 'with allowed (not permitted for malicious rules)' do
        let(:content) { { allowed: [{ is_malicious: true }] } }

        it { is_expected.to be_invalid }
      end

      context 'with is_malicious set to false' do
        let(:content) { { denied: [{ is_malicious: false }] } }

        it { is_expected.to be_invalid }
      end

      context 'with denied item shaped as license (missing is_malicious)' do
        let(:content) { { denied: [{ name: 'MIT License' }] } }

        it { is_expected.to be_invalid }
      end

      context 'with neither denied nor allowed' do
        let(:content) { {} }

        it { is_expected.to be_invalid }
      end
    end

    describe 'risk_severity rule content' do
      subject(:rule) do
        build(:dependency_firewall_policy_rule,
          type: described_class.types[:risk_severity],
          content: content)
      end

      # The exhaustive content cases live in the shared examples for the schema itself. These two
      # only prove that `typed_content` resolves the risk_severity schema for this rule type.
      context 'with a denied count per severity' do
        let(:content) { { denied: [{ severity: 'critical', threshold: 0 }, { severity: 'high', threshold: 10 }] } }

        it { is_expected.to be_valid }
      end

      context 'with neither denied nor allowed' do
        let(:content) { {} }

        it { is_expected.to be_invalid }
      end
    end

    describe 'package_version rule content' do
      subject(:rule) do
        build(:dependency_firewall_policy_rule,
          type: described_class.types[:package_version],
          content: content)
      end

      # The exhaustive content cases live in the shared examples for the schema itself. These two
      # only prove that `typed_content` resolves the package_version schema for this rule type.
      context 'with denied name and version' do
        let(:content) { { denied: [{ name: 'lodash', version: '4.17.20' }] } }

        it { is_expected.to be_valid }
      end

      context 'with neither denied nor allowed' do
        let(:content) { {} }

        it { is_expected.to be_invalid }
      end
    end
  end
end
