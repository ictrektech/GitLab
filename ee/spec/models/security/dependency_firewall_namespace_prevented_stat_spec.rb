# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewallNamespacePreventedStat, feature_category: :dependency_firewall do
  it { is_expected.to belong_to(:namespace).required }
  it { is_expected.to validate_inclusion_of(:window_days).in_array([7, 30]) }

  it 'has a severity column for every vulnerability severity level' do
    expect(described_class::SEVERITIES).to match_array(Enums::Vulnerability.severity_levels.keys)
  end

  describe '#to_counts' do
    it 'returns the collector hash shape, omitting zero severities' do
      stat = build(:dependency_firewall_namespace_prevented_stat, vulnerabilities_prevented: 3,
        severity_critical: 2, severity_high: 1, malicious_packages_prevented: 1, license_risks_warned_only: 4)

      expect(stat.to_counts).to eq(
        vulnerabilities: { prevented: 3, by_severity: { 'critical' => 2, 'high' => 1 } },
        malicious: { prevented: 1, warned_only: 0 },
        license: { prevented: 0, warned_only: 4 }
      )
    end
  end
end
