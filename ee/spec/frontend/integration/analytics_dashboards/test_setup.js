import setWindowLocation from 'helpers/set_window_location_helper';
import {
  getText,
  registerBootstrappedApp,
  screen,
  waitForSetup,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  scopeNamespaceResponse,
  systemDashboardResponse,
} from 'ee_jest/integration/analytics_dashboards/handlers';
import initAnalyticsDashboards from '~/explore/analytics_dashboards';

const EXPLORE_ANALYTICS_DASHBOARDS_PATH = '/explore/analytics_dashboards';

// GLQL panels import their components lazily. Loading them before any test keeps that cost out
// of the first test's wait, which a busy CI runner can push past the timeout.
beforeAll(() =>
  Promise.all([
    import('~/explore/analytics_dashboards/components/visualizations/glql.vue'),
    import('~/explore/analytics_dashboards/data_sources/glql'),
  ]),
);

// Panels write the dashboard's date range into their GLQL queries, and the recorded
// responses are keyed by those queries, so specs that render panels pin this range.
export const FIXTURE_DATE_RANGE = 'date_range=custom&start_date=2020-06-01&end_date=2020-06-30';

export const DAP_IMPACT_SLUG = 'dap_impact';

export const { views: DAP_IMPACT_VIEWS } =
  systemDashboardResponse.data.customSystemDashboard.config;

export const { fullPath: GROUP_PATH, name: GROUP_NAME } = scopeNamespaceResponse.data.group;

export const DAP_IMPACT_SEARCH = `?scope=${GROUP_PATH}&${FIXTURE_DATE_RANGE}`;

export const panelTitles = (viewIndex) =>
  DAP_IMPACT_VIEWS[viewIndex].panels.filter((panel) => !panel.section).map(({ title }) => title);

function mountExploreAnalyticsDashboards(url) {
  setWindowLocation(url);

  const el = document.createElement('div');
  el.id = 'js-explore-analytics-dashboards';
  el.dataset.exploreAnalyticsDashboardsPath = EXPLORE_ANALYTICS_DASHBOARDS_PATH;
  el.dataset.dataSourceClickhouse = 'true';
  document.body.appendChild(el);

  return registerBootstrappedApp(initAnalyticsDashboards());
}

export const mountAnalyticsDashboard = (slug, { search = '' } = {}) =>
  mountExploreAnalyticsDashboards(`${EXPLORE_ANALYTICS_DASHBOARDS_PATH}/${slug}${search}`);

export const mountAnalyticsDashboardsList = () =>
  mountExploreAnalyticsDashboards(EXPLORE_ANALYTICS_DASHBOARDS_PATH);

export const findDashboardListLink = (name) =>
  screen.queryAllByTestId('dashboard-redirect-link').find((link) => getText(link) === name) ?? null;

export const findViewTabs = () => {
  const views = screen.queryByTestId('dashboard-views');

  return views ? within(views).queryAllByRole('tab') : [];
};

export const findViewTabTitles = () => findViewTabs().map((tab) => getText(tab));

export const findViewTab = (title) => findViewTabs().find((tab) => getText(tab) === title) ?? null;

export const findDashboardTitle = (title) => screen.queryByRole('heading', { name: title });

export const findDashboardFilters = () => screen.queryByTestId('dashboard-filters');

export const findDateRangeFilter = () => screen.queryByTestId('dashboard-filters-date-range');

export const findSection = (title) =>
  screen.queryByTestId(`section-${title.toLowerCase().replaceAll(' ', '-')}`);

export const findNoNamespaceEmptyState = () => screen.queryByTestId('no-namespace-empty-state');

export const findNoQualifyingGroupsEmptyState = () =>
  screen.queryByTestId('no-qualifying-groups-empty-state');

export const findNotFound = () => screen.queryByTestId('dashboard-not-found');

export const findLoadErrorAlert = () =>
  screen.queryByText('Failed to load dashboard. Please try again.');

// Matched on the title's own text, since some titles are prefixes of others.
export const findPanel = (title) =>
  screen
    .queryAllByTestId('panel-title')
    .find((titleElement) => within(titleElement).queryByText(title, { exact: true }))
    ?.closest('[id]') ?? null;

export const searchParam = (name) => new URLSearchParams(window.location.search).get(name);

export const expectPanels = (titles) =>
  titles.forEach((title) => expect(findPanel(title)).not.toBe(null));

// Mounting and booting the dashboard is setup, so it runs on the setup budget.
export const bootDashboard = async (search, viewIndex = 0) => {
  mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search });

  await waitForSetup(() => expectPanels(panelTitles(viewIndex)));
};

export const findPanelFooterLink = (title) =>
  findPanel(title)?.querySelector('[data-testid="panel-footer-dashboard-view-link"]') ?? null;

// A GLQL panel body is empty until its query starts, then shows a skeleton until it resolves.
// Panels with a footer wrap the body, so the footer is left out.
export const isPanelLoaded = (title) => {
  const panel = findPanel(title);
  const body =
    panel?.querySelector('[data-testid="panel-body-content"]') ??
    panel?.querySelector('[data-testid="panel-title"] + *');

  return Boolean(body && getText(body)) && !body.querySelector('.gl-skeleton-loader');
};

const FAILED_PANEL_STATES = [
  'error',
  'error-no-retry',
  'no-access',
  'unavailable',
  'not-configured',
];

export const findFailedPanelStates = (panel) =>
  FAILED_PANEL_STATES.filter((state) =>
    panel.querySelector(`[data-testid="panel-state-${state}"]`),
  );
