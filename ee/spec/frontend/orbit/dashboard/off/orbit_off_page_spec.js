import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlBadge, GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import OrbitOffPage from 'ee/orbit/dashboard/off/orbit_off_page.vue';
import OffGroupsTable from 'ee/orbit/dashboard/off/off_groups_table.vue';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import TrialUnavailableAlert from 'ee/orbit/components/trial/trial_unavailable_alert.vue';
import TurnOnConfirmModal from 'ee/orbit/shared/groups/turn_on_confirm_modal.vue';
import offOwnedGroupsQuery from 'ee/orbit/dashboard/off/graphql/off_owned_groups.query.graphql';
import orbitStartTrialMutation from 'ee/orbit/graphql/mutations/orbit_start_trial.mutation.graphql';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import { orbitPlatform } from '../../mock_data';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const offer = { durationDays: 30, initialCredits: 100 };

const trial = (state, expiresOn = null) => ({ state, expiresOn, offer: null });

const access = ({
  state = 'TRIAL_ELIGIBLE',
  reason = null,
  turnOnDenialReason = 'TRIAL_REQUIRED',
  trial: groupTrial = { state: 'ELIGIBLE', expiresOn: null, offer },
} = {}) => ({ state, reason, turnOnDenialReason, trial: groupTrial });

const ACCESS = {
  beta: access({ state: 'LICENSED', reason: 'PLAN', turnOnDenialReason: null, trial: null }),
  purchased: access({
    state: 'LICENSED',
    reason: 'PROMO_ADD_ON',
    turnOnDenialReason: null,
    trial: null,
  }),
  freePlan: access({
    state: 'UNLICENSED',
    reason: 'FREE_PLAN',
    turnOnDenialReason: 'FORBIDDEN',
    trial: null,
  }),
  noLicense: access({
    state: 'UNLICENSED',
    reason: 'NO_LICENSE',
    turnOnDenialReason: 'FORBIDDEN',
    trial: null,
  }),
  purchaseRequired: access({
    state: 'UNLICENSED',
    reason: 'NO_ACCESS',
    turnOnDenialReason: 'PURCHASE_REQUIRED',
    trial: null,
  }),
  notEligible: access({ state: 'TRIAL_NOT_ELIGIBLE', trial: trial('NOT_ELIGIBLE') }),
  noOffer: access({ trial: trial('ELIGIBLE') }),
  expired: access({
    state: 'TRIAL_ENDED',
    reason: 'TRIAL_EXPIRED',
    turnOnDenialReason: 'TRIAL_ENDED',
    trial: trial('ENDED', '2026-10-01'),
  }),
  creditsExhausted: access({
    state: 'TRIAL_ENDED',
    reason: 'CREDITS_EXHAUSTED',
    turnOnDenialReason: 'TRIAL_ENDED',
    trial: trial('ENDED', '2099-01-01'),
  }),
  active: access({
    state: 'TRIAL_ACTIVE',
    turnOnDenialReason: null,
    trial: trial('ACTIVE', '2026-11-13'),
  }),
  unavailable: access({
    state: 'TRIAL_STATUS_UNAVAILABLE',
    turnOnDenialReason: 'UNAVAILABLE',
    trial: null,
  }),
};

const buildGroup = ({
  id = 1,
  name = 'acme',
  startOrbitTrial = true,
  groupAccess = access(),
} = {}) => ({
  id: `gid://gitlab/Group/${id}`,
  name,
  fullPath: name,
  avatarUrl: null,
  userPermissions: { startOrbitTrial },
  orbit: { access: groupAccess },
});

const groupsResponse = (nodes, hasNextPage = false) => ({
  data: { orbit: { __typename: 'Orbit', groups: { pageInfo: { hasNextPage }, nodes } } },
});

const mutationResponse = (root, errors = []) => ({
  data: { [root]: root === 'orbitUpdate' ? { group: null, errors } : { errors } },
});

describe('OrbitOffPage', () => {
  let wrapper;
  let groupsHandler;
  let startTrialHandler;
  let updateHandler;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const createComponent = async ({
    groups = [buildGroup()],
    startTrialResponse = mutationResponse('orbitStartTrial'),
    updateResponse = mutationResponse('orbitUpdate'),
    groupsHandlerFn = null,
    saas = true,
  } = {}) => {
    groupsHandler = groupsHandlerFn || jest.fn().mockResolvedValue(groupsResponse(groups));
    startTrialHandler = jest.fn().mockResolvedValue(startTrialResponse);
    updateHandler = jest.fn().mockResolvedValue(updateResponse);

    wrapper = shallowMountExtended(OrbitOffPage, {
      apolloProvider: createMockApollo([
        [offOwnedGroupsQuery, groupsHandler],
        [orbitStartTrialMutation, startTrialHandler],
        [orbitUpdateMutation, updateHandler],
      ]),
      provide: { orbitPlatform: orbitPlatform({ saas }) },
      stubs: { GlEmptyState },
    });
    await waitForPromises();
  };

  const findTitle = () => wrapper.find('h1');
  const findDetail = () => wrapper.findByTestId('orbit-off-detail');
  const findTable = () => wrapper.findComponent(OffGroupsTable);
  const findTurnOnButton = () => wrapper.findComponentByTestId('orbit-off-turn-on');
  const findModal = () => wrapper.findComponent(TurnOnConfirmModal);
  const findAskOwner = () => wrapper.findByTestId('orbit-off-ask-owner');
  const findUnavailableAlert = () => wrapper.findComponent(TrialUnavailableAlert);
  const findHeaderSales = () => wrapper.findComponent(ContactSalesButton);
  const findLoadError = () => wrapper.findComponentByTestId('orbit-off-load-error');
  const findSummary = () => wrapper.findByTestId('orbit-off-selected-summary');

  const confirmTurnOn = async () => {
    findTurnOnButton().vm.$emit('click');
    await waitForPromises();
    findModal().vm.$emit('confirm');
    await waitForPromises();
  };

  describe('while the groups load', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows a spinner', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    });
  });

  describe('when the Owner has one group that can start a trial', () => {
    beforeEach(() => createComponent());

    it('shows the trial with the offer from CustomersDot', () => {
      expect(wrapper.find('h1').text()).toBe('Try GitLab Orbit');
      expect(findDetail().text()).toContain(
        'each eligible group gets its own 100 credits for GitLab Orbit, valid for 30 days.',
      );
    });

    it('selects the group', () => {
      expect(findTable().props('selected')).toEqual(['acme']);
      expect(findTurnOnButton().props('disabled')).toBe(false);
    });

    it('does not show the selection summary', () => {
      expect(findSummary().exists()).toBe(false);
    });

    it('tells the Owner how to get Orbit in other groups', () => {
      expect(wrapper.findByTestId('orbit-off-other-groups').text()).toBe(
        'To use GitLab Orbit in another group, ask an Owner of that group to turn it on.',
      );
    });

    it('does not say that the list is cut', () => {
      expect(wrapper.findByTestId('orbit-off-more-groups').exists()).toBe(false);
    });

    describe('and clicks Turn on Orbit', () => {
      beforeEach(async () => {
        findTurnOnButton().vm.$emit('click');
        await waitForPromises();
      });

      it('opens the confirm modal for the group and its offer', () => {
        expect(findModal().props()).toMatchObject({
          visible: true,
          groups: [{ fullPath: 'acme', name: 'acme', startsTrial: true, offer }],
          loading: false,
        });
      });

      describe('and cancels', () => {
        beforeEach(async () => {
          findModal().vm.$emit('hide');
          await waitForPromises();
        });

        it('closes the modal', () => {
          expect(findModal().props('visible')).toBe(false);
        });

        describe('and clicks Turn on Orbit again', () => {
          beforeEach(async () => {
            findTurnOnButton().vm.$emit('click');
            await waitForPromises();
          });

          it('opens the modal again', () => {
            expect(findModal().props('visible')).toBe(true);
          });
        });
      });
    });

    describe('while the trial starts', () => {
      beforeEach(async () => {
        startTrialHandler.mockReturnValue(new Promise(() => {}));
        await confirmTurnOn();
      });

      it('shows the modal and the Turn on Orbit button as loading', () => {
        expect(findModal().props('loading')).toBe(true);
        expect(findTurnOnButton().props('loading')).toBe(true);
      });
    });

    describe('and confirms Turn on Orbit', () => {
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
        await confirmTurnOn();
      });

      it('starts the trial', () => {
        expect(startTrialHandler).toHaveBeenCalledWith({ groupPath: 'acme' });
        expect(updateHandler).not.toHaveBeenCalled();
      });

      it('emits turned-on', () => {
        expect(wrapper.emitted('turned-on')).toHaveLength(1);
      });

      it('tracks the confirmation with the kind of turn on and the number of groups', () => {
        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_orbit_turn_on_from_off_page',
          { label: 'start_trial', value: 1 },
          undefined,
        );
      });
    });
  });

  describe('when CustomersDot sends no offer', () => {
    beforeEach(() =>
      createComponent({
        groups: [buildGroup({ groupAccess: ACCESS.noOffer })],
      }),
    );

    it('mentions the trial and no offer numbers', () => {
      expect(findDetail().text()).toContain('each eligible group starts its own trial.');
    });
  });

  describe('when the Owner has several groups', () => {
    const groups = [
      buildGroup({ id: 1, name: 'acme' }),
      buildGroup({ id: 2, name: 'beta-group', startOrbitTrial: false, groupAccess: ACCESS.beta }),
    ];

    beforeEach(() => createComponent({ groups }));

    it('selects no group and disables Turn on Orbit', () => {
      expect(findTable().props('selected')).toEqual([]);
      expect(findTurnOnButton().props('disabled')).toBe(true);
      expect(findSummary().text()).toBe('0 of 2 groups selected');
    });

    describe('and selects both', () => {
      beforeEach(async () => {
        findTable().vm.$emit('update:selected', ['acme', 'beta-group']);
        findTurnOnButton().vm.$emit('click');
        await waitForPromises();
      });

      it('passes both groups and what turning on does for each to the modal', () => {
        expect(findModal().props('groups')).toMatchObject([
          { fullPath: 'acme', startsTrial: true, offer },
          { fullPath: 'beta-group', startsTrial: false },
        ]);
      });
    });

    describe('and confirms Turn on GitLab Orbit for both', () => {
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
        findTable().vm.$emit('update:selected', ['acme', 'beta-group']);
        await confirmTurnOn();
      });

      it('tracks a mixed turn on of two groups', () => {
        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_orbit_turn_on_from_off_page',
          { label: 'mixed', value: 2 },
          undefined,
        );
      });

      it('starts a trial for the trial group and turns on the other group', () => {
        expect(startTrialHandler).toHaveBeenCalledWith({ groupPath: 'acme' });
        expect(updateHandler).toHaveBeenCalledWith({
          input: { groupPath: 'beta-group', enabled: true },
        });
      });
    });
  });

  describe('when one of two selected groups fails to turn on', () => {
    beforeEach(async () => {
      await createComponent({
        groups: [
          buildGroup({ id: 1, name: 'acme' }),
          buildGroup({
            id: 2,
            name: 'beta-group',
            startOrbitTrial: false,
            groupAccess: ACCESS.beta,
          }),
        ],
        updateResponse: mutationResponse('orbitUpdate', ['Orbit cannot be turned on.']),
      });
      findTable().vm.$emit('update:selected', ['acme', 'beta-group']);
      await confirmTurnOn();
    });

    it('alerts with the group and the reason, and emits turned-on', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Could not turn on GitLab Orbit for beta-group',
        message: 'Orbit cannot be turned on.',
      });
      expect(wrapper.emitted('turned-on')).toHaveLength(1);
    });

    it('does not report the error to Sentry', () => {
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });
  });

  describe('when two selected groups fail for different reasons', () => {
    beforeEach(async () => {
      await createComponent({
        groups: [buildGroup({ id: 1, name: 'acme' }), buildGroup({ id: 2, name: 'data-eng' })],
      });
      startTrialHandler
        .mockResolvedValueOnce(mutationResponse('orbitStartTrial', ['Not eligible.']))
        .mockResolvedValueOnce(mutationResponse('orbitStartTrial', ['Not available right now.']));
      findTable().vm.$emit('update:selected', ['acme', 'data-eng']);
      await confirmTurnOn();
    });

    it('alerts with the reason of each group', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Could not turn on GitLab Orbit for acme and data-eng',
        message: 'acme: Not eligible. data-eng: Not available right now.',
      });
    });
  });

  describe('when every selected group fails to turn on', () => {
    const failureAlert = { dismiss: jest.fn() };

    beforeEach(async () => {
      createAlert.mockReturnValue(failureAlert);
      await createComponent({
        startTrialResponse: mutationResponse('orbitStartTrial', ['This group is not eligible.']),
      });
      await confirmTurnOn();
    });

    it('keeps the alert of the failed turn on', () => {
      expect(failureAlert.dismiss).not.toHaveBeenCalled();
    });

    describe('and the Owner turns on Orbit again', () => {
      beforeEach(async () => {
        startTrialHandler.mockResolvedValue(mutationResponse('orbitStartTrial'));
        await confirmTurnOn();
      });

      it('removes the alert of the failed turn on', () => {
        expect(failureAlert.dismiss).toHaveBeenCalled();
        expect(wrapper.emitted('turned-on')).toHaveLength(1);
      });
    });

    it('alerts, stays on the page, and reloads the groups', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Could not turn on GitLab Orbit for acme' }),
      );
      expect(wrapper.emitted('turned-on')).toBeUndefined();
      expect(groupsHandler).toHaveBeenCalledTimes(2);
    });

    it('keeps the group selected', () => {
      expect(findTable().props('selected')).toEqual(['acme']);
    });

    it('closes the confirm modal', () => {
      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('when the server rejects the mutation with a GraphQL error', () => {
    beforeEach(async () => {
      await createComponent();
      startTrialHandler.mockResolvedValue({ errors: [{ message: 'Insufficient permissions.' }] });
      await confirmTurnOn();
    });

    it('alerts with the server message and does not report to Sentry', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Could not turn on GitLab Orbit for acme',
        message: 'Insufficient permissions.',
      });
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });
  });

  describe('while the groups reload after a failed turn on', () => {
    beforeEach(async () => {
      await createComponent({
        startTrialResponse: mutationResponse('orbitStartTrial', ['This group is not eligible.']),
      });
      groupsHandler.mockReturnValue(new Promise(() => {}));
      await confirmTurnOn();
    });

    it('keeps the groups on screen with no spinner', () => {
      expect(groupsHandler).toHaveBeenCalledTimes(2);
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(false);
      expect(findTable().exists()).toBe(true);
    });
  });

  describe('when the mutation request fails', () => {
    const error = new Error('Network error');

    beforeEach(async () => {
      await createComponent();
      startTrialHandler.mockRejectedValue(error);
      await confirmTurnOn();
    });

    it('reports the error to Sentry and alerts with a generic reason', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Could not turn on GitLab Orbit for acme',
        message: 'Could not turn on GitLab Orbit. Try again.',
      });
    });
  });

  describe.each`
    description                                        | groups                                                                                                                                           | title                                                  | detail
    ${'every group is on a plan without Orbit'}        | ${[buildGroup({ groupAccess: ACCESS.freePlan })]}                                                                                                | ${'GitLab Orbit is available on Premium and Ultimate'} | ${'Contact sales to upgrade'}
    ${'every group must buy Orbit'}                    | ${[buildGroup({ groupAccess: ACCESS.purchaseRequired })]}                                                                                        | ${'GitLab Orbit is not available for your groups'}     | ${'Contact sales to get GitLab Orbit for your groups.'}
    ${'no group is eligible for a trial'}              | ${[buildGroup({ groupAccess: ACCESS.notEligible })]}                                                                                             | ${'GitLab Orbit is not available for your groups'}     | ${'Contact sales to get GitLab Orbit for your groups.'}
    ${'the trial of the only group has ended'}         | ${[buildGroup({ groupAccess: ACCESS.expired })]}                                                                                                 | ${'Your GitLab Orbit trial has ended'}                 | ${'Contact sales to keep using GitLab Orbit for your groups.'}
    ${'one trial expired and one ran out of credits'}  | ${[buildGroup({ id: 1, name: 'acme', groupAccess: ACCESS.expired }), buildGroup({ id: 2, name: 'data', groupAccess: ACCESS.creditsExhausted })]} | ${'Your GitLab Orbit trials have ended'}               | ${'Contact sales to keep using GitLab Orbit for your groups.'}
    ${'one trial ended and one group is not eligible'} | ${[buildGroup({ id: 1, name: 'acme', groupAccess: ACCESS.expired }), buildGroup({ id: 2, name: 'data', groupAccess: ACCESS.notEligible })]}      | ${'Your GitLab Orbit trial has ended'}                 | ${'Contact sales to keep using GitLab Orbit for your groups.'}
  `('when $description', ({ groups, title, detail }) => {
    beforeEach(() => createComponent({ groups }));

    it('shows the title, the detail, and no Turn on Orbit button', () => {
      expect(findTitle().text()).toBe(title);
      expect(findDetail().text()).toContain(detail);
      expect(findTurnOnButton().exists()).toBe(false);
    });

    it('offers Contact sales in the rows, not in the header', () => {
      expect(findHeaderSales().exists()).toBe(false);
    });
  });

  describe('when one group can start a trial and another is not eligible', () => {
    beforeEach(() =>
      createComponent({
        groups: [
          buildGroup({ id: 1, name: 'acme' }),
          buildGroup({ id: 2, name: 'bank', groupAccess: ACCESS.notEligible }),
        ],
      }),
    );

    it('offers the trial and selects only the group that can turn on', () => {
      expect(findTitle().text()).toBe('Try GitLab Orbit');
      expect(findDetail().text()).toContain('each eligible group gets its own 100 credits');
      expect(findTable().props('selected')).toEqual(['acme']);
      expect(findTurnOnButton().props('disabled')).toBe(false);
    });
  });

  describe('when CustomersDot does not answer', () => {
    beforeEach(() =>
      createComponent({ groups: [buildGroup({ groupAccess: ACCESS.unavailable })] }),
    );

    it('shows the trial unavailable alert for the Off page and no Turn on Orbit button', () => {
      expect(findUnavailableAlert().props()).toMatchObject({
        glmContent: 'orbit-off-page',
        namespaceId: 1,
        reloading: false,
      });
      expect(findTitle().text()).toBe('GitLab Orbit is not turned on for your groups yet');
      expect(findTurnOnButton().exists()).toBe(false);
    });

    describe('and the Owner clicks Try again', () => {
      beforeEach(async () => {
        groupsHandler.mockReturnValue(new Promise(() => {}));
        findUnavailableAlert().vm.$emit('retry');
        await waitForPromises();
      });

      it('loads the groups again and shows that it is loading', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
        expect(findUnavailableAlert().props('reloading')).toBe(true);
      });
    });
  });

  describe('when every group turns on outside the trial flow', () => {
    beforeEach(() =>
      createComponent({
        groups: [buildGroup({ startOrbitTrial: false, groupAccess: ACCESS.beta })],
      }),
    );

    it('shows the Off title, no trial text, and Turn on Orbit', () => {
      expect(findTitle().text()).toBe('GitLab Orbit is not turned on for your groups yet');
      expect(findDetail().text()).not.toContain('trial');
      expect(findTurnOnButton().props('disabled')).toBe(false);
    });

    it('does not render a Beta badge', () => {
      expect(wrapper.findComponent(GlBadge).exists()).toBe(false);
    });
  });

  describe('when a trial is active and Orbit is off', () => {
    beforeEach(() => createComponent({ groups: [buildGroup({ groupAccess: ACCESS.active })] }));

    it('passes the active trial to the table', () => {
      expect(findTable().props('rows')).toEqual([
        {
          key: 'acme',
          namespaceId: 1,
          name: 'acme',
          avatarUrl: null,
          action: 'turn_on',
          offer: null,
          trialActive: true,
          trialEndsOn: '2026-11-13',
        },
      ]);
    });

    it('does not pass an instance trial to the confirm modal on GitLab.com', () => {
      expect(findModal().props('instanceTrialEndsOn')).toBeNull();
    });
  });

  describe('on GitLab Self-Managed', () => {
    describe('during the instance trial', () => {
      beforeEach(() =>
        createComponent({
          saas: false,
          groups: [buildGroup({ startOrbitTrial: false, groupAccess: ACCESS.active })],
        }),
      );

      it('says that the instance has a trial until the end date and shares its credits', () => {
        expect(findTitle().text()).toBe('Try GitLab Orbit');
        expect(findDetail().text()).toContain(
          'This instance has a GitLab Orbit trial until Nov 13, 2026. All groups on this instance share the trial credits.',
        );
      });

      it('passes the end of the instance trial to the confirm modal', () => {
        expect(findModal().props('instanceTrialEndsOn')).toBe('2026-11-13');
      });

      it('passes the groups to the table', () => {
        expect(findTable().props('rows')).toHaveLength(1);
      });
    });

    // A beta group does not join the instance trial, so its row turns on with no trial end.
    describe('when every owned group is beta during an active instance trial', () => {
      beforeEach(() =>
        createComponent({
          saas: false,
          groups: [buildGroup({ startOrbitTrial: false, groupAccess: ACCESS.beta })],
        }),
      );

      it('shows the Off header, not the instance trial', () => {
        expect(findTitle().text()).toBe('GitLab Orbit is not turned on for your groups yet');
        expect(findTurnOnButton().props('disabled')).toBe(false);
      });

      it('passes no instance trial end to the confirm modal', () => {
        expect(findModal().props('instanceTrialEndsOn')).toBeNull();
      });
    });

    describe.each`
      description                                | groupAccess         | startOrbitTrial | title                                     | detail
      ${'the instance has no license for Orbit'} | ${ACCESS.noLicense} | ${true}         | ${'Get GitLab Orbit for this instance'}   | ${'Ask your administrator, or contact sales.'}
      ${'the instance trial has ended'}          | ${ACCESS.expired}   | ${true}         | ${'The trial of this instance has ended'} | ${'GitLab Orbit is off for your groups. Ask your administrator, or contact sales.'}
    `('when $description', ({ groupAccess, startOrbitTrial, title, detail }) => {
      beforeEach(() =>
        createComponent({ saas: false, groups: [buildGroup({ startOrbitTrial, groupAccess })] }),
      );

      it('shows the instance copy and Contact sales in the header', () => {
        expect(findTitle().text()).toBe(title);
        expect(findDetail().text()).toContain(detail);
        expect(findHeaderSales().props()).toMatchObject({
          glmContent: 'orbit-off-page',
        });
        expect(findTurnOnButton().exists()).toBe(false);
      });

      it('shows no GitLab.com plan copy', () => {
        expect(wrapper.text()).not.toContain('Premium and Ultimate');
      });
    });

    describe.each`
      description                                    | groupAccess
      ${'only an administrator starts the trial'}    | ${access({ turnOnDenialReason: null })}
      ${'the instance is not eligible for a trial'}  | ${{ ...ACCESS.notEligible, turnOnDenialReason: null }}
      ${'the instance has no trial and no purchase'} | ${{ ...ACCESS.purchaseRequired, turnOnDenialReason: null }}
    `('when $description', ({ groupAccess }) => {
      beforeEach(() =>
        createComponent({
          saas: false,
          groups: [buildGroup({ startOrbitTrial: false, groupAccess })],
        }),
      );

      it('offers Turn on Orbit and no Contact sales', () => {
        expect(findTitle().text()).toBe('GitLab Orbit is not turned on for your groups yet');
        expect(findTurnOnButton().props('disabled')).toBe(false);
        expect(findHeaderSales().exists()).toBe(false);
        expect(findTable().props('rows')[0].action).toBe('turn_on');
      });
    });

    describe.each(['PLAN', 'BETA', 'PROMO_ADD_ON'])('when the access comes from %s', (reason) => {
      beforeEach(() =>
        createComponent({
          saas: false,
          groups: [
            buildGroup({
              startOrbitTrial: false,
              groupAccess: access({
                state: 'LICENSED',
                reason,
                turnOnDenialReason: null,
                trial: null,
              }),
            }),
          ],
        }),
      );

      it('offers Turn on Orbit', () => {
        expect(findTurnOnButton().props('disabled')).toBe(false);
      });
    });

    describe('when the user owns no top-level group', () => {
      beforeEach(() => createComponent({ saas: false, groups: [] }));

      it('shows no Contact sales', () => {
        expect(findHeaderSales().exists()).toBe(false);
      });
    });
  });

  describe('when the Owner owns more top-level groups than the page loads', () => {
    beforeEach(() =>
      createComponent({
        groupsHandlerFn: jest.fn().mockResolvedValue(groupsResponse([buildGroup()], true)),
      }),
    );

    it('loads at most 10 groups', () => {
      expect(groupsHandler).toHaveBeenCalledWith({ first: 10 });
    });

    it('says where to turn on Orbit for the other groups', () => {
      expect(wrapper.findByTestId('orbit-off-more-groups').text()).toBe(
        'This list shows your first 10 top-level groups. To turn on GitLab Orbit for another group you own, go to the GitLab Orbit settings of that group.',
      );
    });
  });

  describe('when the user owns no top-level group', () => {
    beforeEach(() => createComponent({ groups: [] }));

    it('asks them to contact an Owner and shows no table', () => {
      expect(findTitle().text()).toBe('GitLab Orbit is not turned on for your groups yet');
      expect(findAskOwner().exists()).toBe(true);
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when the groups field is null', () => {
    beforeEach(() =>
      createComponent({
        groupsHandlerFn: jest
          .fn()
          .mockResolvedValue({ data: { orbit: { __typename: 'Orbit', groups: null } } }),
      }),
    );

    it('shows the view for a user who owns no group', () => {
      expect(findAskOwner().exists()).toBe(true);
      expect(findLoadError().exists()).toBe(false);
    });
  });

  describe('when the groups fail to load', () => {
    beforeEach(() =>
      createComponent({
        groupsHandlerFn: jest
          .fn()
          .mockRejectedValueOnce(new Error('500'))
          .mockResolvedValue(groupsResponse([buildGroup()])),
      }),
    );

    it('shows the error', () => {
      expect(findLoadError().text()).toBe('Could not load groups.');
    });

    it('reports the error to Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalled();
    });

    it('shows no groups and no Ask an Owner message', () => {
      expect(findAskOwner().exists()).toBe(false);
      expect(findTable().exists()).toBe(false);
    });

    describe('and the user clicks Try again', () => {
      beforeEach(async () => {
        findLoadError().vm.$emit('primary-action');
        await waitForPromises();
      });

      it('loads the groups and shows them', () => {
        expect(groupsHandler).toHaveBeenCalledTimes(2);
        expect(findLoadError().exists()).toBe(false);
        expect(findTable().exists()).toBe(true);
      });
    });
  });

  describe('when the groups query returns a GraphQL error', () => {
    beforeEach(() =>
      createComponent({
        groupsHandlerFn: jest
          .fn()
          .mockResolvedValue({ errors: [{ message: 'Complexity too high' }] }),
      }),
    );

    it('shows the error and does not report to Sentry', () => {
      expect(findLoadError().exists()).toBe(true);
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });
  });
});
