# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::PreventedStats::GroupRefreshService, feature_category: :dependency_firewall do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project_a) { create(:project, group: group) }
  let_it_be(:project_b) { create(:project, group: group) }
  let_it_be(:project_c) { create(:project, group: subgroup) }

  let(:model) { Security::DependencyFirewallPreventedPackage }
  let(:stats) { Security::DependencyFirewallNamespacePreventedStat }

  around do |example|
    freeze_time { example.run }
  end

  def create_row(project, *traits, **attrs)
    create(:dependency_firewall_prevented_package, *traits, project: project, **attrs)
  end

  before do
    create_row(project_a, :malicious, identifier: 'pkg:npm/blocked-twice@1')
    create_row(project_c, :malicious, identifier: 'pkg:npm/blocked-twice@1')

    create_row(project_a, :malicious, identifier: 'pkg:npm/blocked-and-warned@1')
    create_row(project_b, :malicious, :warned_only, identifier: 'pkg:npm/blocked-and-warned@1')
    create_row(project_b, :warned_only, rule_type: :license, identifier: 'pkg:npm/license-warned@1')
    create_row(project_c, rule_type: :license, identifier: 'pkg:npm/license-blocked@1')

    create_row(project_a, :risk_severity, identifier: 'pkg:npm/both-projects@1', severity: :high)
    create_row(project_b, :risk_severity, identifier: 'pkg:npm/both-projects@1', severity: :critical)
    create_row(project_c, :risk_severity, identifier: 'pkg:npm/no-severity@1', severity: nil)
    create_row(project_c, :risk_severity, identifier: 'pkg:npm/medium@1', severity: :medium)

    create_row(project_a, :malicious, identifier: 'pkg:npm/twenty-days@1', last_blocked_at: 20.days.ago)
    create_row(project_b, :risk_severity, identifier: 'pkg:npm/twenty-days-vuln@1', severity: :low,
      last_blocked_at: 20.days.ago)
    create_row(project_a, :malicious, identifier: 'pkg:npm/forty-days@1', last_blocked_at: 40.days.ago)
    create_row(project_a, :warned_only, rule_type: :license, identifier: 'pkg:npm/warned-twenty@1',
      last_warned_at: 20.days.ago)
  end

  def query_time_counts(from)
    projects = group.all_projects
    vulnerability_types = Security::DependencyFirewall::PreventedStats::DataCollector::VULNERABILITY_RULE_TYPES
    by_severity = model.blocked_count_by_max_severity(projects: projects, rule_types: vulnerability_types, from: from)
      .each_with_object(Hash.new(0)) { |(int, count), result| result[model.severities.key(int) || 'unknown'] += count }

    {
      vulnerabilities: {
        prevented: model.distinct_blocked_count(projects: projects, rule_types: vulnerability_types, from: from),
        by_severity: by_severity
      },
      malicious: {
        prevented: model.distinct_blocked_count(projects: projects, rule_types: 'malicious', from: from),
        warned_only: model.distinct_warned_only_count(projects: projects, rule_types: 'malicious', from: from)
      },
      license: {
        prevented: model.distinct_blocked_count(projects: projects, rule_types: 'license', from: from),
        warned_only: model.distinct_warned_only_count(projects: projects, rule_types: 'license', from: from)
      }
    }
  end

  def stored_counts
    stats.where(namespace_id: group.id).to_h { |stat| [stat.window_days, stat.to_counts] }
  end

  describe '#execute' do
    it 'stores the counts the query-time group queries return, for each window' do
      described_class.new(group).execute

      expected = stats::WINDOWS.index_with { |days| query_time_counts((days - 1).days.ago.beginning_of_day) }

      expect(stored_counts).to eq(expected)
    end

    it 'stores window starts' do
      described_class.new(group).execute

      expect(stats.find_by!(namespace_id: group.id, window_days: 7).window_start).to eq(6.days.ago.to_date)
      expect(stats.find_by!(namespace_id: group.id, window_days: 30).window_start).to eq(29.days.ago.to_date)
    end

    it 'derives window starts from the UTC date when Time.zone is ahead of UTC', :aggregate_failures do
      travel_to(Time.utc(2026, 1, 1, 18, 0))
      Time.use_zone('Asia/Singapore') { described_class.new(group).execute }

      expect(stats.find_by!(namespace_id: group.id, window_days: 7).window_start).to eq(Date.new(2025, 12, 26))
      expect(stats.find_by!(namespace_id: group.id, window_days: 30).window_start).to eq(Date.new(2025, 12, 3))
    end

    it 'bounds the window queries at UTC midnight when Time.zone is ahead of UTC' do
      zoned_group = create(:group)
      zoned_project = create(:project, group: zoned_group)
      travel_to(Time.utc(2026, 1, 1, 18, 0))
      create_row(zoned_project, :malicious, identifier: 'pkg:npm/before-midnight@1',
        last_blocked_at: Time.utc(2025, 12, 25, 20, 0))
      create_row(zoned_project, :malicious, identifier: 'pkg:npm/after-midnight@1',
        last_blocked_at: Time.utc(2025, 12, 26, 1, 0))

      Time.use_zone('Asia/Singapore') { described_class.new(zoned_group).execute }

      expect(stats.find_by!(namespace_id: zoned_group.id, window_days: 7).malicious_packages_prevented).to eq(1)
    end

    it 'counts a purl blocked in one project and warned-only in another in both columns' do
      described_class.new(group).execute

      expect(stored_counts[7][:malicious]).to eq(prevented: 2, warned_only: 1)
    end

    it 'counts a purl blocked in two projects once, at its highest severity' do
      described_class.new(group).execute

      expect(stored_counts[7][:vulnerabilities]).to eq(
        prevented: 3, by_severity: { 'critical' => 1, 'medium' => 1, 'unknown' => 1 })
    end

    it 'gives the same rows with a batch size of one' do
      described_class.new(group).execute
      default_counts = stored_counts

      stats.delete_all
      described_class.new(group, batch_size: 1).execute

      expect(stored_counts).to eq(default_counts)
    end

    it 'overwrites stale counts, including with zeros' do
      create(:dependency_firewall_namespace_prevented_stat, namespace: group, window_days: 7,
        vulnerabilities_prevented: 9, severity_high: 9, malicious_packages_prevented: 9)
      Security::DependencyFirewallPreventedPackage.delete_all

      expect { described_class.new(group).execute }.to change {
        stats.where(namespace_id: group.id).count
      }.from(1).to(2)

      expect(stored_counts[7]).to eq(
        vulnerabilities: { prevented: 0, by_severity: {} },
        malicious: { prevented: 0, warned_only: 0 },
        license: { prevented: 0, warned_only: 0 })
    end

    it 'stores zero rows for a group without projects' do
      empty_group = create(:group)

      described_class.new(empty_group).execute

      expect(stats.where(namespace_id: empty_group.id).pluck(:window_days)).to contain_exactly(7, 30)
    end
  end
end
