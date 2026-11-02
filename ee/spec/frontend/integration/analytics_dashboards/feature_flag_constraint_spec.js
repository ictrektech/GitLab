import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText, waitForElement, within } from 'ee_jest/integration/helpers/test_helpers';
import {
  getDashboards,
  getSystemDashboard,
} from 'ee_jest/integration/analytics_dashboards/fixture_variants';
import {
  dashboardsResponse,
  systemDashboardResponse,
} from 'ee_jest/integration/analytics_dashboards/handlers';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  DAP_IMPACT_SLUG,
  DAP_IMPACT_VIEWS,
  findDashboardFilters,
  findDashboardListLink,
  findDashboardTitle,
  findNotFound,
  findViewTabTitles,
  mountAnalyticsDashboard,
  mountAnalyticsDashboardsList,
} from './test_setup';

// DAP Impact is gated by `constraints.feature_flag: dap_impact_v1`.
const { title: DAP_IMPACT_TITLE } = systemDashboardResponse.data.customSystemDashboard.config;
const { name: OTHER_DASHBOARD_NAME } = dashboardsResponse.data.customDashboards.nodes.find(
  ({ slug }) => slug !== DAP_IMPACT_SLUG,
);

describe('Dashboard feature flag constraint', () => {
  describe('on the dashboards list', () => {
    it('shows the dashboard when the flag is on', async () => {
      mountAnalyticsDashboardsList();

      const link = await waitForElement(() => findDashboardListLink(DAP_IMPACT_TITLE));

      expect(link.getAttribute('href')).toBe(`/explore/analytics_dashboards/${DAP_IMPACT_SLUG}`);
    });

    it.each([
      ['the flag is off', 'featureFlagDisabled'],
      ['the flag is only on for a group the user is not in', 'notInGroup'],
    ])('hides the dashboard when %s', async (_, variant) => {
      setQueryVariant(getDashboards)[variant]();
      mountAnalyticsDashboardsList();

      await waitForElement(() => findDashboardListLink(OTHER_DASHBOARD_NAME));

      expect(findDashboardListLink(DAP_IMPACT_TITLE)).toBe(null);
    });
  });

  describe('on the dashboard page', () => {
    it('shows the dashboard when the flag is on for a group the user is in', async () => {
      setQueryVariant(getSystemDashboard).inGroup();
      mountAnalyticsDashboard(DAP_IMPACT_SLUG);

      await waitForElement(() => findDashboardTitle(DAP_IMPACT_TITLE));

      expect(findViewTabTitles()).toEqual(DAP_IMPACT_VIEWS.map(({ title }) => title));
      expect(findNotFound()).toBe(null);
    });

    it.each([
      ['the flag is off', 'featureFlagDisabled'],
      ['the flag is only on for a group the user is not in', 'notInGroup'],
    ])('shows not found when %s', async (_, variant) => {
      const captureException = jest.spyOn(Sentry, 'captureException');

      setQueryVariant(getSystemDashboard)[variant]();
      mountAnalyticsDashboard(DAP_IMPACT_SLUG);

      const notFound = await waitForElement(findNotFound);

      expect(getText(notFound)).toContain('Dashboard not found');
      expect(
        within(notFound)
          .getByRole('link', { name: 'View available dashboards' })
          .getAttribute('href'),
      ).toBe('/explore/analytics_dashboards');
      expect(findDashboardTitle(DAP_IMPACT_TITLE)).toBe(null);
      expect(findViewTabTitles()).toEqual([]);
      expect(findDashboardFilters()).toBe(null);
      expect(captureException).not.toHaveBeenCalled();
    });
  });
});
