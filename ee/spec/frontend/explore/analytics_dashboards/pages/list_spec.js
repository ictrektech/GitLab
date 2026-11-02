import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlTabs, GlSearchBoxByType, GlSkeletonLoader, GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ExploreAnalyticsDashboardsListEE from 'ee/explore/analytics_dashboards/pages/list.vue';
import IntroBanner from 'ee/explore/analytics_dashboards/components/intro_banner.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import DashboardsList from '~/explore/analytics_dashboards/components/dashboards_list/dashboards_list.vue';
import EmptyState from '~/explore/analytics_dashboards/components/dashboards_list/empty_state.vue';
import getDashboardsQuery from '~/explore/analytics_dashboards/graphql/get_dashboards.query.graphql';
import getDuoAgentPlatformTopLevelGroupsQuery from 'ee/explore/analytics_dashboards/graphql/get_duo_agent_platform_top_level_groups.query.graphql';
import {
  mockDashboardsListResponse,
  mockEmptyDashboardsListResponse,
  mockNullDashboardsListResponse,
} from 'jest/explore/analytics_dashboards/mock_data';

Vue.use(VueApollo);

jest.mock('~/sentry/sentry_browser_wrapper');

describe('ExploreAnalyticsDashboardsListEE', () => {
  let wrapper;

  const mockResolvedQuery = (queryResponse = mockDashboardsListResponse) =>
    createMockApollo([[getDashboardsQuery, jest.fn().mockResolvedValue({ data: queryResponse })]]);

  const mockRejectedQuery = (error = new Error('Network error')) =>
    createMockApollo([[getDashboardsQuery, jest.fn().mockRejectedValue(error)]]);

  const createComponent = ({ apolloProvider } = {}) => {
    wrapper = shallowMountExtended(ExploreAnalyticsDashboardsListEE, {
      provide: {
        exploreAnalyticsDashboardsPath: '/explore/analytics_dashboards',
      },
      apolloProvider: apolloProvider || mockResolvedQuery(),
    });
  };

  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findEmptyState = () => wrapper.findComponent(EmptyState);
  const findDashboardsList = () => wrapper.findComponent(DashboardsList);

  describe('page layout', () => {
    beforeEach(async () => {
      createComponent();

      await waitForPromises();
    });

    it('renders the page heading', () => {
      expect(findPageHeading().props('heading')).toBe('GitLab Intelligence');
    });

    it('renders the GitLab Intelligence banner', () => {
      expect(wrapper.findComponent(IntroBanner).exists()).toBe(true);
    });

    it('does not render tabs', () => {
      expect(wrapper.findComponent(GlTabs).exists()).toBe(false);
    });

    it('does not render a search box', () => {
      expect(wrapper.findComponent(GlSearchBoxByType).exists()).toBe(false);
    });
  });

  describe('while the dashboards request is pending', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('does not render the dashboards list, alert, or empty state', () => {
      expect(findDashboardsList().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when the request succeeds with dashboards', () => {
    beforeEach(async () => {
      createComponent();

      await waitForPromises();
    });

    it('renders a single dashboards list', () => {
      expect(wrapper.findAllComponents(DashboardsList)).toHaveLength(1);
    });

    it('passes the dashboards to the list', () => {
      const dashboards = findDashboardsList().props('dashboards');

      expect(dashboards).toHaveLength(2);
      expect(dashboards[0].name).toBe('Fake trends');
    });

    it('builds the dashboard URL from the numeric ID for custom dashboards', () => {
      const [customDashboard] = findDashboardsList().props('dashboards');

      expect(customDashboard.dashboardUrl).toBe('/explore/analytics_dashboards/3');
    });

    it('builds the dashboard URL from the slug for system dashboards', () => {
      const dashboards = findDashboardsList().props('dashboards');
      const systemDashboard = dashboards.find((dashboard) => dashboard.system);

      expect(systemDashboard.dashboardUrl).toBe('/explore/analytics_dashboards/merge_requests');
    });

    it('does not render the skeleton loader, alert, or empty state', () => {
      expect(findSkeletonLoader().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when there are no dashboards', () => {
    beforeEach(async () => {
      createComponent({ apolloProvider: mockResolvedQuery(mockEmptyDashboardsListResponse) });

      await waitForPromises();
    });

    it('renders the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('does not render the dashboards list or an alert', () => {
      expect(findDashboardsList().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the dashboards query is unauthorized', () => {
    beforeEach(async () => {
      createComponent({ apolloProvider: mockResolvedQuery(mockNullDashboardsListResponse) });

      await waitForPromises();
    });

    it('renders the empty state instead of erroring', () => {
      expect(findEmptyState().exists()).toBe(true);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the request fails', () => {
    const testError = new Error('Test error');

    beforeEach(async () => {
      createComponent({ apolloProvider: mockRejectedQuery(testError) });

      await waitForPromises();
    });

    it('renders the error alert', () => {
      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().text()).toContain('Failed to load dashboards list. Please try again.');
    });

    it('does not render the dashboards list or empty state', () => {
      expect(findDashboardsList().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });

    it('calls Sentry.captureException with the error', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(testError);
    });
  });

  describe('when a dashboard requires Duo Agent Platform', () => {
    const [customDashboard, systemDashboard] = mockDashboardsListResponse.customDashboards.nodes;
    const dapDashboard = {
      ...systemDashboard,
      config: {
        ...systemDashboard.config,
        filters: {
          scope: {
            requireDuoAgentPlatform: true,
            requirePermissions: ['readProAiAnalytics', 'readEnterpriseAiAnalytics'],
          },
        },
      },
    };
    const group = (readEnterpriseAiAnalytics) => ({
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      name: 'Group',
      fullName: 'Group',
      fullPath: 'group',
      projectsCount: 0,
      descendantGroupsCount: 0,
      userPermissions: {
        __typename: 'GroupPermissions',
        readProAiAnalytics: true,
        readEnterpriseAiAnalytics,
      },
    });
    const groupsResponse = (nodes, hasNextPage = false) => ({
      data: {
        groups: {
          __typename: 'GroupConnection',
          nodes,
          pageInfo: { __typename: 'PageInfo', hasNextPage, endCursor: hasNextPage ? 'next' : null },
        },
      },
    });

    let groupsHandler;

    const createComponentWithGroups = (handler) => {
      groupsHandler = handler;
      createComponent({
        apolloProvider: createMockApollo([
          [
            getDashboardsQuery,
            jest.fn().mockResolvedValue({
              data: { customDashboards: { nodes: [customDashboard, dapDashboard] } },
            }),
          ],
          [getDuoAgentPlatformTopLevelGroupsQuery, groupsHandler],
        ]),
      });
    };

    const findDashboardSlugs = () =>
      findDashboardsList()
        .props('dashboards')
        .map(({ slug }) => slug);

    it('asks for the groups with Duo Agent Platform turned on', async () => {
      createComponentWithGroups(jest.fn().mockResolvedValue(groupsResponse([group(true)])));
      await waitForPromises();

      expect(groupsHandler).toHaveBeenCalled();
    });

    it.each`
      description                                      | handler
      ${'the user has a qualifying group'}             | ${() => jest.fn().mockResolvedValue(groupsResponse([group(true)]))}
      ${'a group has the permission unknown'}          | ${() => jest.fn().mockResolvedValue(groupsResponse([group(null)]))}
      ${'more groups exist than the first page shows'} | ${() => jest.fn().mockResolvedValue(groupsResponse([group(false)], true))}
      ${'the groups request fails'}                    | ${() => jest.fn().mockRejectedValue(new Error('oh no'))}
    `('lists the dashboard when $description', async ({ handler }) => {
      createComponentWithGroups(handler());
      await waitForPromises();

      expect(findDashboardSlugs()).toEqual([customDashboard.slug, dapDashboard.slug]);
    });

    it.each`
      description                          | nodes
      ${'the user has no groups'}          | ${[]}
      ${'every group denies a permission'} | ${[group(false)]}
    `('leaves the dashboard out when $description', async ({ nodes }) => {
      createComponentWithGroups(jest.fn().mockResolvedValue(groupsResponse(nodes)));
      await waitForPromises();

      expect(findDashboardSlugs()).toEqual([customDashboard.slug]);
    });
  });

  describe('when no dashboard requires Duo Agent Platform', () => {
    it('does not ask for groups', async () => {
      const groupsHandler = jest.fn();

      createComponent({
        apolloProvider: createMockApollo([
          [getDashboardsQuery, jest.fn().mockResolvedValue({ data: mockDashboardsListResponse })],
          [getDuoAgentPlatformTopLevelGroupsQuery, groupsHandler],
        ]),
      });
      await waitForPromises();

      expect(groupsHandler).not.toHaveBeenCalled();
    });
  });
});
