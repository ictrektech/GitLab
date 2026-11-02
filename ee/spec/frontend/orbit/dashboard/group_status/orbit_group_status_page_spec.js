import Vue, { nextTick, ref } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import OrbitGroupStatusPage from 'ee/orbit/dashboard/group_status/orbit_group_status_page.vue';
import groupStatusGroupsQuery from 'ee/orbit/dashboard/group_status/graphql/group_status_groups.query.graphql';
import groupStatusIndexingQuery from 'ee/orbit/dashboard/group_status/graphql/group_status_indexing.query.graphql';
import orbitStartTrialMutation from 'ee/orbit/graphql/mutations/orbit_start_trial.mutation.graphql';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import BulkResultAlert from 'ee/orbit/shared/groups/bulk_result_alert.vue';
import GroupsConfirmModal from 'ee/orbit/shared/groups/groups_confirm_modal.vue';
import GroupsTable from 'ee/orbit/shared/groups/groups_table.vue';
import GroupsWarnings from 'ee/orbit/shared/groups/groups_warnings.vue';
import TurnOnConfirmModal from 'ee/orbit/shared/groups/turn_on_confirm_modal.vue';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import TrialUnavailableAlert from 'ee/orbit/components/trial/trial_unavailable_alert.vue';
import { GROUPS_POLL_INTERVAL_MS } from 'ee/orbit/dashboard/constants';
import { DASHBOARD_CACHE_CONFIG } from 'ee/orbit/dashboard/graphql/cache_config';
import { orbitPlatform } from '../../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const NETWORK_ERROR_MESSAGE =
  'The request did not reach GitLab. Check your connection and try again.';
const offer = { __typename: 'OrbitTrialOffer', durationDays: 30, initialCredits: 100 };

const buildIndexing = (state) => ({
  __typename: 'OrbitIndexing',
  state,
  areas: [{ __typename: 'OrbitIndexingArea', name: 'core', state }],
});

const buildTrial = (state, { offer: trialOffer = null, expiresOn = null } = {}) => ({
  __typename: 'OrbitTrial',
  state,
  expiresOn,
  credits: null,
  offer: trialOffer,
});

const buildAccess = ({
  state = 'LICENSED',
  reason = null,
  turnOnDenialReason = null,
  trial = null,
} = {}) => ({
  __typename: 'OrbitAccess',
  state,
  reason,
  turnOnDenialReason,
  trial,
});

const eligibleAccess = buildAccess({
  state: 'TRIAL_ELIGIBLE',
  turnOnDenialReason: 'TRIAL_REQUIRED',
  trial: buildTrial('ELIGIBLE', { offer }),
});
const instanceTrialAccess = buildAccess({
  state: 'TRIAL_ACTIVE',
  trial: buildTrial('ACTIVE', { expiresOn: '2026-11-13' }),
});
const trialEndedAccess = buildAccess({
  state: 'TRIAL_ENDED',
  reason: 'TRIAL_EXPIRED',
  turnOnDenialReason: 'TRIAL_ENDED',
  trial: buildTrial('ENDED', { expiresOn: '2026-10-01' }),
});
const notAvailableAccess = buildAccess({
  state: 'UNLICENSED',
  reason: 'NO_LICENSE',
  turnOnDenialReason: 'FORBIDDEN',
});
const unavailableAccess = buildAccess({
  state: 'TRIAL_STATUS_UNAVAILABLE',
  turnOnDenialReason: 'UNAVAILABLE',
});

const buildOrbit = ({ state = null, access = buildAccess() } = {}) => ({
  __typename: 'OrbitNamespace',
  enabled: Boolean(state),
  enabledAt: state ? '2026-10-01T10:00:00Z' : null,
  access,
  indexing: state ? buildIndexing(state) : null,
});

const GROUP_IDS = { acme: 1, beta: 2, gamma: 3, delta: 4, ended: 5 };

const buildGroup = ({
  name,
  isOwner = true,
  state = null,
  access = buildAccess(),
  startOrbitTrial = false,
} = {}) => ({
  __typename: 'Group',
  id: `gid://gitlab/Group/${GROUP_IDS[name]}`,
  name,
  fullPath: name,
  webPath: `/${name}`,
  avatarUrl: null,
  userPermissions: {
    __typename: 'GroupPermissions',
    readOrbitSetting: isOwner,
    startOrbitTrial,
    updateKnowledgeGraphSetting: isOwner,
  },
  orbit: buildOrbit({ state, access: isOwner ? access : null }),
});

const groupsResponse = (nodes, pageInfo = {}, field = 'memberGroups') => ({
  data: {
    orbit: {
      __typename: 'Orbit',
      [field]: {
        __typename: 'GroupConnection',
        nodes,
        pageInfo: {
          __typename: 'PageInfo',
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: null,
          endCursor: null,
          ...pageInfo,
        },
      },
    },
  },
});

const indexingResponse = (nodes) => ({
  data: { orbit: { __typename: 'Orbit', groups: { __typename: 'GroupConnection', nodes } } },
});

const updateResponse = (errors = []) => ({
  data: { orbitUpdate: { __typename: 'OrbitUpdatePayload', group: null, errors } },
});

const startTrialResponse = (errors = []) => ({
  data: { orbitStartTrial: { __typename: 'OrbitStartTrialPayload', errors } },
});

describe('OrbitGroupStatusPage', () => {
  useFakeDate(2026, 9, 11, 12);

  let wrapper;
  let groupsHandler;
  let indexingHandler;
  let updateHandler;
  let startTrialHandler;
  let documentHidden;

  const trialGroup = buildGroup({ name: 'acme', access: eligibleAccess, startOrbitTrial: true });
  const licensedGroup = buildGroup({ name: 'beta' });
  const indexingGroup = buildGroup({ name: 'gamma', state: 'INDEXING' });
  const memberGroup = buildGroup({ name: 'delta', isOwner: false, state: 'READY' });

  const createComponent = ({
    mountFn = shallowMountExtended,
    hidden = false,
    listAllGroups = false,
    saas = true,
  } = {}) => {
    documentHidden = ref(hidden);
    wrapper = mountFn(OrbitGroupStatusPage, {
      provide: { documentHidden, listAllGroups, orbitPlatform: orbitPlatform({ saas }) },
      apolloProvider: createMockApollo(
        [
          [groupStatusGroupsQuery, groupsHandler],
          [groupStatusIndexingQuery, indexingHandler],
          [orbitUpdateMutation, updateHandler],
          [orbitStartTrialMutation, startTrialHandler],
        ],
        {},
        DASHBOARD_CACHE_CONFIG,
      ),
    });
  };

  const findTable = () => wrapper.findComponent(GroupsTable);
  const findTurnOnModal = () => wrapper.findComponent(TurnOnConfirmModal);
  const findTurnOffModal = () => wrapper.findComponent(GroupsConfirmModal);
  const findBulkResult = () => wrapper.findComponent(BulkResultAlert);
  const findWarnings = () => wrapper.findComponent(GroupsWarnings);
  const findInstanceAlert = () =>
    wrapper
      .findAllComponents(GlAlert)
      .wrappers.find(
        (alert) => alert.attributes('data-testid') === 'orbit-group-status-instance-alert',
      );
  const findInstanceSalesButton = () => findInstanceAlert().findComponent(ContactSalesButton);
  const findTrialUnavailableAlert = () => wrapper.findComponent(TrialUnavailableAlert);
  const findRow = (name) =>
    findTable()
      .props('groups')
      .find((row) => row.name === name);

  const selectAndRun = async (paths, action) => {
    findTable().vm.$emit('select', paths);
    await nextTick();
    findTable().vm.$emit('action', action);
    await nextTick();
  };

  beforeEach(() => {
    groupsHandler = jest
      .fn()
      .mockResolvedValue(groupsResponse([trialGroup, licensedGroup, indexingGroup, memberGroup]));
    indexingHandler = jest.fn().mockResolvedValue(indexingResponse([indexingGroup]));
    updateHandler = jest.fn().mockResolvedValue(updateResponse());
    startTrialHandler = jest.fn().mockResolvedValue(startTrialResponse());
  });

  describe('when the page loads', () => {
    beforeEach(async () => {
      window.gon.dot_com = true;
      createComponent();
      await waitForPromises();
    });

    it('loads the first 10 groups of the user', () => {
      expect(groupsHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          listAllGroups: false,
          first: 10,
          search: null,
          enabled: false,
        }),
      );
    });

    it('passes the rows, the filter options, and the actions column to the table', () => {
      expect(findTable().props()).toMatchObject({
        title: 'Groups',
        selectable: true,
        actionsColumn: true,
        serverSearch: true,
        isLoading: false,
        loadError: null,
        filterOptions: [
          expect.objectContaining({ value: 'all' }),
          expect.objectContaining({ value: 'on' }),
        ],
      });
      expect(findTable().props('groups')).toMatchObject([
        { name: 'acme', allowedActions: ['turnOn'], startsTrial: true },
        { name: 'beta', allowedActions: ['turnOn'], startsTrial: false },
        { name: 'gamma', allowedActions: ['turnOff'], indexingState: 'INDEXING' },
        { name: 'delta', allowedActions: [], indexingState: 'READY' },
      ]);
    });

    it('shows the CustomersDot offer on the row of a group that starts a trial', () => {
      expect(findRow('acme').trialBadge.text).toBe('100 credits when turned on');
    });

    it('shows no trial status alert', () => {
      expect(findTrialUnavailableAlert().exists()).toBe(false);
    });

    it('describes what an Owner can do', () => {
      expect(findTable().props('description')).toBe(
        'See the GitLab Orbit status of your groups and turn GitLab Orbit on or off.',
      );
    });

    it('shows no index status warning, and lets the warning say the Owner can still act', () => {
      expect(findWarnings().props()).toMatchObject({
        indexStatusError: null,
        canChangeGroups: true,
      });
    });
  });

  describe('when the user lists all groups, as an admin on self-managed or Dedicated', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue(groupsResponse([licensedGroup], {}, 'allGroups'));
      createComponent({ listAllGroups: true });
      await waitForPromises();
    });

    it('loads every top-level group', () => {
      expect(groupsHandler).toHaveBeenCalledWith(expect.objectContaining({ listAllGroups: true }));
      expect(findTable().props('groups')).toMatchObject([{ name: 'beta' }]);
    });

    it('describes every top-level group', () => {
      expect(findTable().props('description')).toBe(
        'See the GitLab Orbit status of every top-level group and turn GitLab Orbit on or off.',
      );
    });
  });

  describe('when the user is a member of every group', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue(groupsResponse([memberGroup]));
      createComponent();
      await waitForPromises();
    });

    it('hides the checkboxes and the actions column', () => {
      expect(findTable().props()).toMatchObject({ selectable: false, actionsColumn: false });
    });

    it('does not let the warning say the member can turn Orbit on or off', () => {
      expect(findWarnings().props('canChangeGroups')).toBe(false);
    });

    it('says that Owners turn Orbit on or off', () => {
      expect(findTable().props('description')).toBe(
        'See the GitLab Orbit status of your groups. To turn GitLab Orbit on or off, ask an Owner of the top-level group.',
      );
    });
  });

  describe('when an Owner searches and no group matches', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      groupsHandler.mockResolvedValue(groupsResponse([]));
      findTable().vm.$emit('search', 'zz');
      await waitForPromises();
    });

    it('keeps the Owner description and the checkboxes', () => {
      expect(findTable().props()).toMatchObject({
        selectable: true,
        description: 'See the GitLab Orbit status of your groups and turn GitLab Orbit on or off.',
      });
    });
  });

  describe('when an Owner filters to groups where they are only a member', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      groupsHandler.mockResolvedValue(groupsResponse([memberGroup]));
      findTable().vm.$emit('filter', 'on');
      await waitForPromises();
    });

    it('keeps the Owner description and the checkboxes', () => {
      expect(findTable().props()).toMatchObject({
        selectable: true,
        description: 'See the GitLab Orbit status of your groups and turn GitLab Orbit on or off.',
      });
    });
  });

  describe('the actions column', () => {
    const endedGroup = buildGroup({ name: 'ended', access: trialEndedAccess });

    const mountWithGroups = async ({ listAllGroups = false, saas = true } = {}) => {
      const field = listAllGroups ? 'allGroups' : 'memberGroups';
      groupsHandler.mockResolvedValue(
        groupsResponse([indexingGroup, endedGroup, memberGroup], {}, field),
      );
      createComponent({ mountFn: mountExtended, listAllGroups, saas });
      await waitForPromises();
    };

    describe('when an Owner is on GitLab.com', () => {
      beforeEach(async () => {
        await mountWithGroups();
      });

      it('links to the GitLab Credits dashboard of the group that is on', () => {
        expect(wrapper.findAllByTestId('group-view-billing').wrappers).toHaveLength(1);
        expect(wrapper.findByTestId('group-view-billing').text()).toBe('View billing');
        expect(wrapper.findByTestId('group-view-billing').attributes('href')).toBe(
          '/groups/gamma/-/settings/gitlab_credits_dashboard',
        );
      });
    });

    describe('when the user is a self-managed administrator', () => {
      beforeEach(() => mountWithGroups({ listAllGroups: true }));

      it('links each group that is on to the instance GitLab Credits dashboard', () => {
        expect(wrapper.findAllByTestId('group-view-billing').wrappers).toHaveLength(2);
        expect(wrapper.findByTestId('group-view-billing').attributes('href')).toBe(
          '/admin/gitlab_credits_dashboard',
        );
      });
    });

    describe('when an Owner is off GitLab.com and is not an administrator', () => {
      beforeEach(() => mountWithGroups({ saas: false }));

      it('shows no billing link', () => {
        expect(wrapper.findByTestId('group-view-billing').exists()).toBe(false);
      });
    });

    describe('when a trial ended', () => {
      beforeEach(() => mountWithGroups());

      it('offers the small hand-raise Contact sales button for that group', () => {
        expect(wrapper.findAllComponents(ContactSalesButton)).toHaveLength(1);
        expect(wrapper.findComponent(ContactSalesButton).props()).toMatchObject({
          glmContent: 'orbit-group-status',
          size: 'small',
          namespaceId: 5,
        });
      });
    });
  });

  describe('when one group on GitLab.com has an active trial and another an ended trial', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue(
        groupsResponse([
          buildGroup({ name: 'acme', access: instanceTrialAccess }),
          buildGroup({ name: 'beta', access: trialEndedAccess }),
        ]),
      );
      createComponent({ mountFn: mountExtended });
      await waitForPromises();
    });

    it('shows no instance alert', () => {
      expect(findInstanceAlert()).toBeUndefined();
    });

    it('gives no instance trial end date to the turn-on confirm', () => {
      expect(findTurnOnModal().props('instanceTrialEndsOn')).toBeNull();
    });
  });

  describe('when CustomersDot does not answer for a group', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue(
        groupsResponse([buildGroup({ name: 'acme', access: unavailableAccess })]),
      );
      createComponent();
      await waitForPromises();
    });

    it('shows the trial status alert with the hand-raise Contact sales button', () => {
      expect(findTrialUnavailableAlert().props()).toEqual({
        glmContent: 'orbit-group-status',
        namespaceId: 1,
        reloading: false,
      });
    });

    it('loads the groups again from Try again', async () => {
      findTrialUnavailableAlert().vm.$emit('retry');
      await waitForPromises();

      expect(groupsHandler).toHaveBeenCalledTimes(2);
    });
  });

  describe('on GitLab Self-Managed', () => {
    const mountWith = async (groups) => {
      groupsHandler.mockResolvedValue(groupsResponse(groups));
      createComponent({ mountFn: mountExtended, saas: false });
      await waitForPromises();
    };

    describe('during the instance trial', () => {
      const instanceTrialGroup = buildGroup({ name: 'acme', access: instanceTrialAccess });

      beforeEach(async () => {
        await mountWith([instanceTrialGroup]);
      });

      it('says that all groups share the instance trial until its end date', () => {
        expect(findInstanceAlert().props()).toMatchObject({
          variant: 'info',
          title: 'Trial for this instance',
        });
        expect(findInstanceAlert().text()).toContain(
          'This instance has a GitLab Orbit trial until Nov 13, 2026.',
        );
      });

      it('offers no Contact sales in the alert', () => {
        expect(findInstanceSalesButton().exists()).toBe(false);
      });

      it('gives the end date of the instance trial to the turn-on confirm', async () => {
        await selectAndRun(['acme'], 'turnOn');

        expect(findTurnOnModal().props('instanceTrialEndsOn')).toBe('2026-11-13');
      });
    });

    describe('when the instance trial ended', () => {
      beforeEach(async () => {
        await mountWith([buildGroup({ name: 'acme', access: trialEndedAccess })]);
      });

      it('says the trial ended, indexing continues, and offers the Contact sales link', () => {
        expect(findInstanceAlert().props()).toMatchObject({
          variant: 'warning',
          title: 'The trial of this instance has ended',
        });
        expect(findInstanceAlert().text()).toContain(
          'GitLab Orbit keeps indexing your groups. GitLab Orbit queries are paused. Ask your administrator, or contact sales.',
        );
        expect(findInstanceSalesButton().props()).toMatchObject({
          glmContent: 'orbit-group-status',
        });
      });

      it('offers no Contact sales in the rows', () => {
        expect(wrapper.findAllComponents(ContactSalesButton)).toHaveLength(1);
      });
    });

    describe('when Orbit is not available on the instance', () => {
      beforeEach(async () => {
        await mountWith([buildGroup({ name: 'acme', access: notAvailableAccess })]);
      });

      it('says Orbit is not available and offers the Contact sales link', () => {
        expect(findInstanceAlert().props()).toMatchObject({
          variant: 'info',
          title: 'Get GitLab Orbit for this instance',
        });
        expect(findInstanceAlert().text()).toContain('Ask your administrator, or contact sales.');
        expect(findInstanceSalesButton().exists()).toBe(true);
      });

      it('says the group is not available on this instance', () => {
        expect(findRow('acme').note).toBe('Contact sales to get GitLab Orbit for this instance.');
      });
    });

    describe('when every group is on and the instance is not eligible for a trial', () => {
      beforeEach(async () => {
        await mountWith([
          buildGroup({
            name: 'acme',
            state: 'READY',
            access: buildAccess({ state: 'TRIAL_NOT_ELIGIBLE', trial: buildTrial('NOT_ELIGIBLE') }),
          }),
        ]);
      });

      it('shows no instance alert', () => {
        expect(findRow('acme').isOn).toBe(true);
        expect(findInstanceAlert()).toBeUndefined();
      });
    });

    describe('when the user manages no group', () => {
      beforeEach(async () => {
        await mountWith([memberGroup]);
      });

      it('shows no instance alert', () => {
        expect(findInstanceAlert()).toBeUndefined();
      });
    });

    // A beta group keeps Orbit after the instance trial, so its row never shows the trial-ended alert.
    describe('when a beta group is on after the instance trial ended', () => {
      beforeEach(async () => {
        await mountWith([
          buildGroup({ name: 'acme', state: 'READY', access: buildAccess({ reason: 'BETA' }) }),
        ]);
      });

      it('shows no trial-ended instance alert', () => {
        expect(findRow('acme').turnOnAction).toBe('turn_on');
        expect(findInstanceAlert()).toBeUndefined();
      });
    });

    describe('when every managed group is beta during an active instance trial', () => {
      beforeEach(async () => {
        await mountWith([buildGroup({ name: 'acme', access: buildAccess({ reason: 'BETA' }) })]);
      });

      it('shows no instance trial alert', () => {
        expect(findInstanceAlert()).toBeUndefined();
      });

      it('gives no instance trial end date to the turn-on confirm', async () => {
        await selectAndRun(['acme'], 'turnOn');

        expect(findTurnOnModal().props('instanceTrialEndsOn')).toBeNull();
      });
    });
  });

  describe('when the Owner turns on groups', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      await selectAndRun(['acme', 'beta'], 'turnOn');
    });

    it('asks for confirmation and lists the trial of each group', () => {
      expect(findTurnOnModal().props()).toMatchObject({
        visible: true,
        groups: [
          { fullPath: 'acme', name: 'acme', startsTrial: true, offer },
          { fullPath: 'beta', name: 'beta', startsTrial: false, offer: null },
        ],
      });
    });

    describe('and confirms', () => {
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
        findTurnOnModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('tracks the turn on of a trial group and a licensed group', () => {
        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_orbit_turn_on_from_group_status',
          { label: 'mixed', value: 2 },
          undefined,
        );
      });

      it('starts the trial of the eligible group and turns on the licensed group', () => {
        expect(startTrialHandler).toHaveBeenCalledWith({ groupPath: 'acme' });
        expect(updateHandler).toHaveBeenCalledWith({
          input: { groupPath: 'beta', enabled: true },
        });
      });

      it('shows the result, closes the modal, and refetches the groups', () => {
        expect(findBulkResult().props('result')).toEqual({
          action: 'turnOn',
          total: 2,
          failed: [],
        });
        expect(findTurnOnModal().props('visible')).toBe(false);
        expect(groupsHandler).toHaveBeenCalledTimes(2);
      });

      it('keeps the groups in the modal', () => {
        expect(findTurnOnModal().props('groups')).toHaveLength(2);
      });

      it('tells the dashboard that the groups changed', () => {
        expect(wrapper.emitted('groups-changed')).toHaveLength(1);
      });
    });
  });

  describe('when a group does not turn on', () => {
    beforeEach(async () => {
      startTrialHandler.mockResolvedValue(startTrialResponse(['CustomersDot did not answer.']));
      createComponent();
      await waitForPromises();
      await selectAndRun(['acme', 'beta'], 'turnOn');
      findTurnOnModal().vm.$emit('confirm');
      await waitForPromises();
    });

    it('lists the failed group, marks its row, and keeps it selected', () => {
      expect(findBulkResult().props('result').failed).toEqual([
        { name: 'acme', fullPath: 'acme', message: 'CustomersDot did not answer.' },
      ]);
      expect(findRow('acme').note).toBe('CustomersDot did not answer.');
      expect(findTable().props('selectedPaths')).toEqual(['acme']);
    });

    it('runs each mutation once, and offers to try again', () => {
      expect(startTrialHandler).toHaveBeenCalledTimes(1);
      expect(updateHandler).toHaveBeenCalledTimes(1);
      expect(findBulkResult().props('canRetry')).toBe(true);
    });

    describe('and the Owner retries from the alert', () => {
      beforeEach(async () => {
        findBulkResult().vm.$emit('retry');
        await waitForPromises();
      });

      it('starts the trial of the failed group again, and only that group', () => {
        expect(startTrialHandler).toHaveBeenCalledTimes(2);
        expect(startTrialHandler).toHaveBeenLastCalledWith({ groupPath: 'acme' });
        expect(updateHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('when a trial does not start and the group can no longer start one', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValueOnce(groupsResponse([trialGroup]));
      groupsHandler.mockResolvedValue(
        groupsResponse([
          {
            ...trialGroup,
            orbit: buildOrbit({
              access: buildAccess({
                state: 'TRIAL_NOT_ELIGIBLE',
                turnOnDenialReason: 'TRIAL_REQUIRED',
                trial: buildTrial('NOT_ELIGIBLE'),
              }),
            }),
          },
        ]),
      );
      startTrialHandler.mockResolvedValue(startTrialResponse(['Not eligible.']));
      createComponent();
      await waitForPromises();
      await selectAndRun(['acme'], 'turnOn');
      findTurnOnModal().vm.$emit('confirm');
      await waitForPromises();
    });

    it('lists the failed group, and offers no Try again', () => {
      expect(findBulkResult().props()).toMatchObject({
        result: { failed: [{ name: 'acme', fullPath: 'acme', message: 'Not eligible.' }] },
        canRetry: false,
      });
    });

    it('does not keep the group selected', () => {
      expect(findTable().props('selectedPaths')).toEqual([]);
    });
  });

  describe('when a request does not reach GitLab', () => {
    beforeEach(async () => {
      updateHandler.mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();
      await selectAndRun(['beta'], 'turnOn');
      findTurnOnModal().vm.$emit('confirm');
      await waitForPromises();
    });

    it('lists the network error and reports it to Sentry once', () => {
      expect(findBulkResult().props('result').failed).toEqual([
        {
          name: 'beta',
          fullPath: 'beta',
          message: NETWORK_ERROR_MESSAGE,
        },
      ]);
      expect(Sentry.captureException).toHaveBeenCalledTimes(1);
      expect(wrapper.emitted('groups-changed')).toBeUndefined();
    });
  });

  describe('when the Owner turns off a group', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      await selectAndRun(['gamma'], 'turnOff');
    });

    it('tracks the click and asks for confirmation', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith('click_orbit_turn_off_indexing', {}, undefined);
      expect(findTurnOffModal().props()).toMatchObject({
        kind: 'turnOff',
        autoIndexEnabled: false,
        groups: [expect.objectContaining({ name: 'gamma' })],
      });
    });

    describe('and confirms', () => {
      beforeEach(async () => {
        findTurnOffModal().vm.$emit('confirm', 'turnOff');
        findTurnOffModal().vm.$emit('cancel');
        await waitForPromises();
      });

      it('turns off the group', () => {
        expect(updateHandler).toHaveBeenCalledWith({
          input: { groupPath: 'gamma', enabled: false },
        });
        expect(findTurnOffModal().props('kind')).toBe(null);
      });
    });
  });

  describe('index status polling', () => {
    // Apollo notifies the watching queries from a timer after the poll writes the cache.
    const pollOnce = async () => {
      jest.advanceTimersByTime(GROUPS_POLL_INTERVAL_MS);
      await waitForPromises();
      jest.advanceTimersByTime(0);
      await waitForPromises();
    };

    beforeEach(() => {
      jest.useFakeTimers({ legacyFakeTimers: false });
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    describe('while a group indexes', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('does not load the index status that the groups query returned', () => {
        expect(indexingHandler).not.toHaveBeenCalled();
      });

      describe('and 20 seconds pass', () => {
        beforeEach(pollOnce);

        it('loads only the index status of the indexing groups', () => {
          expect(indexingHandler).toHaveBeenCalledTimes(1);
          expect(indexingHandler).toHaveBeenCalledWith({
            ids: ['gid://gitlab/Group/3'],
            first: 1,
          });
          expect(groupsHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('and Orbit throttles a poll', () => {
        beforeEach(async () => {
          indexingHandler.mockResolvedValue({
            ...indexingResponse([
              { ...indexingGroup, orbit: { ...indexingGroup.orbit, indexing: null } },
            ]),
            errors: [{ message: 'Orbit rate limit reached' }],
          });
          await pollOnce();
        });

        it('keeps the last status, shows the warning, and keeps polling', async () => {
          expect(findRow('gamma').indexingState).toBe('INDEXING');
          expect(findWarnings().props('indexStatusError')).toBe('Orbit rate limit reached');
          expect(indexingHandler).toHaveBeenCalledTimes(1);

          await pollOnce();

          expect(indexingHandler).toHaveBeenCalledTimes(2);
        });

        describe('and the Owner turns off the indexing group', () => {
          beforeEach(async () => {
            groupsHandler.mockResolvedValue(
              groupsResponse([trialGroup, licensedGroup, buildGroup({ name: 'gamma' })]),
            );
            await selectAndRun(['gamma'], 'turnOff');
            findTurnOffModal().vm.$emit('confirm', 'turnOff');
            await waitForPromises();
          });

          it('stops polling and clears the warning', async () => {
            expect(findWarnings().props('indexStatusError')).toBe(null);

            await pollOnce();

            expect(indexingHandler).toHaveBeenCalledTimes(1);
          });
        });
      });

      describe('and a poll does not reach GitLab', () => {
        beforeEach(async () => {
          indexingHandler.mockRejectedValue(new Error('Network error'));
          await pollOnce();
        });

        it('keeps the last status, shows the warning, and keeps polling', async () => {
          expect(findRow('gamma').indexingState).toBe('INDEXING');
          expect(findWarnings().props('indexStatusError')).toBe(NETWORK_ERROR_MESSAGE);
          expect(indexingHandler).toHaveBeenCalledTimes(1);

          await pollOnce();

          expect(indexingHandler).toHaveBeenCalledTimes(2);
        });
      });

      describe('and the index becomes ready', () => {
        beforeEach(async () => {
          indexingHandler.mockResolvedValue(
            indexingResponse([{ ...indexingGroup, orbit: buildOrbit({ state: 'READY' }) }]),
          );
          await pollOnce();
        });

        it('shows the group as indexed and stops polling', async () => {
          expect(findRow('gamma').indexingState).toBe('READY');
          expect(indexingHandler).toHaveBeenCalledTimes(1);

          await pollOnce();

          expect(indexingHandler).toHaveBeenCalledTimes(1);
        });
      });
    });

    describe('when the Owner turns on a group', () => {
      beforeEach(async () => {
        groupsHandler.mockResolvedValue(groupsResponse([licensedGroup]));
        createComponent();
        await waitForPromises();
        groupsHandler.mockResolvedValue(
          groupsResponse([
            {
              ...licensedGroup,
              orbit: {
                ...licensedGroup.orbit,
                enabled: true,
                enabledAt: new Date().toISOString(),
                indexing: null,
              },
            },
          ]),
        );
        await selectAndRun(['beta'], 'turnOn');
        findTurnOnModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('shows the group as queued and does not load its index status yet', () => {
        expect(findRow('beta').indexingState).toBe('NOT_STARTED');
        expect(indexingHandler).not.toHaveBeenCalled();
      });

      it('loads the index status of the group 20 seconds later', async () => {
        expect(indexingHandler).not.toHaveBeenCalled();

        await pollOnce();

        expect(indexingHandler).toHaveBeenCalledTimes(1);
        expect(indexingHandler).toHaveBeenCalledWith({
          ids: ['gid://gitlab/Group/2'],
          first: 1,
        });
      });
    });

    describe('while the browser tab is hidden', () => {
      beforeEach(async () => {
        createComponent({ hidden: true });
        await waitForPromises();
        await pollOnce();
      });

      it('does not load the index status', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(1);
        expect(indexingHandler).not.toHaveBeenCalled();
      });

      describe('and the tab is visible again', () => {
        beforeEach(async () => {
          documentHidden.value = false;
          await waitForPromises();
          await pollOnce();
        });

        it('loads the index status', () => {
          expect(indexingHandler).toHaveBeenCalledTimes(1);
        });
      });
    });
  });

  describe('when Orbit does not return the index status', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue({
        ...groupsResponse([
          { ...indexingGroup, orbit: { ...indexingGroup.orbit, indexing: null } },
        ]),
        errors: [{ message: 'Knowledge graph request failed' }],
      });
      createComponent();
      await waitForPromises();
    });

    it('shows the server message in the warning and keeps the rows', () => {
      expect(findWarnings().props('indexStatusError')).toBe('Knowledge graph request failed');
      expect(findRow('gamma').indexingState).toBe(null);
    });
  });

  describe('when the user is a member of only a subgroup', () => {
    const buildSubgroup = (orbit) => ({
      ...buildGroup({ name: 'team', isOwner: false }),
      fullPath: 'root/team',
      orbit,
    });

    it('shows the subgroup as not started right after its top-level group is turned on', async () => {
      const orbit = { ...buildOrbit(), enabled: true, enabledAt: new Date().toISOString() };
      groupsHandler.mockResolvedValue(groupsResponse([buildSubgroup(orbit)]));
      createComponent();
      await waitForPromises();

      expect(findRow('team')).toMatchObject({ allowedActions: [], indexingState: 'NOT_STARTED' });
    });

    it('asks an Owner of the top-level group to turn on Orbit', async () => {
      groupsHandler.mockResolvedValue(groupsResponse([buildSubgroup(buildOrbit())]));
      createComponent();
      await waitForPromises();

      expect(findRow('team')).toMatchObject({
        allowedActions: [],
        note: 'Ask an Owner of the top-level group to turn on GitLab Orbit.',
      });
    });
  });

  describe.each`
    backend                                       | response
    ${'does not return Query.orbit'}              | ${{ data: { orbit: null } }}
    ${'returns Query.orbit without memberGroups'} | ${{ data: { orbit: { __typename: 'Orbit', memberGroups: null } } }}
  `('when an older backend $backend', ({ response }) => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue(response);
      createComponent();
      await waitForPromises();
    });

    it('says Orbit is not available instead of showing no groups', () => {
      expect(findTable().props('loadError')).toBe(
        'GitLab Orbit is not available right now. Try again later.',
      );
    });
  });

  describe('when the groups load and a refetch does not reach GitLab', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      groupsHandler.mockRejectedValue(new Error('Network error'));
      findTable().vm.$emit('retry');
      await waitForPromises();
    });

    it('shows the error in the table', () => {
      expect(findTable().props('loadError')).toBe(NETWORK_ERROR_MESSAGE);
    });
  });

  describe('when the groups do not load', () => {
    beforeEach(async () => {
      groupsHandler.mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();
    });

    it('shows the error in the table', () => {
      expect(findTable().props('loadError')).toBe(NETWORK_ERROR_MESSAGE);
    });

    it('loads the groups again from Try again', async () => {
      groupsHandler.mockResolvedValue(groupsResponse([licensedGroup]));
      findTable().vm.$emit('retry');
      await waitForPromises();

      expect(findTable().props('loadError')).toBe(null);
      expect(findTable().props('groups')).toMatchObject([{ name: 'beta' }]);
    });
  });

  describe('when GitLab refuses access to the groups', () => {
    beforeEach(async () => {
      groupsHandler.mockRejectedValue(Object.assign(new Error('Forbidden'), { statusCode: 403 }));
      createComponent();
      await waitForPromises();
    });

    it('asks the user to sign in again, not to turn on admin mode', () => {
      expect(findTable().props('loadError')).toBe(
        'You do not have access to the group list. Sign in again, then reload the page.',
      );
    });
  });

  describe('when the user searches, filters, and pages', () => {
    beforeEach(async () => {
      groupsHandler.mockResolvedValue(
        groupsResponse([licensedGroup], { hasNextPage: true, endCursor: 'end' }),
      );
      createComponent();
      await waitForPromises();
    });

    it('loads the matching groups that have Orbit on', async () => {
      findTable().vm.$emit('search', 'be');
      findTable().vm.$emit('filter', 'on');
      await waitForPromises();

      expect(groupsHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ search: 'be', enabled: true, first: 10 }),
      );
    });

    it('loads the next page after the end cursor', async () => {
      findTable().vm.$emit('next', 'end');
      await waitForPromises();

      expect(groupsHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ first: 10, after: 'end' }),
      );
    });
  });
});
