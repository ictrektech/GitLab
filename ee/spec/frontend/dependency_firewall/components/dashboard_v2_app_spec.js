import { GlLink, GlSkeletonLoader, GlCollapsibleListbox } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import { helpPagePath } from '~/helpers/help_page_helper';
import App from 'ee/dependency_firewall/components/dashboard_v2_app.vue';
import groupRuleActivityQuery from 'ee/dependency_firewall/graphql/queries/group_dependency_firewall_rule_activity.query.graphql';
import projectRuleActivityQuery from 'ee/dependency_firewall/graphql/queries/project_dependency_firewall_rule_activity.query.graphql';

Vue.use(VueApollo);

const GROUP_PATH = 'gitlab-org';
const NEW_POLICY_PATH =
  '/groups/gitlab-org/-/security/policies/new?type=dependency_firewall_policy';

const mockSummary = {
  blocked: 57,
  warned: 4,
  totalTriggers: 2148,
  vulnerabilitiesPrevented: 52,
  vulnerabilitiesPreventedBySeverity: [
    { severity: 'CRITICAL', count: 4, __typename: 'DependencyFirewallSeverityCount' },
    { severity: 'HIGH', count: 12, __typename: 'DependencyFirewallSeverityCount' },
  ],
  maliciousPackagesPrevented: 3,
  maliciousPackagesWarnedOnly: 0,
  licenseRisksPrevented: 2,
  licenseRisksWarnedOnly: 0,
  __typename: 'DependencyFirewallActivitySummary',
};

const groupSource = {
  inherited: true,
  namespace: {
    id: 'gid://gitlab/Group/1',
    fullPath: 'gitlab-org',
    name: 'Gitlab Org',
    __typename: 'Group',
  },
  __typename: 'GroupSecurityPolicySource',
};

const projectSource = {
  project: { fullPath: 'gitlab-org/df-test', __typename: 'Project' },
  __typename: 'ProjectSecurityPolicySource',
};

const buildRule = ({
  id,
  policyName,
  mode = 'ENFORCE',
  enabled = true,
  source = groupSource,
  sourceRelationship = 'DIRECT',
}) => ({
  id: `gid://gitlab/Security::DependencyFirewallPolicyRule/${id}`,
  policyName,
  mode,
  enabled,
  lastModified: { at: '2020-07-08T10:00:00Z', __typename: 'DependencyFirewallRuleLastModified' },
  source,
  sourceRelationship,
  scope: null,
  __typename: 'DependencyFirewallRuleActivity',
});

// Two rules of one policy, a direct warn-mode policy, and a disabled policy.
const mockRules = [
  buildRule({ id: 1, policyName: 'Supply chain baseline' }),
  buildRule({ id: 2, policyName: 'Supply chain baseline' }),
  buildRule({ id: 3, policyName: 'Copyleft licenses', mode: 'WARN', source: projectSource }),
  buildRule({ id: 4, policyName: 'Retired policy', enabled: false }),
];

const buildResponse = (summary = mockSummary, typename = 'Group', rules = mockRules) => ({
  data: {
    dependencyFirewall: {
      id: `gid://gitlab/${typename}/1`,
      dependencyFirewallActivitySummary: summary,
      dependencyFirewallRuleActivity: rules,
      __typename: typename,
    },
  },
});

describe('DependencyFirewallDashboardApp', () => {
  useFakeDate(2020, 6, 10); // 2020-07-10

  let wrapper;

  const createComponent = ({ handler, namespaceType = 'group', disableNewPolicy } = {}) => {
    const isProject = namespaceType === 'project';
    const query = isProject ? projectRuleActivityQuery : groupRuleActivityQuery;
    const requestHandler =
      handler ||
      jest.fn().mockResolvedValue(buildResponse(mockSummary, isProject ? 'Project' : 'Group'));
    wrapper = mountExtended(App, {
      apolloProvider: createMockApollo([[query, requestHandler]]),
      provide: { namespaceType },
      propsData: {
        fullPath: GROUP_PATH,
        namespaceType,
        newPolicyPath: NEW_POLICY_PATH,
        disableNewPolicy,
      },
    });
  };

  const findTable = () => wrapper.findComponentByTestId('dependency-firewall-policies-table');
  const findRows = () => findTable().findAll('tbody tr');
  const findNewPolicyButton = () => wrapper.findByTestId('new-policy-button');
  const findSkeletonLoaders = () => wrapper.findAllComponents(GlSkeletonLoader);
  const findBanner = () => wrapper.findComponentByTestId('ga-billing-alert');
  const findErrorAlert = () => wrapper.findByTestId('error-alert');
  const findTimeWindowListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findMetricCard = (key) => wrapper.findByTestId(`metric-card-${key}`);
  const findMetricBreakdown = (key) => wrapper.findByTestId(`metric-breakdown-${key}`);
  const findActivePoliciesCount = () => wrapper.findByTestId('active-policies-count');

  it('shows skeleton loaders while the query is in flight', () => {
    createComponent();

    expect(findSkeletonLoaders().length).toBeGreaterThan(0);
  });

  describe('once loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('hides the skeleton loaders', () => {
      expect(findSkeletonLoaders()).toHaveLength(0);
    });

    it('shows the supply-chain subtitle with the namespace name interpolated', () => {
      expect(wrapper.text()).toContain(
        'Every package entering gitlab-org is evaluated against the policies in effect for its group.',
      );
    });

    it('links the new policy button to the namespace-scoped policy path', () => {
      expect(findNewPolicyButton().attributes('href')).toBe(NEW_POLICY_PATH);
    });
  });

  describe('when the user cannot create or modify policies', () => {
    beforeEach(async () => {
      createComponent({ disableNewPolicy: true });
      await waitForPromises();
    });

    it('hides the new policy button', () => {
      expect(findNewPolicyButton().exists()).toBe(false);
    });
  });

  describe('metric cards', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders a card with title and value for each metric from the GraphQL response', () => {
      expect(findMetricCard('packageEvaluations').text()).toContain('Package evaluations');
      expect(findMetricCard('packageEvaluations').text()).toContain('2,148');

      expect(findMetricCard('vulnerabilitiesPrevented').text()).toContain(
        'Vulnerabilities prevented',
      );
      expect(findMetricCard('vulnerabilitiesPrevented').text()).toContain('52');

      expect(findMetricCard('maliciousPackagesPrevented').text()).toContain(
        'Malicious packages prevented',
      );
      expect(findMetricCard('maliciousPackagesPrevented').text()).toContain('3');

      expect(findMetricCard('licenseRisksPrevented').text()).toContain('License risks prevented');
      expect(findMetricCard('licenseRisksPrevented').text()).toContain('2');
    });

    it('renders the breakdown items for the package evaluations card', () => {
      expect(findMetricBreakdown('blocked').text()).toContain('57');
      expect(findMetricBreakdown('blocked').text()).toContain('Blocked');
      expect(findMetricBreakdown('warned').text()).toContain('4');
      expect(findMetricBreakdown('warned').text()).toContain('Warned');
    });

    it('renders the severity breakdown returned by the query, lowercased for the label lookup', () => {
      expect(findMetricBreakdown('critical').text()).toContain('4');
      expect(findMetricBreakdown('critical').text()).toContain('Critical');
      expect(findMetricBreakdown('high').text()).toContain('12');
      expect(findMetricBreakdown('high').text()).toContain('High');
    });
  });

  describe('with other severities and large counts', () => {
    beforeEach(async () => {
      const summary = {
        ...mockSummary,
        blocked: 1234,
        vulnerabilitiesPreventedBySeverity: [
          { severity: 'MEDIUM', count: 3, __typename: 'DependencyFirewallSeverityCount' },
        ],
      };
      createComponent({ handler: jest.fn().mockResolvedValue(buildResponse(summary)) });
      await waitForPromises();
    });

    it('shows only Critical and High, defaulting missing ones to 0', () => {
      expect(findMetricBreakdown('critical').text()).toContain('0');
      expect(findMetricBreakdown('high').text()).toContain('0');
      expect(findMetricBreakdown('medium').exists()).toBe(false);
    });

    it('formats breakdown counts with thousands separators', () => {
      expect(findMetricBreakdown('blocked').text()).toContain('1,234');
    });
  });

  describe('at project level', () => {
    beforeEach(async () => {
      createComponent({ namespaceType: 'project' });
      await waitForPromises();
    });

    it('shows the project-scoped subtitle', () => {
      expect(wrapper.text()).toContain(
        'Every package entering gitlab-org is evaluated against the policies in effect for its project.',
      );
    });

    it('queries the project-level GraphQL field and renders its metrics', () => {
      expect(findMetricCard('vulnerabilitiesPrevented').text()).toContain('52');
    });
  });

  describe('active policies table', () => {
    const findRow = (index) => findRows().at(index);

    beforeEach(async () => {
      createComponent({ namespaceType: 'project' });
      await waitForPromises();
    });

    it('renders the column headers', () => {
      const headers = findTable()
        .findAll('th')
        .wrappers.map((th) => th.text());

      expect(headers).toEqual(['Policy Name', 'Source', 'Scope', 'Mode', 'Last Updated']);
    });

    it('shows one row per enabled policy, merging its rules', () => {
      expect(findActivePoliciesCount().text()).toBe('2');
      expect(findRows()).toHaveLength(2);
      expect(findTable().text()).not.toContain('Retired policy');
    });

    it('links an inherited policy to the group it comes from', () => {
      expect(findRow(0).text()).toContain('Supply chain baseline');
      expect(findRow(0).text()).toContain('Inherited from Gitlab Org');
      expect(findRow(0).findComponent(GlLink).attributes('href')).toMatch(
        /\/groups\/gitlab-org\/-\/security\/policies$/,
      );
      expect(findRow(0).text()).toContain('Blocking');
    });

    it('labels a policy defined on the project', () => {
      expect(findRow(1).text()).toContain('Copyleft licenses');
      expect(findRow(1).text()).toContain('This project');
      expect(findRow(1).text()).toContain('Warning');
    });

    it('renders the scope and last updated time for each policy', () => {
      expect(wrapper.findAllByTestId('default-text').wrappers.map((w) => w.text())).toEqual([
        'This project',
        'This project',
      ]);
      expect(wrapper.findAllComponents(TimeAgoTooltip)).toHaveLength(2);
    });
  });

  describe('active policies table at group level', () => {
    const subgroupSource = {
      ...groupSource,
      inherited: false,
      namespace: {
        ...groupSource.namespace,
        id: 'gid://gitlab/Group/2',
        fullPath: 'gitlab-org/sub',
        name: 'Sub',
      },
    };
    const directGroupSource = { ...groupSource, inherited: false };

    const findRow = (index) => findRows().at(index);

    beforeEach(async () => {
      const rules = [
        buildRule({
          id: 1,
          policyName: 'Project policy',
          source: projectSource,
          sourceRelationship: 'DESCENDANT',
        }),
        buildRule({
          id: 2,
          policyName: 'Subgroup policy',
          source: subgroupSource,
          sourceRelationship: 'DESCENDANT',
        }),
        buildRule({ id: 3, policyName: 'Group policy', source: directGroupSource }),
      ];
      createComponent({
        handler: jest.fn().mockResolvedValue(buildResponse(mockSummary, 'Group', rules)),
      });
      await waitForPromises();
    });

    it('labels a policy defined in a descendant project with its path', () => {
      expect(findRow(0).text()).toContain('Defined in gitlab-org/df-test');
      expect(findRow(0).findComponent(GlLink).attributes('href')).toMatch(
        /\/gitlab-org\/df-test\/-\/security\/policies$/,
      );
    });

    it('labels a policy defined in a descendant subgroup with its path', () => {
      expect(findRow(1).text()).toContain('Defined in gitlab-org/sub');
      expect(findRow(1).findComponent(GlLink).attributes('href')).toMatch(
        /\/groups\/gitlab-org\/sub\/-\/security\/policies$/,
      );
    });

    it('labels a policy defined on the group itself', () => {
      expect(findRow(2).text()).toContain('This group');
    });
  });

  describe.each`
    sourceType   | source
    ${'project'} | ${{ ...projectSource, project: null }}
    ${'group'}   | ${{ ...groupSource, inherited: false, namespace: null }}
  `('when the descendant $sourceType is not readable', ({ source }) => {
    beforeEach(async () => {
      const rules = [
        buildRule({ id: 1, policyName: 'Hidden policy', source, sourceRelationship: 'DESCENDANT' }),
      ];
      createComponent({
        handler: jest.fn().mockResolvedValue(buildResponse(mockSummary, 'Group', rules)),
      });
      await waitForPromises();
    });

    it('labels the policy as defined below the group without a link', () => {
      expect(findRows().at(0).text()).toContain('Defined in a subgroup or project');
      expect(findRows().at(0).findComponent(GlLink).exists()).toBe(false);
    });
  });

  describe('when there are no policies', () => {
    beforeEach(async () => {
      createComponent({
        namespaceType: 'project',
        handler: jest.fn().mockResolvedValue(buildResponse(mockSummary, 'Project', [])),
      });
      await waitForPromises();
    });

    it('renders the empty state', () => {
      expect(findTable().text()).toContain('No active dependency firewall policies');
    });
  });

  describe('when policy names contain slashes', () => {
    const subgroupSource = {
      ...groupSource,
      namespace: {
        ...groupSource.namespace,
        id: 'gid://gitlab/Group/2',
        fullPath: 'gitlab-org/team',
      },
    };

    beforeEach(async () => {
      const rules = [
        buildRule({ id: 1, policyName: 'team/baseline' }),
        buildRule({ id: 2, policyName: 'baseline', source: subgroupSource }),
      ];
      createComponent({
        namespaceType: 'project',
        handler: jest.fn().mockResolvedValue(buildResponse(mockSummary, 'Project', rules)),
      });
      await waitForPromises();
    });

    it('keeps policies apart when source path and name would join to the same string', () => {
      expect(findRows()).toHaveLength(2);
    });
  });

  describe('when the prevented fields are null', () => {
    beforeEach(async () => {
      const summary = {
        ...mockSummary,
        vulnerabilitiesPrevented: null,
        vulnerabilitiesPreventedBySeverity: null,
        maliciousPackagesPrevented: null,
        maliciousPackagesWarnedOnly: null,
        licenseRisksPrevented: null,
        licenseRisksWarnedOnly: null,
      };
      createComponent({
        namespaceType: 'project',
        handler: jest.fn().mockResolvedValue(buildResponse(summary, 'Project')),
      });
      await waitForPromises();
    });

    it('renders them as 0, with 0 Critical and 0 High', () => {
      expect(findErrorAlert().exists()).toBe(false);
      expect(findMetricCard('vulnerabilitiesPrevented').text()).toContain('0');
      expect(findMetricCard('maliciousPackagesPrevented').text()).toContain('0');
      expect(findMetricCard('licenseRisksPrevented').text()).toContain('0');
      expect(findMetricBreakdown('critical').text()).toContain('0 Critical');
      expect(findMetricBreakdown('high').text()).toContain('0 High');
      expect(findMetricCard('packageEvaluations').text()).toContain('2,148');
    });
  });

  describe('when the query fails', () => {
    beforeEach(async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('boom')) });
      await waitForPromises();
    });

    it('shows an error alert', () => {
      expect(findErrorAlert().exists()).toBe(true);
    });
  });

  describe('when the query fails then a window change triggers a successful refetch', () => {
    beforeEach(async () => {
      const handler = jest
        .fn()
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValue(buildResponse());
      createComponent({ handler });
      await waitForPromises();
    });

    it('clears the error alert', async () => {
      expect(findErrorAlert().exists()).toBe(true);

      // Default window is 30 days, so re-selecting the same value wouldn't change the
      // query variables (and wouldn't trigger a refetch) — pick a different value.
      findTimeWindowListbox().vm.$emit('select', 7);
      await waitForPromises();

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('GitLab credits banner', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a non-dismissible warning banner about credits at GA', () => {
      expect(findBanner().props('variant')).toBe('warning');
      expect(findBanner().props('dismissible')).toBe(false);
      expect(findBanner().props('title')).toBe('Charges may be incurred at the end of beta');
      expect(findBanner().text()).toContain('free during the beta period');
      expect(findBanner().findComponent(GlLink).text()).toBe('GitLab Credits');
    });

    it('links to the GitLab credits documentation', () => {
      expect(findBanner().findComponent(GlLink).attributes('href')).toBe(
        helpPagePath('subscriptions/gitlab_credits'),
      );
    });
  });

  describe('time window', () => {
    it('labels the dropdown with a screen-reader-only "Time period" label', () => {
      createComponent();

      const labelledBy = findTimeWindowListbox().props('toggleAriaLabelledBy');
      const label = wrapper.find(`#${labelledBy}`);

      expect(label.classes()).toContain('gl-sr-only');
      expect(label.text()).toBe('Time period');
    });

    it('defaults to the last 30 days when querying', () => {
      const handler = jest.fn().mockResolvedValue(buildResponse());
      createComponent({ handler });

      expect(handler).toHaveBeenCalledWith({
        fullPath: GROUP_PATH,
        from: '2020-06-11',
        includeAttributeScopes: false,
      });
    });

    it('refetches with 2020-07-04 when "Last 7 days" is selected', async () => {
      const handler = jest.fn().mockResolvedValue(buildResponse());
      createComponent({ handler });
      await waitForPromises();

      findTimeWindowListbox().vm.$emit('select', 7);
      await waitForPromises();

      expect(handler).toHaveBeenLastCalledWith({
        fullPath: GROUP_PATH,
        from: '2020-07-04',
        includeAttributeScopes: false,
      });
    });

    it('refetches with 2020-06-11 when returning to "Last 30 days" from a different window', async () => {
      // 30 days is the default, so selecting it from the initial mount wouldn't change the
      // query variables and wouldn't trigger a refetch — select 7 first to force a real change.
      const handler = jest.fn().mockResolvedValue(buildResponse());
      createComponent({ handler });
      await waitForPromises();

      findTimeWindowListbox().vm.$emit('select', 7);
      await waitForPromises();
      findTimeWindowListbox().vm.$emit('select', 30);
      await waitForPromises();

      expect(handler).toHaveBeenLastCalledWith({
        fullPath: GROUP_PATH,
        from: '2020-06-11',
        includeAttributeScopes: false,
      });
    });
  });
});
