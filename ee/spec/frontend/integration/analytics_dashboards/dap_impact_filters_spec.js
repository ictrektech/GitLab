import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  getAnalyticsDashboardDuoAgentPlatformTopLevelGroups,
  getAnalyticsDashboardScopeNamespace,
} from 'ee_jest/integration/analytics_dashboards/fixture_variants';
import { systemDashboardResponse } from 'ee_jest/integration/analytics_dashboards/handlers';
import {
  DAP_IMPACT_SEARCH,
  DAP_IMPACT_SLUG,
  FIXTURE_DATE_RANGE,
  GROUP_PATH,
  bootDashboard,
  findDashboardFilters,
  findDateRangeFilter,
  findNoNamespaceEmptyState,
  findPanel,
  mountAnalyticsDashboard,
  panelTitles,
  searchParam,
} from './test_setup';

const findDateRangeToggle = () =>
  findDateRangeFilter()?.querySelector('[data-testid="base-dropdown-toggle"]') ?? null;

const findDateRangeOption = (name) => {
  const filter = findDateRangeFilter();

  return filter ? within(filter).queryByRole('option', { name }) : null;
};

const { numberOfDaysLimit: DATE_RANGE_LIMIT } =
  systemDashboardResponse.data.customSystemDashboard.config.filters.dateRange;

const findDateRangeLimit = () =>
  findDateRangeFilter() ? within(findDateRangeFilter()).queryByText(/^Limited to/) : null;

const openDateRangeOption = async (text) => {
  const toggle = await waitForElement(findDateRangeToggle);

  toggle.click();
  await waitForAssertion(() => expect(toggle.getAttribute('aria-expanded')).toBe('true'));
  await waitAndClick(() => findDateRangeOption(text));
};

describe('DAP Impact dashboard filters', () => {
  describe('scope', () => {
    it('resolves the group named in the URL', async () => {
      await bootDashboard(DAP_IMPACT_SEARCH);

      expect(lastRequestVariables('getAnalyticsDashboardScopeNamespace')).toEqual({
        fullPath: GROUP_PATH,
        fullPaths: [GROUP_PATH],
      });
      expect(findNoNamespaceEmptyState()).toBe(null);
    });

    // The user has no visit history, so the default falls back to the first qualifying group.
    it('scopes the dashboard to the first qualifying group when the URL names none', async () => {
      await bootDashboard(`?${FIXTURE_DATE_RANGE}`);

      expect(searchParam('scope')).toBe(GROUP_PATH);
      expect(findNoNamespaceEmptyState()).toBe(null);
    });

    it('drops a group the user cannot analyse and asks for one instead', async () => {
      setQueryVariant(getAnalyticsDashboardScopeNamespace).noAnalyticsPermission();
      mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: DAP_IMPACT_SEARCH });

      await waitForElement(findNoNamespaceEmptyState);

      expect(lastRequestVariables('getAnalyticsDashboardScopeNamespace')).toEqual({
        fullPath: GROUP_PATH,
        fullPaths: [GROUP_PATH],
      });
      expect(panelTitles(0).filter((title) => findPanel(title))).toEqual([]);
    });
  });

  // With no qualifying group there are no panels, so the ranges below need no recorded queries.
  describe('date range', () => {
    beforeEach(() => {
      setQueryVariant(getAnalyticsDashboardDuoAgentPlatformTopLevelGroups).noneQualifying();
    });

    it('defaults to the last 30 days', async () => {
      mountAnalyticsDashboard(DAP_IMPACT_SLUG);

      await waitForAssertion(() => expect(getText(findDateRangeToggle())).toBe('Last 30 days'));
    });

    it.each([
      ['7d', 'Last 7 days'],
      ['90d', 'Last 90 days'],
    ])('shows the range from date_range=%s in the picker', async (dateRange, text) => {
      mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: `?date_range=${dateRange}` });

      await waitForAssertion(() => expect(getText(findDateRangeToggle())).toBe(text));
    });

    it('shows a custom range from the URL in the date pickers', async () => {
      mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: `?${FIXTURE_DATE_RANGE}` });

      await waitForAssertion(() => expect(getText(findDateRangeToggle())).toBe('Custom range'));

      const inputs = within(findDateRangeFilter()).queryAllByRole('textbox');

      expect(inputs.map((input) => input.value)).toEqual(['2020-06-01', '2020-06-30']);
    });

    it('writes the picked range to the URL', async () => {
      mountAnalyticsDashboard(DAP_IMPACT_SLUG);

      await openDateRangeOption('Last 7 days');

      await waitForAssertion(() => expect(searchParam('date_range')).toBe('7d'));
      expect(getText(findDateRangeToggle())).toBe('Last 7 days');
    });

    it('shows the dashboard limit once a custom range is picked', async () => {
      mountAnalyticsDashboard(DAP_IMPACT_SLUG);

      await waitForAssertion(() => expect(getText(findDateRangeToggle())).toBe('Last 30 days'));
      expect(findDateRangeLimit()).toBe(null);

      await openDateRangeOption('Custom range');

      await waitForAssertion(() =>
        expect(getText(findDateRangeLimit())).toBe(`Limited to ${DATE_RANGE_LIMIT} days`),
      );
      expect(within(findDashboardFilters()).queryAllByText('Date range')).toHaveLength(1);
    });
  });
});
