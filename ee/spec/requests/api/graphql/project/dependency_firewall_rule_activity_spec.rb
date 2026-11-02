# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project.dependencyFirewallRuleActivity', feature_category: :dependency_firewall do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, group: group, developers: user) }
  let_it_be(:configuration) do
    create(:security_orchestration_policy_configuration, :namespace, namespace: group)
  end

  let_it_be(:policy) do
    create(:security_policy, :dependency_firewall_policy,
      security_orchestration_policy_configuration: configuration, name: 'Block GPL')
  end

  let_it_be(:rule) { create(:dependency_firewall_policy_rule, security_policy: policy) }

  let(:fields) do
    'policyName enabled blockedCount lastModified { at } ' \
      'source { ... on GroupSecurityPolicySource { inherited namespace { id name } } }'
  end

  let(:query) do
    graphql_query_for(
      :project, { full_path: project.full_path },
      query_graphql_field(:dependency_firewall_rule_activity, {}, fields)
    )
  end

  let(:current_user) { user }

  subject(:activity) do
    post_graphql(query, current_user: current_user)
    graphql_data_at(:project, :dependency_firewall_rule_activity)
  end

  before do
    stub_licensed_features(security_orchestration_policies: true, dependency_firewall: true)
  end

  it 'returns the rule with activity recorded for the project, inherited from the group' do
    create(:dependency_firewall_activity_stat,
      dependency_firewall_policy_rule: rule, project: project, outcome: :blocked, count: 7)

    expect(activity).to contain_exactly(
      a_hash_including(
        'policyName' => 'Block GPL',
        'blockedCount' => 7,
        'source' => a_hash_including(
          'inherited' => true,
          'namespace' => a_hash_including('name' => group.name)
        )
      )
    )
  end

  it 'excludes activity recorded against projects other than this one' do
    other_project = create(:project, group: group)
    create(:dependency_firewall_activity_stat,
      dependency_firewall_policy_rule: rule, project: other_project, outcome: :blocked, count: 99)

    expect(activity.first['blockedCount']).to eq(0)
  end

  it 'exposes the policy last-modified timestamp' do
    expect(activity.first.dig('lastModified', 'at')).to be_present
  end

  context 'with a disabled policy inherited from the group' do
    let_it_be(:disabled_policy) do
      create(:security_policy, :dependency_firewall_policy,
        security_orchestration_policy_configuration: configuration,
        name: 'Disabled Policy', enabled: false, policy_index: 1)
    end

    let_it_be(:disabled_rule) { create(:dependency_firewall_policy_rule, security_policy: disabled_policy) }

    it 'lists the disabled rule flagged as disabled', :aggregate_failures do
      by_name = activity.index_by { |item| item['policyName'] }

      expect(by_name['Disabled Policy']['enabled']).to be(false)
      expect(by_name['Block GPL']['enabled']).to be(true)
    end
  end

  context 'when the dependency_firewall_phase1 feature flag is disabled' do
    before do
      stub_feature_flags(dependency_firewall_phase1: false)
    end

    it { is_expected.to eq([]) }
  end

  context 'when the dependency_firewall licensed feature is unavailable' do
    before do
      stub_licensed_features(security_orchestration_policies: true, dependency_firewall: false)
    end

    it { is_expected.to eq([]) }
  end

  context 'when the user cannot read security orchestration policies' do
    let(:current_user) { create(:user) }

    it { is_expected.to be_nil }
  end

  describe 'dependencyFirewallActivitySummary call limit' do
    let_it_be(:other_project) { create(:project, group: group, developers: user) }

    let(:query) do
      <<~GQL
        query {
          first: project(fullPath: "#{project.full_path}") { dependencyFirewallActivitySummary { blocked } }
          second: project(fullPath: "#{other_project.full_path}") { dependencyFirewallActivitySummary { blocked } }
        }
      GQL
    end

    it 'can be resolved for only one project per request' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include(
        '"dependencyFirewallActivitySummary" field can be requested only for 1 Project(s) at a time.'
      )
    end
  end

  describe 'dependencyFirewallActivitySummary prevented package stats' do
    let(:prevented_fields) do
      'vulnerabilitiesPrevented vulnerabilitiesPreventedBySeverity { severity count } ' \
        'maliciousPackagesPrevented maliciousPackagesWarnedOnly ' \
        'licenseRisksPrevented licenseRisksWarnedOnly'
    end

    let(:summary_query) do
      graphql_query_for(
        :project, { full_path: project.full_path },
        query_graphql_field(:dependency_firewall_activity_summary, {}, prevented_fields)
      )
    end

    subject(:summary) do
      post_graphql(summary_query, current_user: current_user)
      graphql_data_at(:project, :dependency_firewall_activity_summary)
    end

    context 'with ledger rows in the window' do
      before do
        create(:dependency_firewall_prevented_package, project: project,
          identifier: 'pkg:npm/lic-a@1', last_blocked_at: 1.day.ago)
        create(:dependency_firewall_prevented_package, :warned_only, project: project,
          identifier: 'pkg:npm/lic-b@1', last_warned_at: 1.day.ago)
        create(:dependency_firewall_prevented_package, :malicious, project: project,
          identifier: 'pkg:npm/mal-a@1', last_blocked_at: 1.day.ago)
        create(:dependency_firewall_prevented_package, :risk_severity, project: project,
          identifier: 'pkg:npm/vuln-a@1', severity: :high, last_blocked_at: 1.day.ago)
        create(:dependency_firewall_prevented_package, :risk_severity, project: project,
          identifier: 'pkg:npm/vuln-b@1', severity: :critical, last_blocked_at: 1.day.ago)
        # Another project in the same group must not count here.
        create(:dependency_firewall_prevented_package, project: create(:project, group: group),
          identifier: 'pkg:npm/other@1', last_blocked_at: 1.day.ago)
        # Blocked before the default window starts, so it must not count.
        create(:dependency_firewall_prevented_package, project: project,
          identifier: 'pkg:npm/lic-old@1', last_blocked_at: 30.days.ago)
      end

      it 'returns distinct prevented counts for the project with the severity breakdown, most severe first' do
        expect(summary).to match(
          'vulnerabilitiesPrevented' => 2,
          'vulnerabilitiesPreventedBySeverity' => [
            { 'severity' => 'CRITICAL', 'count' => 1 },
            { 'severity' => 'HIGH', 'count' => 1 }
          ],
          'maliciousPackagesPrevented' => 1,
          'maliciousPackagesWarnedOnly' => 0,
          'licenseRisksPrevented' => 1,
          'licenseRisksWarnedOnly' => 1
        )
      end
    end

    context 'with no ledger rows' do
      it 'returns zeroes with an empty breakdown' do
        expect(summary).to eq(
          'vulnerabilitiesPrevented' => 0,
          'vulnerabilitiesPreventedBySeverity' => [],
          'maliciousPackagesPrevented' => 0,
          'maliciousPackagesWarnedOnly' => 0,
          'licenseRisksPrevented' => 0,
          'licenseRisksWarnedOnly' => 0
        )
      end
    end

    context 'when the dependency_firewall_dashboard_v2 flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_dashboard_v2: false)
        create(:dependency_firewall_prevented_package, project: project,
          identifier: 'pkg:npm/lic-a@1', last_blocked_at: 1.day.ago)
      end

      it 'returns null prevented stats despite existing ledger rows' do
        expect(summary).to eq(
          'vulnerabilitiesPrevented' => nil,
          'vulnerabilitiesPreventedBySeverity' => nil,
          'maliciousPackagesPrevented' => nil,
          'maliciousPackagesWarnedOnly' => nil,
          'licenseRisksPrevented' => nil,
          'licenseRisksWarnedOnly' => nil
        )
      end
    end
  end
end
