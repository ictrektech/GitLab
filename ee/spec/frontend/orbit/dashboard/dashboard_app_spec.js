import Vue, { nextTick, unref } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DashboardApp from 'ee/orbit/dashboard/dashboard_app.vue';
import OrbitOffPage from 'ee/orbit/dashboard/off/orbit_off_page.vue';
import OrbitTopAlerts from 'ee/orbit/dashboard/orbit_top_alerts.vue';
import dashboardGroupsQuery from 'ee/orbit/dashboard/graphql/dashboard_groups.query.graphql';
import ownedTrialsQuery from 'ee/orbit/dashboard/graphql/owned_trials.query.graphql';
import itemCountsQuery from 'ee/orbit/dashboard/graphql/item_counts.query.graphql';
import { DASHBOARD_CACHE_CONFIG } from 'ee/orbit/dashboard/graphql/cache_config';
import { buildGroupWithPendingProjects, buildOrbitGroup, orbitPlatform } from '../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/alert');

Vue.use(VueApollo);

const groupsResponse = (nodes) => ({
  data: { orbit: { __typename: 'Orbit', memberGroups: { nodes } } },
});
const countsResponse = (groups) =>
  groupsResponse(
    groups.map(({ id }) => ({
      __typename: 'Group',
      id,
      orbit: { __typename: 'OrbitNamespace', itemCounts: { domains: [] } },
    })),
  );
const trialsResponse = (nodes) => ({ data: { orbit: { __typename: 'Orbit', groups: { nodes } } } });
const ownedTrial = (state) => ({
  id: 'gid://gitlab/Group/9',
  orbit: { __typename: 'OrbitNamespace', access: { state } },
});

// A render function: the MODE 3 host has no runtime compiler for a template stub.
const PageStub = {
  name: 'PageStub',
  inject: {
    enabledMemberGroups: { default: null },
  },
  render(h) {
    const providedPaths = unref(this.enabledMemberGroups)?.map((group) => group.fullPath);

    return h('div', {
      attrs: {
        'data-testid': 'page',
        'data-provided-groups': providedPaths?.join(','),
      },
    });
  },
};

describe('OrbitDashboardApp', () => {
  let wrapper;
  let groupsHandler;
  let trialsHandler;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const mountComponent = ({
    routeName = 'overview',
    groups = [buildOrbitGroup()],
    ownedTrials = [],
    trialAvailable = false,
    adminConfigurationPath = null,
    duoAccessible = true,
    orbitSettingsEnabled = true,
    defaultGroupMissing = false,
    groupsHandlerFn = null,
    trialsHandlerFn = null,
  } = {}) => {
    groupsHandler = groupsHandlerFn || jest.fn().mockResolvedValue(groupsResponse(groups));
    trialsHandler = trialsHandlerFn || jest.fn().mockResolvedValue(trialsResponse(ownedTrials));

    wrapper = mountExtended(DashboardApp, {
      apolloProvider: createMockApollo(
        [
          [dashboardGroupsQuery, groupsHandler],
          [ownedTrialsQuery, trialsHandler],
          [itemCountsQuery, jest.fn().mockResolvedValue(countsResponse(groups))],
        ],
        {},
        DASHBOARD_CACHE_CONFIG,
      ),
      propsData: { adminConfigurationPath, duoAccessible, orbitSettingsEnabled },
      provide: {
        orbitPlatform: orbitPlatform(),
        trialAvailable,
        currentUserId: 1,
        defaultGroupMissing,
        preferencesPath: '/-/profile/preferences',
      },
      mocks: { $route: { name: routeName, query: {} } },
      attachTo: document.body,
      stubs: {
        RouterViewWithSlot: {
          render() {
            return this.$scopedSlots.default({ Component: PageStub });
          },
        },
        OrbitOffPage: true,
        'router-link': { props: ['to'], template: '<a data-testid="orbit-tab"><slot /></a>' },
      },
    });
  };

  const createComponent = async (options) => {
    mountComponent(options);
    await waitForPromises();
  };

  const findTabs = () => wrapper.findAllByTestId('orbit-tab');
  const findOffPage = () => wrapper.findComponent(OrbitOffPage);
  const findProvidedGroups = () => wrapper.findByTestId('page').attributes('data-provided-groups');
  const findQuickstart = () => wrapper.findByTestId('orbit-quickstart');
  const findQuickstartToggle = () => wrapper.findByTestId('orbit-quickstart-toggle');
  const findQuickstartChevron = (direction) =>
    findQuickstartToggle().find(`[data-testid="chevron-${direction}-icon"]`);
  const findTrialEndedAlert = () => wrapper.findByTestId('orbit-trial-ended-alert');
  const findHeading = () => wrapper.find('h1');
  const findSettingsButton = () => wrapper.findByTestId('orbit-settings-btn');
  const fillsViewport = () => wrapper.classes('orbit-app-fill-viewport');

  beforeEach(() => {
    localStorage.clear();
  });

  describe('while the groups load', () => {
    beforeEach(() => mountComponent());

    it('shows a large spinner and no tabs', () => {
      expect(wrapper.findComponent(GlLoadingIcon).props('size')).toBe('lg');
      expect(findTabs()).toHaveLength(0);
    });
  });

  describe('when no group has Orbit on', () => {
    describe('and the route is Overview', () => {
      beforeEach(() => createComponent({ groups: [], trialAvailable: true }));

      it('shows the Off page', () => {
        expect(findOffPage().exists()).toBe(true);
      });

      it('shows no header, no tabs, and no Quickstart', () => {
        expect(findHeading().exists()).toBe(false);
        expect(findTabs()).toHaveLength(0);
        expect(findQuickstartToggle().exists()).toBe(false);
      });

      it('does not stretch the Off page to the viewport height', () => {
        expect(fillsViewport()).toBe(false);
      });

      describe('and the Owner turns on Orbit', () => {
        beforeEach(async () => {
          groupsHandler.mockResolvedValue(
            groupsResponse([buildOrbitGroup({ state: 'NOT_STARTED' })]),
          );
          findOffPage().vm.$emit('turned-on');
          await waitForPromises();
        });

        it('loads the groups again and shows the Overview', () => {
          expect(groupsHandler).toHaveBeenCalledTimes(2);
          expect(findOffPage().exists()).toBe(false);
          expect(findProvidedGroups()).toBe('gl-demo');
        });
      });
    });

    describe.each(['schema', 'query', 'group_status'])('and the route is %s', (routeName) => {
      beforeEach(() => createComponent({ routeName, groups: [] }));

      it('shows the Off page with no header and no tabs', () => {
        expect(findOffPage().exists()).toBe(true);
        expect(findHeading().exists()).toBe(false);
        expect(findTabs()).toHaveLength(0);
      });

      it('does not stretch the Off page to the viewport height', () => {
        expect(fillsViewport()).toBe(false);
      });
    });
  });

  describe('when a group has Orbit on', () => {
    beforeEach(() => createComponent());

    it('does not show the Off page', () => {
      expect(findOffPage().exists()).toBe(false);
    });

    it('shows the header and the Overview, Schema, Query editor, and Status tabs', () => {
      expect(findHeading().text()).toBe('GitLab Orbit');
      expect(findTabs().wrappers.map((tab) => tab.text())).toEqual([
        'Overview',
        'Schema',
        'Query editor',
        'Status',
      ]);
    });

    it('shows the feedback link', () => {
      expect(wrapper.text()).toContain('Leave feedback');
    });

    it('does not show the settings button', () => {
      expect(findSettingsButton().exists()).toBe(false);
    });

    it('provides the groups with Orbit on to the page, loaded once', () => {
      expect(findProvidedGroups()).toBe('gl-demo');
      expect(groupsHandler).toHaveBeenCalledTimes(1);
    });

    describe('and the groups load again after the page turns Orbit on or off', () => {
      beforeEach(async () => {
        groupsHandler.mockReturnValueOnce(new Promise(() => {}));
        wrapper.findComponent(PageStub).vm.$emit('groups-changed');
        await waitForPromises();
      });

      it('loads the groups with Orbit on again', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
      });

      it('keeps the page and the tabs', () => {
        expect(wrapper.findComponent(PageStub).exists()).toBe(true);
        expect(findTabs()).toHaveLength(4);
      });
    });

    it('fits the Overview to the viewport height', () => {
      expect(fillsViewport()).toBe(true);
    });
  });

  describe('when the user is an admin', () => {
    beforeEach(() => createComponent({ adminConfigurationPath: '/admin/orbit' }));

    it('links the Settings button to the admin page', () => {
      expect(findSettingsButton().attributes('href')).toBe('/admin/orbit');
    });
  });

  describe('when the user views Schema', () => {
    beforeEach(() =>
      createComponent({ routeName: 'schema', groups: [buildOrbitGroup({ state: 'INDEXING' })] }),
    );

    it('provides the groups with Orbit on to the page', () => {
      expect(findProvidedGroups()).toBe('gl-demo');
    });

    it('shows no alerts', () => {
      expect(wrapper.findComponent(GlAlert).exists()).toBe(false);
    });

    it('fits the Schema to the viewport height', () => {
      expect(fillsViewport()).toBe(true);
    });

    describe('and a minute passes', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(60000);
        await waitForPromises();
      });

      it('does not poll', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe.each`
    routeName
    ${'schema'}
    ${'query'}
    ${'group_status'}
  `('when the user views the $routeName tab', ({ routeName }) => {
    beforeEach(() => createComponent({ routeName, groups: [buildOrbitGroup()] }));

    it('shows the Quickstart button and its panel', () => {
      expect(findQuickstartToggle().attributes('aria-expanded')).toBe('true');
      expect(findQuickstart().exists()).toBe(true);
    });
  });

  describe('Quickstart', () => {
    describe('when the user has not closed it before', () => {
      beforeEach(() => createComponent());

      it('opens the panel with an up chevron on the button', () => {
        expect(findQuickstart().exists()).toBe(true);
        expect(findQuickstartToggle().attributes('aria-expanded')).toBe('true');
        expect(findQuickstartChevron('up').exists()).toBe(true);
      });

      describe('and the user clicks the Quickstart button', () => {
        beforeEach(async () => {
          await findQuickstartToggle().trigger('click');
          await nextTick();
        });

        it('hides the panel, drops the button aria-controls, and turns the chevron down', () => {
          expect(findQuickstart().exists()).toBe(false);
          expect(findQuickstartToggle().attributes('aria-expanded')).toBe('false');
          expect(findQuickstartToggle().attributes('aria-controls')).toBeUndefined();
          expect(findQuickstartChevron('down').exists()).toBe(true);
          expect(findQuickstartChevron('up').exists()).toBe(false);
        });

        it('remembers the choice for that user', () => {
          expect(localStorage.getItem('orbit-quickstart-closed:1')).toBe('true');
        });

        describe('and the user clicks the Quickstart button again', () => {
          beforeEach(() => findQuickstartToggle().trigger('click'));

          it('opens the panel and remembers it', () => {
            expect(findQuickstart().exists()).toBe(true);
            expect(localStorage.getItem('orbit-quickstart-closed:1')).toBe('false');
          });
        });
      });
    });

    describe('when the user closed it before', () => {
      beforeEach(() => {
        localStorage.setItem('orbit-quickstart-closed:1', 'true');
        return createComponent();
      });

      it('keeps the panel closed', () => {
        expect(findQuickstart().exists()).toBe(false);
        expect(findQuickstartToggle().attributes('aria-expanded')).toBe('false');
      });
    });

    describe('when another user closed it in the same browser', () => {
      beforeEach(() => {
        localStorage.setItem('orbit-quickstart-closed:2', 'true');
        return createComponent();
      });

      it('opens the panel', () => {
        expect(findQuickstart().exists()).toBe(true);
      });
    });
  });

  describe('tab tracking', () => {
    const clickTab = (label) => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);
      expect(trackEventSpy).not.toHaveBeenCalled();

      triggerEvent(wrapper.findByText(label).element);

      return trackEventSpy;
    };

    describe.each`
      routeName     | label             | eventName
      ${'schema'}   | ${'Overview'}     | ${'click_orbit_overview_tab'}
      ${'overview'} | ${'Schema'}       | ${'click_orbit_schema_tab'}
      ${'overview'} | ${'Query editor'} | ${'click_orbit_query_editor_tab'}
    `('when the user views $routeName', ({ routeName, label, eventName }) => {
      beforeEach(() => createComponent({ routeName }));

      it(`tracks a click on the ${label} tab`, () => {
        expect(clickTab(label)).toHaveBeenCalledWith(eventName, {});
      });
    });

    describe('when the user views Overview', () => {
      beforeEach(() => createComponent({ routeName: 'overview' }));

      it('does not track a click on the active Overview tab', () => {
        expect(clickTab('Overview')).not.toHaveBeenCalled();
      });
    });
  });

  describe('when a group is indexing', () => {
    beforeEach(() => createComponent({ groups: [buildOrbitGroup({ state: 'INDEXING' })] }));

    it('loads the groups one time and shows the indexing alert', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(1);
      expect(wrapper.findByTestId('orbit-indexing-alert').exists()).toBe(true);
    });

    describe('and 20 seconds pass', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(20000);
        await waitForPromises();
      });

      it('loads the groups again', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('when a ready group has new projects that wait for code indexing', () => {
    beforeEach(() => createComponent({ groups: [buildGroupWithPendingProjects()] }));

    it('loads the groups one time and does not show the indexing alert', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(1);
      expect(wrapper.findByTestId('orbit-indexing-alert').exists()).toBe(false);
    });

    describe('and 20 seconds pass', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(20000);
        await waitForPromises();
      });

      it('loads the groups again', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('when every group is ready', () => {
    beforeEach(() => createComponent({ groups: [buildOrbitGroup({ state: 'READY' })] }));

    it('loads the groups one time', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(1);
    });

    describe('and a minute passes', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(60000);
        await waitForPromises();
      });

      it('does not poll', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('when the indexing group becomes ready', () => {
    beforeEach(() => {
      const handler = jest
        .fn()
        .mockResolvedValueOnce(groupsResponse([buildOrbitGroup({ state: 'INDEXING' })]))
        .mockResolvedValue(groupsResponse([buildOrbitGroup({ state: 'READY' })]));

      return createComponent({ groupsHandlerFn: handler });
    });

    it('loads the groups one time', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(1);
    });

    describe('and the next poll reports it ready', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(20000);
        await waitForPromises();
      });

      it('polls one more time', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
      });

      describe('and a minute passes', () => {
        beforeEach(async () => {
          jest.advanceTimersByTime(60000);
          await waitForPromises();
        });

        it('stops polling', () => {
          expect(groupsHandler).toHaveBeenCalledTimes(2);
        });
      });
    });
  });

  describe('when the trial lookup is available and a trial has ended', () => {
    beforeEach(() =>
      createComponent({
        trialAvailable: true,
        ownedTrials: [ownedTrial('TRIAL_ENDED')],
      }),
    );

    it('reads the trials of the owned groups', () => {
      expect(trialsHandler).toHaveBeenCalledTimes(1);
    });

    it('shows the trial ended alert', () => {
      expect(findTrialEndedAlert().exists()).toBe(true);
    });

    it('sends Contact sales leads to the group whose trial ended', () => {
      expect(wrapper.findComponent(OrbitTopAlerts).props('endedTrialNamespaceId')).toBe(9);
    });
  });

  describe('when the trial is active', () => {
    beforeEach(() =>
      createComponent({
        trialAvailable: true,
        ownedTrials: [ownedTrial('TRIAL_ACTIVE')],
      }),
    );

    it('shows no trial ended alert', () => {
      expect(findTrialEndedAlert().exists()).toBe(false);
    });
  });

  describe('when the group is licensed', () => {
    beforeEach(() =>
      createComponent({
        trialAvailable: true,
        ownedTrials: [ownedTrial('LICENSED')],
      }),
    );

    it('shows no trial ended alert', () => {
      expect(findTrialEndedAlert().exists()).toBe(false);
    });
  });

  describe('when the instance has no trials', () => {
    beforeEach(() => createComponent({ trialAvailable: false }));

    it('does not read the trials', () => {
      expect(trialsHandler).not.toHaveBeenCalled();
    });
  });

  describe('when no group has Orbit on and a trial has ended', () => {
    beforeEach(() =>
      createComponent({
        groups: [],
        trialAvailable: true,
        ownedTrials: [ownedTrial('TRIAL_ENDED')],
      }),
    );

    it('shows the Off page and does not read the trials', () => {
      expect(findOffPage().exists()).toBe(true);
      expect(trialsHandler).not.toHaveBeenCalled();
      expect(findTrialEndedAlert().exists()).toBe(false);
    });
  });

  describe('when Orbit errors on the indexing status', () => {
    beforeEach(() =>
      createComponent({
        groupsHandlerFn: jest.fn().mockResolvedValue({
          ...groupsResponse([
            {
              ...buildOrbitGroup(),
              orbit: {
                __typename: 'OrbitNamespace',
                enabled: true,
                enabledAt: null,
                indexing: null,
              },
            },
          ]),
          errors: [{ message: 'Orbit unavailable' }],
        }),
      }),
    );

    it('keeps the group list and shows the Overview, not the Off page', () => {
      expect(findOffPage().exists()).toBe(false);
      expect(findProvidedGroups()).toBe('gl-demo');
    });

    it('does not alert or report to Sentry', () => {
      expect(createAlert).not.toHaveBeenCalled();
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    describe('and a minute passes', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(60000);
        await waitForPromises();
      });

      it('does not poll', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('when the groups query errors with no data', () => {
    beforeEach(() =>
      createComponent({
        groupsHandlerFn: jest
          .fn()
          .mockResolvedValue({ data: null, errors: [{ message: 'complexity exceeded' }] }),
      }),
    );

    it('alerts one time and does not show the Off page', () => {
      expect(createAlert).toHaveBeenCalledTimes(1);
      expect(findOffPage().exists()).toBe(false);
    });
  });

  describe('when an older backend does not return Query.orbit', () => {
    beforeEach(() =>
      createComponent({ groupsHandlerFn: jest.fn().mockResolvedValue({ data: { orbit: null } }) }),
    );

    it('does not alert and does not show the Off page', () => {
      expect(createAlert).not.toHaveBeenCalled();
      expect(findOffPage().exists()).toBe(false);
    });
  });

  describe('when the groups fail to load', () => {
    beforeEach(() =>
      createComponent({ groupsHandlerFn: jest.fn().mockRejectedValue(new Error('boom')) }),
    );

    it('alerts and does not show the Off page', () => {
      expect(createAlert).toHaveBeenCalledTimes(1);
      expect(findOffPage().exists()).toBe(false);
    });

    it('does not show an Overview with no groups', () => {
      expect(wrapper.findByTestId('page').exists()).toBe(false);
    });

    it('stops the spinner', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(false);
    });
  });

  describe('when a poll gets no indexing status while a group indexes', () => {
    const indexingGroups = groupsResponse([buildOrbitGroup({ state: 'INDEXING' })]);
    const throttledGroups = {
      ...groupsResponse([
        {
          ...buildOrbitGroup(),
          orbit: { __typename: 'OrbitNamespace', enabled: true, enabledAt: null, indexing: null },
        },
      ]),
      errors: [{ message: 'Too many requests' }],
    };

    beforeEach(async () => {
      await createComponent({
        groupsHandlerFn: jest
          .fn()
          .mockResolvedValueOnce(indexingGroups)
          .mockResolvedValueOnce(throttledGroups)
          .mockResolvedValue(indexingGroups),
      });

      jest.advanceTimersByTime(20000);
      await waitForPromises();
    });

    it('keeps the last known status and the indexing alert', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(2);
      expect(wrapper.findByTestId('orbit-indexing-alert').exists()).toBe(true);
    });

    describe('and 20 seconds pass', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(20000);
        await waitForPromises();
      });

      it('polls again', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(3);
      });
    });
  });

  describe('when the browser tab is hidden while a group indexes', () => {
    const setHidden = (hidden) => {
      jest.spyOn(document, 'hidden', 'get').mockReturnValue(hidden);
      document.dispatchEvent(new Event('visibilitychange'));
    };

    beforeEach(async () => {
      await createComponent({ groups: [buildOrbitGroup({ state: 'INDEXING' })] });
      setHidden(true);
      await nextTick();
      jest.advanceTimersByTime(60000);
      await waitForPromises();
    });

    it('does not poll', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(1);
    });

    describe('and the tab is visible again', () => {
      beforeEach(async () => {
        setHidden(false);
        await nextTick();
        jest.advanceTimersByTime(20000);
        await waitForPromises();
      });

      it('polls again', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('when a poll fails while a group indexes', () => {
    const indexingGroups = groupsResponse([buildOrbitGroup({ state: 'INDEXING' })]);

    beforeEach(async () => {
      await createComponent({
        groupsHandlerFn: jest
          .fn()
          .mockResolvedValueOnce(indexingGroups)
          .mockRejectedValueOnce(new Error('boom'))
          .mockResolvedValue(indexingGroups),
      });

      jest.advanceTimersByTime(20000);
      await waitForPromises();
    });

    it('keeps the Overview with its groups and does not alert', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(2);
      expect(createAlert).not.toHaveBeenCalled();
      expect(findProvidedGroups()).toBe('gl-demo');
    });

    describe('and the next poll runs', () => {
      beforeEach(async () => {
        jest.advanceTimersByTime(20000);
        await waitForPromises();
      });

      it('loads the groups', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(3);
      });
    });
  });

  describe('when the trials fail to load', () => {
    beforeEach(() =>
      createComponent({
        trialAvailable: true,
        trialsHandlerFn: jest.fn().mockRejectedValue(new Error('cdot down')),
      }),
    );

    it('reports to Sentry and shows no trial-ended alert', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      expect(findTrialEndedAlert().exists()).toBe(false);
    });
  });

  describe('when the trials query returns GraphQL errors', () => {
    beforeEach(() =>
      createComponent({
        trialAvailable: true,
        trialsHandlerFn: jest
          .fn()
          .mockResolvedValue({ data: null, errors: [{ message: 'customers dot unavailable' }] }),
      }),
    );

    it('does not report to Sentry and shows no trial-ended alert', () => {
      expect(Sentry.captureException).not.toHaveBeenCalled();
      expect(findTrialEndedAlert().exists()).toBe(false);
    });
  });
});
