# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::PreventedStats::PostgresqlCollector,
  feature_category: :dependency_firewall do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:outside_project) { create(:project) }

  let(:from) { 7.days.ago }

  def collect(container)
    described_class.new(container: container, from: from).counts
  end

  context 'with no ledger rows' do
    it 'returns zeroed counts' do
      expect(collect(project)).to eq(
        vulnerabilities: { prevented: 0, by_severity: {} },
        malicious: { prevented: 0, warned_only: 0 },
        license: { prevented: 0, warned_only: 0 }
      )
    end
  end

  context 'with ledger rows in several projects' do
    before_all do
      # Same purl in another project: not counted here.
      create(:dependency_firewall_prevented_package, project: project,
        identifier: 'pkg:npm/lic-a@1', last_blocked_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, project: subgroup_project,
        identifier: 'pkg:npm/lic-a@1', last_blocked_at: 2.days.ago)
      create(:dependency_firewall_prevented_package, :warned_only, project: subgroup_project,
        identifier: 'pkg:npm/lic-b@1', last_warned_at: 1.day.ago)
      # Blocked before the window: not prevented in it.
      create(:dependency_firewall_prevented_package, project: project,
        identifier: 'pkg:npm/lic-old@1', first_seen_at: 30.days.ago, last_blocked_at: 30.days.ago)

      create(:dependency_firewall_prevented_package, :malicious, project: project,
        identifier: 'pkg:npm/mal-a@1', last_blocked_at: 1.day.ago)
      # Warned and blocked in the window: prevented, not warned-only.
      create(:dependency_firewall_prevented_package, :malicious, project: subgroup_project,
        identifier: 'pkg:npm/mal-b@1', last_blocked_at: 1.day.ago, last_warned_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, :malicious, :warned_only, project: subgroup_project,
        identifier: 'pkg:npm/mal-c@1', last_warned_at: 1.day.ago)

      create(:dependency_firewall_prevented_package, :risk_severity, project: project,
        identifier: 'pkg:npm/vuln-a@1', severity: :critical, last_blocked_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, :risk_severity, project: project,
        identifier: 'pkg:npm/vuln-b@1', severity: nil, last_blocked_at: 1.day.ago)
      # NULL and explicit unknown severities share the 'unknown' bucket.
      create(:dependency_firewall_prevented_package, :risk_severity, project: project,
        identifier: 'pkg:npm/vuln-c@1', severity: :unknown, last_blocked_at: 1.day.ago)

      # Another group's activity must never leak in.
      create(:dependency_firewall_prevented_package, project: outside_project,
        identifier: 'pkg:npm/other@1', last_blocked_at: 1.day.ago)
    end

    it 'counts only the given project, each purl once at its severity' do
      expect(collect(project)).to eq(
        vulnerabilities: {
          prevented: 3,
          by_severity: { 'critical' => 1, 'unknown' => 2 }
        },
        malicious: { prevented: 1, warned_only: 0 },
        license: { prevented: 1, warned_only: 0 }
      )
    end

    it 'counts a package blocked before the window once it is blocked again inside it' do
      travel_to(29.days.ago) do
        create(:dependency_firewall_prevented_package, project: project,
          identifier: 'pkg:npm/lic-again@1', last_blocked_at: Time.current)
      end
      Security::DependencyFirewallPreventedPackage
        .find_by(identifier: 'pkg:npm/lic-again@1')
        .update!(last_blocked_at: 1.day.ago)

      expect(collect(project)[:license][:prevented]).to eq(2)
    end
  end
end
