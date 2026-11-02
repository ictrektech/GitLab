# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::PreventedStats::ClickHouseCollector, :click_house, :freeze_time,
  feature_category: :dependency_firewall do
  include ClickHouseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:outside_project) { create(:project) }

  let(:from) { 7.days.ago }

  def collect(container)
    described_class.new(container: container, from: from).counts
  end

  def postgresql_counts(container)
    Security::DependencyFirewall::PreventedStats::PostgresqlCollector
      .new(container: container, from: from).counts
  end

  # PostgresqlCollector is project-only; groups are compared with the query-time model methods.
  def group_query_time_counts(container)
    model = Security::DependencyFirewallPreventedPackage
    projects = container.all_projects
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

  def insert_to_siphon(rows, replicated_at: Time.current, deleted: false)
    result = clickhouse_fixture(:siphon_dependency_firewall_prevented_packages, rows.map do |row|
      {
        id: row.id,
        project_id: row.project_id,
        first_seen_at: row.first_seen_at,
        last_blocked_at: row.last_blocked_at,
        last_warned_at: row.last_warned_at,
        created_at: row.created_at,
        updated_at: row.updated_at,
        rule_type: Security::DependencyFirewallPreventedPackage.rule_types[row.rule_type],
        severity: row.severity && Security::DependencyFirewallPreventedPackage.severities[row.severity],
        identifier: row.identifier,
        traversal_path: row.project.project_namespace.traversal_path(with_organization: true),
        _siphon_replicated_at: replicated_at,
        _siphon_deleted: deleted
      }
    end)

    expect(result).to be(true)
  end

  context 'with no replicated rows' do
    it 'returns zeroed counts' do
      expect(collect(group)).to eq(
        vulnerabilities: { prevented: 0, by_severity: {} },
        malicious: { prevented: 0, warned_only: 0 },
        license: { prevented: 0, warned_only: 0 }
      )
    end
  end

  context 'with replicated ledger rows across the hierarchy' do
    before do
      create(:dependency_firewall_prevented_package, project: project,
        identifier: 'pkg:npm/lic-a@1', last_blocked_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, project: subgroup_project,
        identifier: 'pkg:npm/lic-a@1', last_blocked_at: 2.days.ago)
      create(:dependency_firewall_prevented_package, :warned_only, project: subgroup_project,
        identifier: 'pkg:npm/lic-b@1', last_warned_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, project: project,
        identifier: 'pkg:npm/lic-old@1', first_seen_at: 30.days.ago, last_blocked_at: 30.days.ago)

      create(:dependency_firewall_prevented_package, :malicious, project: project,
        identifier: 'pkg:npm/mal-a@1', last_blocked_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, :malicious, project: subgroup_project,
        identifier: 'pkg:npm/mal-b@1', last_blocked_at: 1.day.ago, last_warned_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, :malicious, :warned_only, project: subgroup_project,
        identifier: 'pkg:npm/mal-c@1', last_warned_at: 1.day.ago)
      # Blocked before the window and warned inside it: warned only for this window.
      create(:dependency_firewall_prevented_package, :malicious, project: project,
        identifier: 'pkg:npm/mal-blocked-earlier@1', last_blocked_at: 20.days.ago, last_warned_at: 1.day.ago)

      create(:dependency_firewall_prevented_package, :risk_severity, project: project,
        identifier: 'pkg:npm/vuln-a@1', severity: :high, last_blocked_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, :risk_severity, project: subgroup_project,
        identifier: 'pkg:npm/vuln-a@1', severity: :critical, last_blocked_at: 1.day.ago)
      create(:dependency_firewall_prevented_package, :risk_severity, project: subgroup_project,
        identifier: 'pkg:npm/vuln-b@1', severity: nil, last_blocked_at: 1.day.ago)
      # An explicit unknown next to a NULL severity: both land in the 'unknown' bucket.
      create(:dependency_firewall_prevented_package, :risk_severity, project: subgroup_project,
        identifier: 'pkg:npm/vuln-c@1', severity: :unknown, last_blocked_at: 1.day.ago)

      create(:dependency_firewall_prevented_package, project: outside_project,
        identifier: 'pkg:npm/other@1', last_blocked_at: 1.day.ago)

      insert_to_siphon(Security::DependencyFirewallPreventedPackage.all)
    end

    it 'aggregates distinct packages across the whole group hierarchy' do
      expect(collect(group)).to eq(
        vulnerabilities: {
          prevented: 3,
          by_severity: { 'critical' => 1, 'unknown' => 2 }
        },
        malicious: { prevented: 2, warned_only: 2 },
        license: { prevented: 1, warned_only: 1 }
      )
    end

    it 'scopes to a single project when given one' do
      expect(collect(project)).to eq(
        vulnerabilities: {
          prevented: 1,
          by_severity: { 'high' => 1 }
        },
        malicious: { prevented: 1, warned_only: 1 },
        license: { prevented: 1, warned_only: 0 }
      )
    end

    # The ClickHouse and PostgreSQL reads must be interchangeable behind the rollout flag.
    it 'returns numbers identical to the PostgreSQL reads', :aggregate_failures do
      expect(collect(project)).to eq(postgresql_counts(project))
      expect(collect(subgroup_project)).to eq(postgresql_counts(subgroup_project))
      expect(collect(group)).to eq(group_query_time_counts(group))
      expect(collect(subgroup)).to eq(group_query_time_counts(subgroup))
    end

    it 'accepts a from that is not a stored summary window', :aggregate_failures do
      create(:dependency_firewall_prevented_package, project: project,
        identifier: 'pkg:npm/lic-ten@1', last_blocked_at: 10.days.ago)
      insert_to_siphon(Security::DependencyFirewallPreventedPackage.all)

      [3, 10, 45].each do |days|
        window_start = days.days.ago.beginning_of_day
        counts = described_class.new(container: group, from: window_start).counts

        expect(counts[:license][:prevented]).to eq(
          Security::DependencyFirewallPreventedPackage.distinct_blocked_count(
            projects: group.all_projects, rule_types: 'license', from: window_start
          )
        )
      end
    end
  end

  context 'with multiple replicated versions of the same row' do
    let(:row) do
      create(:dependency_firewall_prevented_package, project: project,
        identifier: 'pkg:npm/lic-a@1', last_blocked_at: 20.days.ago)
    end

    it 'counts the row once its latest version moves into the window' do
      insert_to_siphon([row], replicated_at: 1.hour.ago)
      row.update!(last_blocked_at: 1.day.ago)
      insert_to_siphon([row], replicated_at: Time.current)

      expect(collect(project)[:license][:prevented]).to eq(1)
    end

    it 'honours an update that moves the row out of the window' do
      row.update!(last_blocked_at: 1.day.ago)
      insert_to_siphon([row], replicated_at: 1.hour.ago)
      # An anomalous but possible backwards move (e.g. manual data fix) must win as latest state.
      row.update!(last_blocked_at: 20.days.ago)
      insert_to_siphon([row], replicated_at: Time.current)

      expect(collect(project)[:license][:prevented]).to eq(0)
    end

    it 'excludes a row whose latest version is a delete', :aggregate_failures do
      row.update!(last_blocked_at: 1.day.ago)
      insert_to_siphon([row], replicated_at: 1.hour.ago)
      expect(collect(project)[:license][:prevented]).to eq(1)

      insert_to_siphon([row], replicated_at: Time.current, deleted: true)
      expect(collect(project)[:license][:prevented]).to eq(0)
    end
  end
end
