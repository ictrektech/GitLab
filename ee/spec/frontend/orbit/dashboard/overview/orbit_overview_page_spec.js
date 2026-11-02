import Vue, { ref } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { useFakeDate } from 'helpers/fake_date';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import OrbitOverviewPage from 'ee/orbit/dashboard/overview/orbit_overview_page.vue';
import OverviewPendingProjects from 'ee/orbit/dashboard/overview/overview_pending_projects.vue';
import OverviewQueriesLocked from 'ee/orbit/dashboard/overview/overview_queries_locked.vue';
import OverviewStatsCard from 'ee/orbit/dashboard/overview/overview_stats_card.vue';
import GraphExplorer from 'ee/orbit/components/graph_explorer.vue';
import { fetchOrbitSchema } from 'ee/orbit/api/orbit_api';
import {
  buildGroupWithPendingProjects,
  buildItemCountGroup,
  buildOrbitGroup,
  orbitPlatform,
} from '../../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('ee/orbit/api/orbit_api');

const countGroups = (pipelines) => [
  buildItemCountGroup({ domains: { ci: { Pipeline: pipelines } } }),
];

const SCHEMA = { nodes: [{ name: 'Project' }] };

Vue.use(VueApollo);

describe('OrbitOverviewPage', () => {
  let wrapper;
  let providedGroups;

  const mountComponent = ({
    enabledGroups = [buildOrbitGroup()],
    route = { query: {} },
    defaultGroupMissing = false,
    queriesAvailable = true,
    instanceAccessState = null,
    adminConfigurationPath = null,
    itemCountGroups = countGroups(1200),
    itemCountsLoading = false,
  } = {}) => {
    providedGroups = ref(enabledGroups);
    wrapper = shallowMountExtended(OrbitOverviewPage, {
      apolloProvider: createMockApollo(),
      provide: {
        defaultGroupMissing,
        enabledMemberGroups: providedGroups,
        itemCountGroups: ref(itemCountGroups),
        itemCountsLoading: ref(itemCountsLoading),
        queriesAvailable,
        adminConfigurationPath,
        orbitPlatform: orbitPlatform({ saas: false, instance: { state: instanceAccessState } }),
      },
      mocks: { $route: route },
      stubs: {
        GraphExplorer: stubComponent(GraphExplorer, {
          template: '<div><slot name="top-right"></slot></div>',
        }),
      },
    });
  };

  const createComponent = async (options) => {
    mountComponent(options);
    await waitForPromises();
  };

  const pollGroups = async (groups) => {
    providedGroups.value = groups;
    await waitForPromises();
  };

  const findStatsCard = () => wrapper.findComponent(OverviewStatsCard);
  const findPendingProjects = () => wrapper.findComponent(OverviewPendingProjects);
  const findExplorer = () => wrapper.findComponent(GraphExplorer);
  const findOverlay = () => wrapper.findByTestId('overview-indexing-overlay');
  const findQueriesLocked = () => wrapper.findComponent(OverviewQueriesLocked);

  beforeEach(() => {
    fetchOrbitSchema.mockResolvedValue(SCHEMA);
  });

  it('shows the stats card as loading until the counts arrive', () => {
    mountComponent({ itemCountGroups: [], itemCountsLoading: true });

    expect(findStatsCard().props()).toMatchObject({ status: 'loading', graphStats: null });
  });

  describe('when every group is ready', () => {
    beforeEach(() => createComponent());

    it('shows the stats card and no overlay', () => {
      expect(findStatsCard().exists()).toBe(true);
      expect(findStatsCard().props('groupCount')).toBe(1);
      expect(findOverlay().exists()).toBe(false);
    });

    it('does not show the pending projects', () => {
      expect(findPendingProjects().exists()).toBe(false);
    });

    it('lets the globe load the group neighbors', () => {
      expect(findExplorer().props('expandNeighbors')).toBe(true);
    });

    it('shows no trial and purchase card and leaves the globe in reach', () => {
      expect(findQueriesLocked().exists()).toBe(false);
      expect(findExplorer().attributes('inert')).toBeUndefined();
    });

    it('reads the expanded schema and hands it to the globe', () => {
      expect(fetchOrbitSchema).toHaveBeenCalledWith(
        expect.objectContaining({ query: expect.any(Function) }),
      );
      expect(findExplorer().props('schema')).toBe(SCHEMA);
    });

    it('asks the globe for no instance map', () => {
      expect(findExplorer().props('instanceMapRequest')).toBe(null);
    });

    it('hands the summed counts to the card', () => {
      expect(findStatsCard().props('status')).toBe('ready');
      expect(findStatsCard().props('graphStats')).toEqual({
        domains: { ci: 1200 },
        entities: { pipeline: 1200 },
        indexedProjects: 0,
      });
    });
  });

  // Orbit queries return 422 until the user picks a default group.
  describe('when the default group is missing', () => {
    beforeEach(() => createComponent({ defaultGroupMissing: true }));

    it('does not let the globe load the group neighbors', () => {
      expect(findExplorer().props('expandNeighbors')).toBe(false);
    });
  });

  // The neighbors of a group come from a billed Orbit query.
  describe('when the instance runs no Orbit queries', () => {
    describe('and every group is ready', () => {
      beforeEach(() =>
        createComponent({
          queriesAvailable: false,
          instanceAccessState: 'TRIAL_ELIGIBLE',
          adminConfigurationPath: '/admin/orbit',
          enabledGroups: [buildGroupWithPendingProjects()],
          route: { query: { entity: 'MergeRequest' } },
        }),
      );

      it('keeps the counts and does not load the group neighbors', () => {
        expect(findStatsCard().props('status')).toBe('ready');
        expect(findExplorer().props('expandNeighbors')).toBe(false);
      });

      it('covers the globe with the trial and purchase card', () => {
        expect(findQueriesLocked().props()).toEqual({
          accessState: 'TRIAL_ELIGIBLE',
          adminPath: '/admin/orbit',
        });
      });

      it('runs no instance map query and keeps the globe out of reach', () => {
        expect(findExplorer().props('instanceMapRequest')).toBe(null);
        expect(findExplorer().attributes('inert')).toBeDefined();
      });

      it('hides the pending projects under the card', () => {
        expect(findPendingProjects().exists()).toBe(false);
      });
    });

    describe('and a group indexes for the first time', () => {
      beforeEach(() =>
        createComponent({
          queriesAvailable: false,
          enabledGroups: [buildOrbitGroup({ state: 'INDEXING' })],
        }),
      );

      it('shows the indexing overlay and no trial and purchase card', () => {
        expect(findOverlay().exists()).toBe(true);
        expect(findQueriesLocked().exists()).toBe(false);
      });
    });
  });

  describe('when some groups are ready and one indexes', () => {
    beforeEach(() =>
      createComponent({
        enabledGroups: [buildOrbitGroup({ id: 1 }), buildOrbitGroup({ id: 2, state: 'INDEXING' })],
      }),
    );

    it('shows the overlay and hides the stats card', () => {
      expect(findOverlay().exists()).toBe(true);
      expect(findStatsCard().exists()).toBe(false);
    });

    it('does not show the pending projects', () => {
      expect(findPendingProjects().exists()).toBe(false);
    });
  });

  describe('when a ready group has new projects that wait for code indexing', () => {
    let groups;

    beforeEach(() => {
      groups = [buildOrbitGroup({ id: 1 }), buildGroupWithPendingProjects({ id: 2, pending: 2 })];
      return createComponent({ enabledGroups: groups });
    });

    it('shows the stats card with the indexed projects of all groups, and no overlay', () => {
      expect(findOverlay().exists()).toBe(false);
      expect(findStatsCard().props('graphStats').indexedProjects).toBe(98);
    });

    it('hands the groups to the pending projects', () => {
      expect(findPendingProjects().props('groups')).toEqual(groups);
    });
  });

  describe('when a group failed and the others are ready', () => {
    beforeEach(() =>
      createComponent({
        enabledGroups: [buildOrbitGroup({ id: 1 }), buildOrbitGroup({ id: 2, state: 'FAILED' })],
      }),
    );

    it('shows the stats card and no overlay', () => {
      expect(findStatsCard().exists()).toBe(true);
      expect(findOverlay().exists()).toBe(false);
    });
  });

  describe('when a group never started indexing long after Orbit was turned on', () => {
    useFakeDate(2026, 9, 13);

    beforeEach(() =>
      createComponent({
        enabledGroups: [
          buildOrbitGroup({ id: 1 }),
          buildOrbitGroup({ id: 2, state: 'NOT_STARTED', enabledAt: '2026-04-22T14:04:36Z' }),
        ],
      }),
    );

    it('shows the stats card and no overlay', () => {
      expect(findStatsCard().exists()).toBe(true);
      expect(findOverlay().exists()).toBe(false);
    });
  });

  describe("when a group's indexing status failed to load", () => {
    // Orbit down or rate limited: the node arrives with no status.
    beforeEach(() =>
      createComponent({
        enabledGroups: [
          {
            ...buildOrbitGroup(),
            orbit: { __typename: 'OrbitNamespace', enabled: true, indexing: null },
          },
        ],
      }),
    );

    it('shows the stats card and no overlay', () => {
      expect(findStatsCard().exists()).toBe(true);
      expect(findOverlay().exists()).toBe(false);
    });
  });

  it.each`
    case                         | itemCountGroups
    ${'no counts'}               | ${[]}
    ${'null counts for a group'} | ${[{ ...buildItemCountGroup(), orbit: { itemCounts: null } }]}
  `('marks the stats as failed, not as zero items, with $case', ({ itemCountGroups }) => {
    mountComponent({ itemCountGroups });

    expect(findStatsCard().props()).toMatchObject({ status: 'failed', graphStats: null });
  });

  it('sums the groups that have counts when another group has none', () => {
    mountComponent({
      itemCountGroups: [
        ...countGroups(5),
        { ...buildItemCountGroup({ id: 2 }), orbit: { itemCounts: null } },
      ],
    });

    expect(findStatsCard().props('status')).toBe('ready');
    expect(findStatsCard().props('graphStats').domains).toEqual({ ci: 5 });
  });

  describe('while a group indexes', () => {
    beforeEach(() => createComponent({ enabledGroups: [buildOrbitGroup({ state: 'INDEXING' })] }));

    it('shows the overlay and hides the stats card', () => {
      expect(findOverlay().text()).toContain(
        'Indexing in progress. The map fills in as data finishes indexing.',
      );
      expect(findStatsCard().exists()).toBe(false);
    });

    describe('and the last group turns ready', () => {
      beforeEach(async () => {
        await pollGroups([buildOrbitGroup({ state: 'READY' })]);
      });

      it('shows the stats card and bumps the globe neighbors version', () => {
        expect(findStatsCard().exists()).toBe(true);
        expect(findExplorer().props('neighborsVersion')).toBe('gl-demo:READY');
      });
    });
  });

  describe('when a poll returns new group objects with no change', () => {
    let nodesBefore;

    beforeEach(async () => {
      await createComponent();
      nodesBefore = findExplorer().props('initialNodes');

      await pollGroups([buildOrbitGroup()]);
    });

    it('keeps the globe nodes', () => {
      expect(findExplorer().props('initialNodes')).toBe(nodesBefore);
    });
  });

  describe('when the route asks for the instances of an entity', () => {
    beforeEach(() => createComponent({ route: { query: { entity: 'Project' } } }));

    it('passes the instance map request to the globe', () => {
      expect(findExplorer().props('instanceMapRequest')).toEqual({ entityType: 'Project' });
    });
  });

  describe('when the route repeats the entity', () => {
    beforeEach(() => createComponent({ route: { query: { entity: ['Project', 'User'] } } }));

    it('maps the first entity', () => {
      expect(findExplorer().props('instanceMapRequest')).toEqual({ entityType: 'Project' });
    });
  });

  describe('when the schema request fails', () => {
    beforeEach(() => {
      fetchOrbitSchema.mockRejectedValue(new Error('no schema'));
      return createComponent();
    });

    it('reports the error and renders the globe', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      expect(findExplorer().exists()).toBe(true);
    });
  });
});
