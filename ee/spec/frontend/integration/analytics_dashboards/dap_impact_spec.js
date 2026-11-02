import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  getAnalyticsDashboardDuoAgentPlatformTopLevelGroups,
  getSystemDashboard,
} from 'ee_jest/integration/analytics_dashboards/fixture_variants';
import {
  dashboardsResponse,
  systemDashboardResponse,
} from 'ee_jest/integration/analytics_dashboards/handlers';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { getText, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import {
  DAP_IMPACT_SLUG,
  DAP_IMPACT_VIEWS,
  FIXTURE_DATE_RANGE,
  findDashboardFilters,
  findDashboardListLink,
  findDashboardTitle,
  findLoadErrorAlert,
  findNoQualifyingGroupsEmptyState,
  findNotFound,
  findViewTabTitles,
  mountAnalyticsDashboard,
  mountAnalyticsDashboardsList,
} from './test_setup';

const { title: DASHBOARD_TITLE } = systemDashboardResponse.data.customSystemDashboard.config;
const { name: OTHER_DASHBOARD_NAME } = dashboardsResponse.data.customDashboards.nodes.find(
  ({ slug }) => slug !== DAP_IMPACT_SLUG,
);

describe('DAP Impact dashboard', () => {
  let captureException;

  beforeEach(() => {
    captureException = jest.spyOn(Sentry, 'captureException');
  });

  describe('when the dashboard is available to the user', () => {
    beforeEach(() => {
      // The picker defaults to the user's qualifying group, so its panels need recorded dates.
      mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: `?${FIXTURE_DATE_RANGE}` });
    });

    it('renders the dashboard and its views', async () => {
      await waitForElement(() => findDashboardTitle(DASHBOARD_TITLE));

      expect(lastRequestVariables('getSystemDashboard')).toEqual({ slug: DAP_IMPACT_SLUG });
      expect(findViewTabTitles()).toEqual(DAP_IMPACT_VIEWS.map(({ title }) => title));
      expect(findDashboardFilters()).not.toBe(null);
      expect(findNotFound()).toBe(null);
    });
  });

  describe('when the user has no qualifying group', () => {
    beforeEach(() => {
      setQueryVariant(getAnalyticsDashboardDuoAgentPlatformTopLevelGroups).noneQualifying();
    });

    it('leaves the dashboard out of the list', async () => {
      mountAnalyticsDashboardsList();

      await waitForElement(() => findDashboardListLink(OTHER_DASHBOARD_NAME));

      expect(findDashboardListLink(DASHBOARD_TITLE)).toBe(null);
    });

    describe('when the dashboard is opened by URL', () => {
      beforeEach(() => {
        mountAnalyticsDashboard(DAP_IMPACT_SLUG);
      });

      it('explains why there is nothing to show, rather than rendering any panel', async () => {
        const emptyState = await waitForElement(findNoQualifyingGroupsEmptyState);

        expect(getText(emptyState)).toContain('No groups available');
        expect(getText(document.body)).not.toContain(DAP_IMPACT_VIEWS[0].panels[0].title);
      });

      it('loads without reporting an error', async () => {
        await waitForElement(findNoQualifyingGroupsEmptyState);

        expect(findLoadErrorAlert()).toBe(null);
        expect(captureException).not.toHaveBeenCalled();
      });
    });
  });

  describe('when the dashboard fails to load', () => {
    beforeEach(() => {
      setQueryVariant(getSystemDashboard).error();

      mountAnalyticsDashboard(DAP_IMPACT_SLUG);
    });

    it('shows an error in place of the dashboard and reports it', async () => {
      await waitForElement(findLoadErrorAlert);

      expect(findDashboardTitle(DASHBOARD_TITLE)).toBe(null);
      expect(captureException).toHaveBeenCalled();
    });
  });
});
