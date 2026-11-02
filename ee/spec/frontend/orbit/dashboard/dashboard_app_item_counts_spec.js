import Vue from 'vue';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DashboardApp from 'ee/orbit/dashboard/dashboard_app.vue';
import createDashboardRouter from 'ee/orbit/dashboard/router';
import { GROUPS_POLL_INTERVAL_MS } from 'ee/orbit/dashboard/constants';
import { DASHBOARD_CACHE_CONFIG } from 'ee/orbit/dashboard/graphql/cache_config';
import dashboardGroupsQuery from 'ee/orbit/dashboard/graphql/dashboard_groups.query.graphql';
import itemCountsQuery from 'ee/orbit/dashboard/graphql/item_counts.query.graphql';
import OrbitGroupStatusPage from 'ee/orbit/dashboard/group_status/orbit_group_status_page.vue';
import OrbitSchemaPage from 'ee/orbit/dashboard/schema/orbit_schema_page.vue';
import OverviewStatsCard from 'ee/orbit/dashboard/overview/overview_stats_card.vue';
import SchemaDataTab from 'ee/orbit/dashboard/schema/schema_data_tab.vue';
import { executeOrbitNamedQuery, fetchOrbitSchema } from 'ee/orbit/api/orbit_api';
import { FIVE_MINUTES_MS } from 'ee/orbit/utils/orbit_cache';
import {
  buildGroupWithPendingProjects,
  buildItemCountGroup,
  buildOrbitGroup,
  memberGroupsResponse,
  orbitPlatform,
} from '../mock_data';

jest.mock('ee/orbit/api/orbit_api');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('ee/orbit/dashboard/group_status/orbit_group_status_page.vue', () => ({
  name: 'OrbitGroupStatusPage',
  render: (h) => h('div'),
}));
jest.mock('ee/orbit/dashboard/query_editor/orbit_query_editor_page.vue', () => ({
  name: 'OrbitQueryEditorPage',
  render: (h) => h('div'),
}));

Vue.use(VueApollo);
Vue.use(VueRouter);

const countsResponse = (pipelines) =>
  memberGroupsResponse([buildItemCountGroup({ domains: { ci: { Pipeline: pipelines } } })]);

describe('OrbitDashboardApp item counts', () => {
  let wrapper;
  let groupsHandler;
  let itemCountsHandler;

  const findTab = (label) =>
    wrapper.findAll('a.gl-tab-nav-item').wrappers.find((tab) => tab.text() === label).element;
  const findStatsCard = () => wrapper.findComponent(OverviewStatsCard);

  const openTab = async (label) => {
    findTab(label).click();
    await waitForPromises();
  };

  const poll = async () => {
    jest.advanceTimersByTime(GROUPS_POLL_INTERVAL_MS);
    await waitForPromises();
  };

  const mountAt = async (path, ...groupResponses) => {
    groupsHandler = jest.fn();
    groupResponses.forEach((group) =>
      groupsHandler.mockResolvedValueOnce(memberGroupsResponse([group])),
    );
    groupsHandler.mockResolvedValue(memberGroupsResponse([groupResponses.at(-1)]));
    const router = createDashboardRouter('/');
    await router.push(path);
    wrapper = mountExtended(DashboardApp, {
      router,
      apolloProvider: createMockApollo(
        [
          [dashboardGroupsQuery, groupsHandler],
          [itemCountsQuery, itemCountsHandler],
        ],
        {},
        DASHBOARD_CACHE_CONFIG,
      ),
      propsData: { duoAccessible: true, orbitSettingsEnabled: true },
      stubs: { GraphExplorer: true },
      provide: {
        orbitPlatform: orbitPlatform({ saas: false, instance: { state: null } }),
        queriesAvailable: true,
        adminConfigurationPath: null,
        trialAvailable: false,
        currentUserId: 1,
        defaultGroupMissing: true,
        preferencesPath: '/-/profile/preferences',
        canAskDuoForQueries: false,
      },
    });
    await waitForPromises();
  };

  beforeEach(() => {
    localStorage.clear();
    fetchOrbitSchema.mockResolvedValue({ nodes: [], edges: [] });
    executeOrbitNamedQuery.mockResolvedValue({ data: { result: { nodes: [], edges: [] } } });
    itemCountsHandler = jest
      .fn()
      .mockResolvedValueOnce(countsResponse(1))
      .mockResolvedValue(countsResponse(9));
  });

  it('reads the counts of all groups in one request', async () => {
    await mountAt('/overview', buildOrbitGroup());

    expect(itemCountsHandler).toHaveBeenCalledTimes(1);
    expect(itemCountsHandler).toHaveBeenCalledWith({ first: 50 });
    expect(findStatsCard().props('graphStats').domains).toEqual({ ci: 1 });
  });

  it('reads the counts once across polls and tab switches', async () => {
    await mountAt('/overview', buildGroupWithPendingProjects());

    await poll();
    await openTab('Schema');
    await openTab('Overview');

    expect(groupsHandler).toHaveBeenCalledTimes(2);
    expect(itemCountsHandler).toHaveBeenCalledTimes(1);
  });

  it('reads the counts when the initial indexing ends', async () => {
    await mountAt('/overview', buildOrbitGroup({ state: 'INDEXING' }), buildOrbitGroup());

    expect(itemCountsHandler).not.toHaveBeenCalled();

    await poll();

    expect(itemCountsHandler).toHaveBeenCalledTimes(1);
    expect(findStatsCard().props('status')).toBe('ready');
  });

  it('reads the counts again when the indexing changes while Overview is closed', async () => {
    await mountAt('/overview', buildOrbitGroup(), buildOrbitGroup({ state: 'FAILED' }));
    await openTab('Schema');

    wrapper.findComponent(OrbitSchemaPage).vm.$emit('groups-changed');
    await waitForPromises();
    await openTab('Overview');

    expect(itemCountsHandler).toHaveBeenCalledTimes(2);
    expect(findStatsCard().props('graphStats').domains).toEqual({ ci: 9 });
  });

  it('shows the new counts on Schema after the indexing changes', async () => {
    await mountAt('/schema', buildOrbitGroup(), buildOrbitGroup({ state: 'FAILED' }));

    wrapper.findComponent(OrbitSchemaPage).vm.$emit('groups-changed');
    await waitForPromises();

    expect(itemCountsHandler).toHaveBeenCalledTimes(2);
    expect(wrapper.findComponent(SchemaDataTab).props('graphStats')).toEqual({ pipeline: 9 });
  });

  describe('on a tab without counts', () => {
    it('reads no counts', async () => {
      await mountAt('/query', buildOrbitGroup());
      await openTab('Status');

      expect(itemCountsHandler).not.toHaveBeenCalled();
    });

    it('reads the counts again on Overview when the indexing changed on Status', async () => {
      await mountAt('/overview', buildOrbitGroup(), buildOrbitGroup({ state: 'FAILED' }));
      await openTab('Status');

      wrapper.findComponent(OrbitGroupStatusPage).vm.$emit('groups-changed');
      await waitForPromises();

      expect(itemCountsHandler).toHaveBeenCalledTimes(1);

      await openTab('Overview');

      expect(itemCountsHandler).toHaveBeenCalledTimes(2);
      expect(findStatsCard().props('graphStats').domains).toEqual({ ci: 9 });
    });

    it('does not read the counts again on Overview when the indexing did not change', async () => {
      await mountAt('/overview', buildOrbitGroup());
      await openTab('Status');

      wrapper.findComponent(OrbitGroupStatusPage).vm.$emit('groups-changed');
      await waitForPromises();
      await openTab('Overview');

      expect(itemCountsHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('with the counts in the local cache', () => {
    const remountAt = async (path, group) => {
      wrapper.destroy();
      await mountAt(path, group);
    };

    it('reads no counts after a reload with the same indexing state', async () => {
      await mountAt('/overview', buildOrbitGroup());
      await remountAt('/overview', buildOrbitGroup());

      expect(itemCountsHandler).toHaveBeenCalledTimes(1);
      expect(findStatsCard().props('graphStats').domains).toEqual({ ci: 1 });
    });

    it('reads the counts again after a reload with a new indexing state', async () => {
      await mountAt('/overview', buildOrbitGroup());
      await remountAt('/overview', buildOrbitGroup({ state: 'FAILED' }));

      expect(itemCountsHandler).toHaveBeenCalledTimes(2);
      expect(findStatsCard().props('graphStats').domains).toEqual({ ci: 9 });
    });

    it('reads the counts again after the cache entry expires', async () => {
      await mountAt('/overview', buildOrbitGroup());
      jest.spyOn(Date, 'now').mockReturnValue(Date.now() + FIVE_MINUTES_MS + 1);
      await remountAt('/overview', buildOrbitGroup());
      Date.now.mockRestore();

      expect(itemCountsHandler).toHaveBeenCalledTimes(2);
    });

    it('does not keep an Orbit error in the cache', async () => {
      itemCountsHandler = jest
        .fn()
        .mockResolvedValueOnce({ errors: [{ message: 'Orbit request failed' }] })
        .mockResolvedValue(countsResponse(1));
      await mountAt('/overview', buildOrbitGroup());
      await remountAt('/overview', buildOrbitGroup());

      expect(itemCountsHandler).toHaveBeenCalledTimes(2);
      expect(findStatsCard().props('status')).toBe('ready');
    });
  });

  describe('when the counts request fails', () => {
    it('marks the stats as failed and reports the error', async () => {
      itemCountsHandler = jest.fn().mockRejectedValue(new Error('timeout'));
      await mountAt('/overview', buildOrbitGroup());

      expect(findStatsCard().props()).toMatchObject({ status: 'failed', graphStats: null });
      expect(Sentry.captureException).toHaveBeenCalledTimes(1);
    });

    it('does not report an Orbit error to Sentry', async () => {
      itemCountsHandler = jest
        .fn()
        .mockResolvedValue({ errors: [{ message: 'Orbit request failed' }] });
      await mountAt('/overview', buildOrbitGroup());

      expect(findStatsCard().props('status')).toBe('failed');
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });
  });
});
