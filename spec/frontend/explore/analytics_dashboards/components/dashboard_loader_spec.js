import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlSkeletonLoader, GlAlert, GlEmptyState } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DashboardLoader from '~/explore/analytics_dashboards/components/dashboard_loader.vue';
import getDashboardQuery from '~/explore/analytics_dashboards/graphql/get_dashboard.query.graphql';
import getSystemDashboardQuery from '~/explore/analytics_dashboards/graphql/get_system_dashboard.query.graphql';
import * as sentryBrowserWrapper from '~/sentry/sentry_browser_wrapper';
import {
  mockCustomDashboard,
  mockDashboardResponse,
  mockDashboardCompactGridResponse,
  mockDashboardWithViewsResponse,
  mockInvalidSystemDashboardResponse,
  mockSystemDashboardWithPanelErrorsResponse,
  mockInvalidSystemDashboardWithViewsResponse,
  mockSystemDashboardWithNullEntriesResponse,
  mockSystemDashboardResponse,
} from '../mock_data';

Vue.use(VueApollo);

jest.mock('~/sentry/sentry_browser_wrapper');

describe('DashboardLoader', () => {
  let wrapper;

  const mockBreadcrumbState = { name: '', slug: '', update: jest.fn() };

  const mockResolvedQuery = (queryResponse = mockDashboardResponse) =>
    createMockApollo([[getDashboardQuery, jest.fn().mockResolvedValue({ data: queryResponse })]]);

  const mockResolvedSystemQuery = (queryResponse = mockSystemDashboardResponse) =>
    createMockApollo([
      [getSystemDashboardQuery, jest.fn().mockResolvedValue({ data: queryResponse })],
    ]);

  const mockRejectedQuery = () =>
    createMockApollo([
      [getDashboardQuery, jest.fn().mockRejectedValue(new Error('Network error'))],
    ]);

  const createComponent = ({ requestHandlers, routeParams = { slug: '3' }, stubs = {} } = {}) => {
    wrapper = shallowMountExtended(DashboardLoader, {
      apolloProvider: requestHandlers || mockResolvedQuery(),
      provide: {
        breadcrumbState: mockBreadcrumbState,
        exploreAnalyticsDashboardsPath: '/explore/analytics_dashboards',
      },
      mocks: { $route: { params: routeParams } },
      stubs,
      scopedSlots: {
        dashboard: `
          <div data-testid="dashboard-slot">
            <div data-testid="slot-dashboard-id">{{ props.dashboardId }}</div>
            <div data-testid="slot-config">{{ JSON.stringify(props.config) }}</div>
            <div data-testid="slot-cellHeight">{{ props.cellHeight }}</div>
            <div data-testid="slot-minCellHeight">{{ props.minCellHeight }}</div>
            <div data-testid="slot-isSystemDashboard">{{ props.isSystemDashboard }}</div>
            <div data-testid="slot-errors">{{ JSON.stringify(props.errors) }}</div>
          </div>
        `,
      },
    });
  };

  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findDashboardSlot = () => wrapper.findByTestId('dashboard-slot');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(GlEmptyState);
  const getSlotProp = (name) => {
    const value = wrapper.findByTestId(`slot-${name}`).text();
    return ['config', 'errors'].includes(name) ? JSON.parse(value) : value;
  };

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('while the query is loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('does not render the dashboard slot', () => {
      expect(findDashboardSlot().exists()).toBe(false);
    });

    it('does not emit the loaded event', () => {
      expect(wrapper.emitted('loaded')).toBeUndefined();
    });
  });

  describe('with data loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('does not render the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(false);
    });

    it('renders the dashboard slot', () => {
      expect(findDashboardSlot().exists()).toBe(true);
    });

    it('updates the breadcrumb state with the dashboard title and slug', () => {
      expect(mockBreadcrumbState.update).toHaveBeenCalledWith({
        name: 'Fake trend dashboard',
        slug: '3',
      });
    });

    it('replaces original panel ids with unique ids', () => {
      const { panels } = getSlotProp('config');

      panels.forEach((panel, idx) => {
        expect(panel.id).toBe(`panel-${idx + 1}`);
        expect(panel.id).not.toBe(`panel-original-${idx + 1}`);
      });
    });

    it('passes the dashboard ID to the slot', () => {
      expect(getSlotProp('dashboard-id')).toBe(
        'gid://gitlab/Analytics::CustomDashboards::Dashboard/3',
      );
    });

    it('passes isSystemDashboard as false to the slot for a custom dashboard', () => {
      expect(getSlotProp('isSystemDashboard')).toBe('false');
    });

    it('emits the loaded event once with the loaded dashboard', () => {
      expect(wrapper.emitted('loaded')).toHaveLength(1);
      expect(wrapper.emitted('loaded')[0][0]).toMatchObject({
        id: mockCustomDashboard.id,
        name: mockCustomDashboard.name,
        config: expect.objectContaining({ title: mockCustomDashboard.config.title }),
      });
    });

    it('emits the loaded event with a copy of the dashboard, not the original object', () => {
      expect(wrapper.emitted('loaded')[0][0]).not.toBe(wrapper.vm.dashboard);
    });

    it('passes an empty errors list to the slot for a valid dashboard', () => {
      expect(getSlotProp('errors')).toEqual([]);
    });
  });

  describe('with a system dashboard that failed schema validation', () => {
    const { errors } = mockInvalidSystemDashboardResponse.customSystemDashboard;

    beforeEach(async () => {
      createComponent({
        requestHandlers: mockResolvedSystemQuery(mockInvalidSystemDashboardResponse),
        routeParams: { slug: 'broken' },
      });
      await waitForPromises();
    });

    it('passes the schema errors to the slot', () => {
      expect(getSlotProp('errors')).toEqual(errors);
    });

    it('still renders the dashboard slot when panels is not an array', () => {
      expect(getSlotProp('config').panels).toEqual([]);
    });

    it('emits the loaded event with the errors', () => {
      expect(wrapper.emitted('loaded')[0][0]).toMatchObject({ errors });
    });
  });

  describe('with a system dashboard whose panels have schema errors', () => {
    const { errors } = mockSystemDashboardWithPanelErrorsResponse.customSystemDashboard;
    const panelErrors = (panel) => panel.visualization?.errors;

    beforeEach(async () => {
      createComponent({
        requestHandlers: mockResolvedSystemQuery(mockSystemDashboardWithPanelErrorsResponse),
        routeParams: { slug: 'panel_errors' },
      });
      await waitForPromises();
    });

    it('puts every error under a panel pointer onto that panel, by its original index', () => {
      const [fine, bad] = getSlotProp('config').panels;

      expect(panelErrors(fine)).toBeUndefined();
      expect(panelErrors(bad)).toEqual([errors[1], errors[2]]);
    });

    it('gives a panel without a visualization one that only carries the errors', () => {
      const [, , missing] = getSlotProp('config').panels;

      expect(missing.visualization).toEqual({ errors: [errors[3]] });
    });

    it('replaces a visualization that is not an object instead of spreading it', () => {
      const [, , , scalar] = getSlotProp('config').panels;

      expect(scalar.visualization).toEqual({ errors: [errors[4]] });
    });

    it('drops existing errors that are not a list instead of spreading them', () => {
      const [, , , , scalarErrors] = getSlotProp('config').panels;

      expect(panelErrors(scalarErrors)).toEqual([errors[5]]);
    });

    describe('for a panel with its own views', () => {
      const withViews = () => getSlotProp('config').panels[5];

      it('puts a view error on that view only', () => {
        const [first, second] = withViews().views;

        expect(first.visualization.errors).toEqual([errors[7]]);
        expect(second.visualization.errors).toEqual([errors[6], errors[7]]);
      });

      it('puts a panel-wide error on the panel and on every view, whichever is selected', () => {
        expect(panelErrors(withViews())).toEqual([errors[7]]);
        expect(withViews().views.map(({ visualization }) => visualization.type)).toEqual([
          'LineChart',
          'Nope',
        ]);
      });
    });

    it('leaves a section panel alone, since the details page renders its header instead', () => {
      const [, , , , , , section] = getSlotProp('config').panels;

      expect(section.section).toEqual({ title: 'Section', description: 7 });
      expect(section.visualization).toBeUndefined();
    });

    it('maps errors under a dashboard view onto that view panel', () => {
      const [view] = getSlotProp('config').views;

      expect(panelErrors(view.panels[0])).toEqual([errors[9]]);
    });

    it('keeps the full list for the dashboard alert', () => {
      expect(getSlotProp('errors')).toEqual(errors);
    });
  });

  describe('with a system dashboard whose panel views are not a list', () => {
    const panel = (id, extra = {}) => ({
      id,
      title: id,
      gridAttributes: { width: 4, height: 2 },
      visualization: { type: 'LineChart' },
      ...extra,
    });
    const response = {
      customSystemDashboard: {
        ...mockSystemDashboardWithPanelErrorsResponse.customSystemDashboard,
        id: 'gitlab:dashboard:bad_panel_views',
        name: 'bad_panel_views',
        config: {
          title: 'Bad panel views',
          panels: [
            panel('string', { views: 'oops' }),
            panel('null', { views: null }),
            panel('none'),
          ],
        },
        errors: [
          "property '/panels/0/views' is not of type: array",
          "property '/panels/1/views' is not of type: array",
          "property '/panels/2/title' is not of type: string",
        ],
      },
    };

    beforeEach(async () => {
      createComponent({
        requestHandlers: mockResolvedSystemQuery(response),
        routeParams: { slug: 'bad_panel_views' },
      });
      await waitForPromises();
    });

    it('replaces views that are not a list with an empty list', () => {
      const [string, nullViews] = getSlotProp('config').panels;

      expect(string.views).toEqual([]);
      expect(nullViews.views).toEqual([]);
    });

    it('does not add views to a panel that had none', () => {
      const [, , none] = getSlotProp('config').panels;

      expect(none).not.toHaveProperty('views');
      expect(none.visualization.errors).toEqual([response.customSystemDashboard.errors[2]]);
    });
  });

  describe('with a system dashboard whose views have a broken panels list', () => {
    beforeEach(async () => {
      createComponent({
        requestHandlers: mockResolvedSystemQuery(mockInvalidSystemDashboardWithViewsResponse),
        routeParams: { slug: 'broken_views' },
      });
      await waitForPromises();
    });

    it('keeps the intact view and empties the broken one', () => {
      const { views } = getSlotProp('config');

      expect(views.map((view) => view.panels.length)).toEqual([0, 1]);
      expect(views[1].panels[0].id).toBe('panel-1');
    });

    it('passes the schema errors to the slot', () => {
      expect(getSlotProp('errors')).toEqual(["property '/views/0/panels' is not of type: array"]);
    });
  });

  describe('with a system dashboard that has null entries in panels and views', () => {
    beforeEach(async () => {
      createComponent({
        requestHandlers: mockResolvedSystemQuery(mockSystemDashboardWithNullEntriesResponse),
        routeParams: { slug: 'null_entries' },
      });
      await waitForPromises();
    });

    it('drops the null entries and keeps the rest', () => {
      const { panels, views } = getSlotProp('config');

      expect(panels.map((panel) => panel.title)).toEqual(['Fine']);
      expect(views.map((view) => [view.title, view.panels.length])).toEqual([['Good', 0]]);
    });

    it('names the breadcrumb and the layout after the slug when the title is missing', () => {
      expect(mockBreadcrumbState.update).toHaveBeenCalledWith({
        name: 'null_entries',
        slug: 'null_entries',
      });
      expect(getSlotProp('config').title).toBe('null_entries');
    });
  });

  describe('with a dashboard that defines views', () => {
    beforeEach(async () => {
      createComponent({ requestHandlers: mockResolvedQuery(mockDashboardWithViewsResponse) });
      await waitForPromises();
    });

    it('replaces panel ids with unique ids within each view', () => {
      const { views } = getSlotProp('config');
      const ids = views.flatMap((view) => view.panels.map((panel) => panel.id));

      ids.forEach((id) => {
        expect(id).toMatch(/^panel-\d+$/);
      });
      expect(new Set(ids).size).toBe(ids.length);
    });

    it('preserves each view title', () => {
      const { views } = getSlotProp('config');

      expect(views.map((view) => view.title)).toEqual(['Overview', 'Details']);
    });
  });

  describe('with a section entry', () => {
    const sectionPanel = {
      section: { title: 'Adoption tiers' },
      gridAttributes: { xPos: 0, yPos: 0, height: 1 },
    };
    const normalPanel = mockCustomDashboard.config.panels[0];

    const createWithConfig = async (config) => {
      createComponent({
        requestHandlers: mockResolvedQuery({
          customDashboard: {
            ...mockCustomDashboard,
            config: { ...mockCustomDashboard.config, ...config },
          },
        }),
      });
      await waitForPromises();
    };

    it('drops a panel with no gridAttributes and keeps the rest', async () => {
      const { gridAttributes, ...unplaced } = normalPanel;
      await createWithConfig({ panels: [{ ...unplaced, title: 'Unplaced' }, normalPanel] });

      expect(getSlotProp('config').panels.map((panel) => panel.title)).toEqual([normalPanel.title]);
    });

    it.each([undefined, 'full', 3])(
      'drops a section whose gridAttributes is %s and keeps the rest',
      async (gridAttributes) => {
        await createWithConfig({ panels: [{ ...sectionPanel, gridAttributes }, normalPanel] });

        expect(getSlotProp('config').panels.map((panel) => panel.title)).toEqual([
          normalPanel.title,
        ]);
      },
    );

    it('fills in the full dashboard width', async () => {
      await createWithConfig({ panels: [sectionPanel] });

      expect(getSlotProp('config').panels[0].gridAttributes).toEqual({
        xPos: 0,
        yPos: 0,
        height: 1,
        width: 12,
      });
    });

    it('keeps an explicitly configured width', async () => {
      await createWithConfig({
        panels: [{ ...sectionPanel, gridAttributes: { ...sectionPanel.gridAttributes, width: 6 } }],
      });

      expect(getSlotProp('config').panels[0].gridAttributes.width).toBe(6);
    });

    it('leaves the grid attributes of a normal panel untouched', async () => {
      await createWithConfig({ panels: [normalPanel] });

      expect(getSlotProp('config').panels[0].gridAttributes).toEqual(normalPanel.gridAttributes);
    });

    it('numbers the panels in reading order', async () => {
      const lower = { ...normalPanel, gridAttributes: { ...normalPanel.gridAttributes, yPos: 5 } };
      await createWithConfig({ panels: [lower, normalPanel] });

      expect(getSlotProp('config').panels.map(({ loadPriority }) => loadPriority)).toEqual([1, 0]);
    });

    it('restarts the numbering for each view', async () => {
      const lower = { ...normalPanel, gridAttributes: { ...normalPanel.gridAttributes, yPos: 5 } };
      await createWithConfig({
        panels: [],
        views: [
          { title: 'First', panels: [normalPanel] },
          { title: 'Second', panels: [lower, normalPanel] },
        ],
      });

      const { views } = getSlotProp('config');

      expect(views[0].panels.map(({ loadPriority }) => loadPriority)).toEqual([0]);
      expect(views[1].panels.map(({ loadPriority }) => loadPriority)).toEqual([1, 0]);
    });

    it('fills in the width for a section inside a view', async () => {
      await createWithConfig({ views: [{ title: 'Overview', panels: [sectionPanel] }] });

      expect(getSlotProp('config').views[0].panels[0].gridAttributes.width).toBe(12);
    });
  });

  // The compact grid is the only one supported, whatever the config says. 42 and {} are values
  // the schema rejects; a dashboard kept with its schema errors must still render.
  describe.each([undefined, null, 'default', 'compact', 42, {}])(
    'with a grid height of %s',
    (gridHeight) => {
      beforeEach(async () => {
        createComponent({
          requestHandlers: mockResolvedQuery(mockDashboardCompactGridResponse(gridHeight)),
        });
        await waitForPromises();
      });

      it('passes cellHeight as 10 to the slot', () => {
        expect(getSlotProp('cellHeight')).toBe('10');
      });

      it('passes minCellHeight as 10 to the slot', () => {
        expect(getSlotProp('minCellHeight')).toBe('10');
      });
    },
  );

  describe('with a query error', () => {
    beforeEach(async () => {
      createComponent({ requestHandlers: mockRejectedQuery() });
      await waitForPromises();
    });

    it('does not render the dashboard slot', () => {
      expect(findDashboardSlot().exists()).toBe(false);
    });

    it('shows an error alert', () => {
      expect(findAlert().exists()).toBe(true);
      expect(findAlert().text()).toBe('Failed to load dashboard. Please try again.');
    });

    it('logs the error to sentry', () => {
      expect(sentryBrowserWrapper.captureException).toHaveBeenCalledWith(expect.any(Error));
    });
  });

  describe('when the route is a system dashboard', () => {
    let customQueryHandler;
    let systemQueryHandler;

    const createSystemComponent = ({ slug = 'merge_requests' } = {}) => {
      customQueryHandler = jest.fn().mockResolvedValue({ data: mockDashboardResponse });
      systemQueryHandler = jest.fn().mockResolvedValue({ data: mockSystemDashboardResponse });

      const apolloProvider = createMockApollo([
        [getDashboardQuery, customQueryHandler],
        [getSystemDashboardQuery, systemQueryHandler],
      ]);

      createComponent({
        requestHandlers: apolloProvider,
        routeParams: { slug },
      });
    };

    beforeEach(async () => {
      createSystemComponent();
      await waitForPromises();
    });

    it('uses the system dashboard query', () => {
      expect(systemQueryHandler).toHaveBeenCalledWith({ slug: 'merge_requests' });
    });

    it('does not call the custom dashboard query', () => {
      expect(customQueryHandler).not.toHaveBeenCalled();
    });

    it('does not convert the slug into a GraphQL ID', () => {
      expect(systemQueryHandler).not.toHaveBeenCalledWith(
        expect.objectContaining({ slug: expect.stringContaining('gid://') }),
      );
    });

    it('passes the dashboard slug to the slot as the ID', () => {
      expect(getSlotProp('dashboard-id')).toEqual('merge_requests');
    });

    it('renders the system dashboard config in the slot', () => {
      expect(getSlotProp('config')).toMatchObject(
        mockSystemDashboardResponse.customSystemDashboard.config,
      );
    });

    it('passes isSystemDashboard as true to the slot', () => {
      expect(getSlotProp('isSystemDashboard')).toBe('true');
    });
  });

  describe('when the system dashboard does not exist', () => {
    let systemQueryHandler;

    beforeEach(async () => {
      systemQueryHandler = jest.fn().mockResolvedValue({ data: { customSystemDashboard: null } });

      const apolloProvider = createMockApollo([[getSystemDashboardQuery, systemQueryHandler]]);

      createComponent({
        requestHandlers: apolloProvider,
        routeParams: { slug: 'does_not_exist' },
      });

      await waitForPromises();
    });

    it('queries the system dashboard endpoint with the slug', () => {
      expect(systemQueryHandler).toHaveBeenCalledWith({ slug: 'does_not_exist' });
    });

    it('does not show an error alert', () => {
      expect(findAlert().exists()).toBe(false);
    });

    it('renders the not found state with a link back to the dashboards list', () => {
      expect(findNotFound().props()).toMatchObject({
        title: 'Dashboard not found',
        primaryButtonLink: '/explore/analytics_dashboards',
      });
    });

    it('does not render the dashboard slot', () => {
      expect(findDashboardSlot().exists()).toBe(false);
    });

    it('does not emit the loaded event', () => {
      expect(wrapper.emitted('loaded')).toBeUndefined();
    });

    it('names the breadcrumb after the not found state', () => {
      expect(mockBreadcrumbState.update).toHaveBeenCalledWith({
        name: 'Dashboard not found',
        slug: 'does_not_exist',
      });
    });
  });

  describe('when the user may not see the system dashboard', () => {
    beforeEach(async () => {
      const apolloProvider = createMockApollo([
        [
          getSystemDashboardQuery,
          jest.fn().mockResolvedValue({
            data: { customSystemDashboard: null },
            errors: [
              {
                message:
                  "The resource that you are attempting to access does not exist or you don't have permission to perform this action",
              },
            ],
          }),
        ],
      ]);

      createComponent({ requestHandlers: apolloProvider, routeParams: { slug: 'dap_impact' } });

      await waitForPromises();
    });

    it('renders the not found state instead of an error', () => {
      expect(findNotFound().exists()).toBe(true);
      expect(findAlert().exists()).toBe(false);
      expect(findDashboardSlot().exists()).toBe(false);
    });

    it('names the breadcrumb after the not found state', () => {
      expect(mockBreadcrumbState.update).toHaveBeenCalledWith({
        name: 'Dashboard not found',
        slug: 'dap_impact',
      });
    });

    it('does not report the error to Sentry', () => {
      expect(sentryBrowserWrapper.captureException).not.toHaveBeenCalled();
    });
  });

  describe('when the system dashboard query returns another GraphQL error', () => {
    beforeEach(async () => {
      const apolloProvider = createMockApollo([
        [
          getSystemDashboardQuery,
          jest.fn().mockResolvedValue({
            data: { customSystemDashboard: null },
            errors: [{ message: 'Something went wrong' }],
          }),
        ],
      ]);

      createComponent({ requestHandlers: apolloProvider, routeParams: { slug: 'dap_impact' } });

      await waitForPromises();
    });

    it('renders the error alert instead of the not found state', () => {
      expect(findAlert().exists()).toBe(true);
      expect(findNotFound().exists()).toBe(false);
    });

    it('reports the error to Sentry', () => {
      expect(sentryBrowserWrapper.captureException).toHaveBeenCalledWith(expect.any(Error));
    });
  });
});
