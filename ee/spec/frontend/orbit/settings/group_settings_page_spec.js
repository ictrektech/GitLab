import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlSkeletonLoader, GlToggle } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { createAlert } from '~/alert';
import groupSettingsQuery from 'ee/orbit/graphql/queries/group_settings.query.graphql';
import orbitStartTrialMutation from 'ee/orbit/graphql/mutations/orbit_start_trial.mutation.graphql';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import GroupSettingsPage from 'ee/orbit/settings/group_settings_page.vue';
import { GROUP_SETTINGS_CACHE_CONFIG } from 'ee/orbit/settings/graphql/cache_config';
import GroupSettingsAlert from 'ee/orbit/settings/group_settings_alert.vue';
import GroupsConfirmModal from 'ee/orbit/shared/groups/groups_confirm_modal.vue';
import TurnOnConfirmModal from 'ee/orbit/shared/groups/turn_on_confirm_modal.vue';
import { orbitPlatform } from '../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('OrbitGroupSettingsPage', () => {
  let wrapper;
  let queryHandler;
  let startTrialHandler;
  let updateHandler;

  const offer = { __typename: 'OrbitTrialOffer', durationDays: 30, initialCredits: 100 };
  const DENIALS = {
    UNLICENSED: 'FORBIDDEN',
    TRIAL_ELIGIBLE: 'TRIAL_REQUIRED',
    TRIAL_NOT_ELIGIBLE: 'TRIAL_REQUIRED',
    TRIAL_STATUS_UNAVAILABLE: 'UNAVAILABLE',
    TRIAL_ENDED: 'TRIAL_ENDED',
  };
  const access = (state, reason = null, trial = {}) => ({
    __typename: 'OrbitAccess',
    state,
    reason,
    turnOnDenialReason: DENIALS[state] ?? null,
    trial: { __typename: 'OrbitTrial', expiresOn: null, credits: null, offer, ...trial },
  });

  const buildGroup = ({
    enabled = false,
    startOrbitTrial = true,
    access: orbitAccess = access('TRIAL_ELIGIBLE'),
    orbit = {},
  } = {}) => ({
    id: 'gid://gitlab/Group/1',
    name: 'Acme',
    fullPath: 'acme',
    userPermissions: { __typename: 'GroupPermissions', startOrbitTrial },
    orbit: {
      __typename: 'OrbitNamespace',
      enabled,
      enabledAt: null,
      access: orbitAccess,
      indexing: null,
      ...orbit,
    },
    __typename: 'Group',
  });

  const createComponent = ({ group = {}, props = {}, saas = true, queryResponse } = {}) => {
    queryHandler = jest
      .fn()
      .mockResolvedValue(queryResponse ?? { data: { group: buildGroup(group) } });
    startTrialHandler = jest.fn().mockResolvedValue({
      data: { orbitStartTrial: { __typename: 'OrbitStartTrialPayload', errors: [] } },
    });
    updateHandler = jest.fn().mockResolvedValue({
      data: {
        orbitUpdate: {
          __typename: 'OrbitUpdatePayload',
          group: {
            __typename: 'Group',
            id: 'gid://gitlab/Group/1',
            name: 'Acme',
            fullPath: 'acme',
            orbit: { __typename: 'OrbitNamespace', enabled: !group.enabled },
          },
          errors: [],
        },
      },
    });

    wrapper = shallowMountExtended(GroupSettingsPage, {
      apolloProvider: createMockApollo(
        [
          [groupSettingsQuery, queryHandler],
          [orbitStartTrialMutation, startTrialHandler],
          [orbitUpdateMutation, updateHandler],
        ],
        {},
        GROUP_SETTINGS_CACHE_CONFIG,
      ),
      propsData: {
        groupFullPath: 'acme',
        duoAvailable: true,
        orbitPath: '/-/dashboard/orbit',
        usageQuotasPath: '/acme/-/usage_quotas',
        duoSettingsPath: '/acme/-/settings/gitlab_duo',
        ...props,
      },
      provide: { orbitPlatform: orbitPlatform({ saas }) },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findToggle = () => wrapper.findComponent(GlToggle);
  const findTrialBanner = () => wrapper.findByTestId('orbit-trial-banner');
  const findGroupAlert = () => wrapper.findComponent(GroupSettingsAlert);
  const findTurnOnConfirmModal = () => wrapper.findComponent(TurnOnConfirmModal);
  const findTurnOffConfirmModal = () => wrapper.findComponent(GroupsConfirmModal);
  const findActionError = () => wrapper.findByTestId('orbit-action-error');
  const findStatusAlert = () => wrapper.findComponentByTestId('orbit-status-alert');
  const findDuoAlert = () => wrapper.findByTestId('orbit-duo-alert');

  const turnOnAndConfirm = async () => {
    findToggle().vm.$emit('change', true);
    await nextTick();
    findTurnOnConfirmModal().vm.$emit('confirm');
    await waitForPromises();
  };
  const turnOffAndConfirm = async () => {
    findToggle().vm.$emit('change', false);
    await nextTick();
    findTurnOffConfirmModal().vm.$emit('confirm', 'turnOff');
    await waitForPromises();
  };

  describe('while loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows a skeleton and no content', () => {
      expect(findSkeleton().exists()).toBe(true);
      expect(findToggle().exists()).toBe(false);
    });
  });

  describe('when the group cannot load', () => {
    beforeEach(async () => {
      createComponent({
        queryResponse: { data: { group: null }, errors: [{ message: 'Internal server error' }] },
      });
      await waitForPromises();
    });

    it('shows the load error and keeps the skeleton', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Could not load the group. Try again.' }),
      );
      expect(findSkeleton().exists()).toBe(true);
    });
  });

  describe('when only the Orbit status cannot load', () => {
    beforeEach(async () => {
      createComponent({
        queryResponse: {
          data: {
            group: buildGroup({
              enabled: true,
              access: access('LICENSED'),
              orbit: {
                __typename: 'OrbitNamespace',
                enabledAt: '2026-10-15T11:59:00Z',
                indexing: null,
              },
            }),
          },
          errors: [
            {
              message: 'Knowledge graph request failed',
              path: ['group', 'orbit', 'indexing'],
            },
          ],
        },
      });
      await waitForPromises();
    });

    it('shows the toggle and no load error', () => {
      expect(createAlert).not.toHaveBeenCalled();
      expect(findToggle().props('value')).toBe(true);
    });

    it('says the status is not available', () => {
      expect(findStatusAlert().props('title')).toBe('GitLab Orbit status is not available');
    });
  });

  describe('when an older backend does not return the Orbit state', () => {
    const findUnknownAlert = () => wrapper.findByTestId('orbit-state-unknown-alert');

    it.each`
      scenario                  | orbit
      ${'no orbit object'}      | ${null}
      ${'no enabled or access'} | ${{ __typename: 'OrbitNamespace', enabled: null, enabledAt: null, access: null, indexing: null }}
    `('hides the toggle and says Orbit is not available with $scenario', async ({ orbit }) => {
      createComponent({ queryResponse: { data: { group: { ...buildGroup(), orbit } } } });
      await waitForPromises();

      expect(findToggle().exists()).toBe(false);
      expect(findUnknownAlert().text()).toBe(
        'GitLab Orbit is not available right now. Try again later.',
      );
      expect(findStatusAlert().exists()).toBe(false);
      expect(findGroupAlert().exists()).toBe(false);
      expect(createAlert).not.toHaveBeenCalled();
      expect(updateHandler).not.toHaveBeenCalled();
    });
  });

  describe('when the trial flow is off', () => {
    describe('and the group is licensed', () => {
      beforeEach(async () => {
        createComponent({
          group: {
            access: access('LICENSED'),
          },
        });
        await waitForPromises();
      });

      it('shows the toggle and no trial UI', () => {
        expect(findToggle().exists()).toBe(true);
        expect(findGroupAlert().exists()).toBe(false);
        expect(findTrialBanner().exists()).toBe(false);
      });
    });
  });

  describe.each`
    scenario                         | accessState         | reason          | alert
    ${'the group is on Free'}        | ${'UNLICENSED'}     | ${'FREE_PLAN'}  | ${'free_plan'}
    ${'the instance has no license'} | ${'UNLICENSED'}     | ${'NO_LICENSE'} | ${'unlicensed'}
    ${'the group lost access'}       | ${'UNLICENSED'}     | ${'NO_ACCESS'}  | ${'unlicensed'}
    ${'Orbit is not set up'}         | ${'NOT_CONFIGURED'} | ${null}         | ${'unlicensed'}
  `('when $scenario', ({ accessState, reason, alert }) => {
    beforeEach(async () => {
      createComponent({ group: { access: access(accessState, reason) } });
      await waitForPromises();
    });

    it(`shows the ${alert} alert and no toggle`, () => {
      expect(findGroupAlert().props('state')).toBe(alert);
      expect(findToggle().exists()).toBe(false);
    });
  });

  describe('when the trial flow is on', () => {
    describe.each`
      scenario                          | accessState                   | reason                 | state
      ${'CustomersDot does not answer'} | ${'TRIAL_STATUS_UNAVAILABLE'} | ${null}                | ${'cdot_unavailable'}
      ${'the group is not eligible'}    | ${'TRIAL_NOT_ELIGIBLE'}       | ${null}                | ${'not_eligible'}
      ${'the trial ran out of time'}    | ${'TRIAL_ENDED'}              | ${'TRIAL_EXPIRED'}     | ${'trial_ended'}
      ${'the trial ran out of credits'} | ${'TRIAL_ENDED'}              | ${'CREDITS_EXHAUSTED'} | ${'credits_used_up'}
    `('when $scenario', ({ accessState, reason, state }) => {
      beforeEach(async () => {
        createComponent({ group: { access: access(accessState, reason) } });
        await waitForPromises();
      });

      it(`shows the ${state} alert`, () => {
        expect(findGroupAlert().props('state')).toBe(state);
      });
    });

    describe('when the group is eligible to start a trial', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('shows the trial banner with the offer from CustomersDot and the toggle turned off', () => {
        expect(findTrialBanner().text()).toContain(
          'Turn on GitLab Orbit to start a trial for Acme with 100 credits, valid for 30 days.',
        );
        expect(findToggle().props('value')).toBe(false);
      });
    });

    describe('when CustomersDot sends no offer', () => {
      beforeEach(async () => {
        createComponent({
          group: { access: access('TRIAL_ELIGIBLE', null, { offer: null }) },
        });
        await waitForPromises();
      });

      it('shows the trial banner with no offer numbers', () => {
        expect(findTrialBanner().text()).toContain(
          'Turn on GitLab Orbit to start a trial for Acme.',
        );
      });
    });

    describe('when a trial is active', () => {
      const createActiveTrial = (credits) =>
        createComponent({
          group: {
            enabled: true,
            access: access('TRIAL_ACTIVE', null, { offer: null, credits }),
            orbit: {
              __typename: 'OrbitNamespace',
              enabledAt: null,
              indexing: { __typename: 'OrbitIndexing', state: 'READY' },
            },
          },
        });

      describe('with the credits of the trial', () => {
        beforeEach(async () => {
          createActiveTrial({ __typename: 'OrbitTrialCredits', total: 500 });
          await waitForPromises();
        });

        it('shows the credits of the trial and the toggle turned on', () => {
          expect(findTrialBanner().text()).toContain(
            'Acme has a GitLab Orbit trial with 500 credits.',
          );
          expect(findToggle().props('value')).toBe(true);
        });
      });

      describe('with no credits from CustomersDot', () => {
        beforeEach(async () => {
          createActiveTrial(null);
          await waitForPromises();
        });

        it('shows the trial banner with no credit numbers', () => {
          expect(findTrialBanner().text()).toContain('Acme has a GitLab Orbit trial.');
        });
      });
    });
  });

  describe('when the server sends no turn-on denial for an eligible group that is on', () => {
    beforeEach(async () => {
      createComponent({
        group: {
          enabled: true,
          access: { ...access('TRIAL_ELIGIBLE'), turnOnDenialReason: null },
        },
      });
      await waitForPromises();
    });

    it('shows no alert and keeps the toggle on', () => {
      expect(findGroupAlert().exists()).toBe(false);
      expect(findToggle().props('value')).toBe(true);
    });
  });

  describe('when the group is eligible and Orbit is already on', () => {
    beforeEach(async () => {
      createComponent({ group: { enabled: true } });
      await waitForPromises();
    });

    it('shows no trial banner', () => {
      expect(findTrialBanner().exists()).toBe(false);
      expect(findToggle().props('value')).toBe(true);
    });

    describe('and the Owner turns it off', () => {
      beforeEach(async () => {
        findToggle().vm.$emit('change', false);
        await nextTick();
      });

      it('asks to confirm the turn off, not a trial, and does not update Orbit', () => {
        expect(findTurnOffConfirmModal().props('kind')).toBe('turnOff');
        expect(findTurnOffConfirmModal().props('groups')).toMatchObject([
          { fullPath: 'acme', name: 'Acme' },
        ]);
        expect(findTurnOnConfirmModal().props('visible')).toBe(false);
        expect(updateHandler).not.toHaveBeenCalled();
      });

      describe('and confirms', () => {
        beforeEach(async () => {
          findTurnOffConfirmModal().vm.$emit('confirm', 'turnOff');
          await waitForPromises();
        });

        it('turns Orbit off and closes the confirm', () => {
          expect(updateHandler).toHaveBeenCalledWith({
            input: { groupPath: 'acme', enabled: false },
          });
          expect(findTurnOffConfirmModal().props('kind')).toBe(null);
        });
      });

      describe('and cancels', () => {
        beforeEach(async () => {
          findTurnOffConfirmModal().vm.$emit('cancel');
          await waitForPromises();
        });

        it('closes the confirm and keeps Orbit on', () => {
          expect(findTurnOffConfirmModal().props('kind')).toBe(null);
          expect(updateHandler).not.toHaveBeenCalled();
          expect(findToggle().props('value')).toBe(true);
        });
      });
    });

    describe('and the Owner turns it off while the group reloads', () => {
      beforeEach(async () => {
        queryHandler.mockReturnValue(new Promise(() => {}));
        await turnOffAndConfirm();
      });

      it('shows Orbit as off from the mutation result', () => {
        expect(findToggle().props('value')).toBe(false);
      });
    });
  });

  describe('starting a trial', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('shows no error and no confirm modal before the user acts', () => {
      expect(findActionError().exists()).toBe(false);
      expect(findTurnOnConfirmModal().props('visible')).toBe(false);
    });

    describe('when the Owner turns on Orbit', () => {
      beforeEach(async () => {
        findToggle().vm.$emit('change', true);
        await nextTick();
      });

      it('asks to confirm the trial and does not update Orbit', () => {
        expect(findTurnOnConfirmModal().props('visible')).toBe(true);
        expect(updateHandler).not.toHaveBeenCalled();
      });

      it('asks to confirm with the shared turn-on confirm and the CustomersDot offer', () => {
        expect(findTurnOnConfirmModal().props('groups')).toEqual([
          { fullPath: 'acme', name: 'Acme', startsTrial: true, offer },
        ]);
      });

      describe('and confirms', () => {
        beforeEach(async () => {
          findTurnOnConfirmModal().vm.$emit('confirm');
          await waitForPromises();
        });

        it('runs the mutation for the group and refetches', () => {
          expect(startTrialHandler).toHaveBeenCalledWith({ groupPath: 'acme' });
          expect(queryHandler).toHaveBeenCalledTimes(2);
        });
      });
    });

    describe('when the trial cannot start', () => {
      beforeEach(async () => {
        startTrialHandler.mockResolvedValue({
          data: {
            orbitStartTrial: { __typename: 'OrbitStartTrialPayload', errors: ['No seats left'] },
          },
        });
        findTurnOnConfirmModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('shows the server message in an error alert', () => {
        expect(findActionError().text()).toContain('No seats left');
      });
    });

    describe('when the trial cannot start because CustomersDot stops answering', () => {
      beforeEach(async () => {
        startTrialHandler.mockResolvedValue({
          data: {
            orbitStartTrial: {
              __typename: 'OrbitStartTrialPayload',
              errors: ['GitLab Orbit is not available right now. Try again later.'],
            },
          },
        });
        queryHandler.mockResolvedValue({
          data: { group: buildGroup({ access: access('TRIAL_STATUS_UNAVAILABLE') }) },
        });
        findTurnOnConfirmModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('shows only the CustomersDot alert', () => {
        expect(findGroupAlert().props('state')).toBe('cdot_unavailable');
        expect(findActionError().exists()).toBe(false);
      });
    });
  });

  describe('toggling Orbit', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    describe('when Orbit is off', () => {
      beforeEach(async () => {
        createComponent({ group: { access: access('LICENSED') } });
        await waitForPromises();
      });

      it('does not update Orbit before the toggle changes', () => {
        expect(updateHandler).not.toHaveBeenCalled();
      });

      describe('and the Owner turns it on', () => {
        beforeEach(async () => {
          findToggle().vm.$emit('change', true);
          await nextTick();
        });

        it('asks to confirm with no trial and does not update Orbit', () => {
          expect(findTurnOnConfirmModal().props()).toMatchObject({
            visible: true,
            groups: [{ fullPath: 'acme', name: 'Acme', startsTrial: false, offer }],
            instanceTrialEndsOn: null,
          });
          expect(updateHandler).not.toHaveBeenCalled();
        });

        describe('and confirms', () => {
          beforeEach(async () => {
            findTurnOnConfirmModal().vm.$emit('confirm');
            await waitForPromises();
          });

          it('runs the update mutation, closes the confirm, and refetches', () => {
            expect(updateHandler).toHaveBeenCalledWith({
              input: { groupPath: 'acme', enabled: true },
            });
            expect(findTurnOnConfirmModal().props('visible')).toBe(false);
            expect(queryHandler).toHaveBeenCalledTimes(2);
          });
        });
      });

      describe('and the update fails', () => {
        beforeEach(async () => {
          updateHandler.mockResolvedValue({
            data: {
              orbitUpdate: { __typename: 'OrbitUpdatePayload', group: null, errors: ['Blocked'] },
            },
          });
          await turnOnAndConfirm();
        });

        it('shows the server message in an error alert', () => {
          expect(findActionError().text()).toContain('Blocked');
        });
      });
    });

    describe('when Orbit is on', () => {
      let trackEventSpy;

      beforeEach(async () => {
        createComponent({
          group: {
            enabled: true,
            access: access('LICENSED'),
          },
        });
        await waitForPromises();
        ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
      });

      it('does not track a turn off before the toggle changes', () => {
        expect(trackEventSpy).not.toHaveBeenCalled();
      });

      describe('and the Owner turns it off and confirms', () => {
        beforeEach(async () => {
          await turnOffAndConfirm();
        });

        it('runs the update mutation and tracks the event', () => {
          expect(updateHandler).toHaveBeenCalledWith({
            input: { groupPath: 'acme', enabled: false },
          });
          expect(trackEventSpy).toHaveBeenCalledWith(
            'click_orbit_turn_off_indexing',
            {},
            undefined,
          );
        });
      });
    });
  });

  describe('when Orbit is on', () => {
    describe('and still indexing', () => {
      beforeEach(async () => {
        createComponent({
          group: {
            enabled: true,
            access: access('LICENSED'),
            orbit: {
              __typename: 'OrbitNamespace',
              enabledAt: '2026-10-15T11:59:00Z',
              indexing: { __typename: 'OrbitIndexing', state: 'INDEXING' },
            },
          },
        });
        await waitForPromises();
      });

      it('shows an info status alert', () => {
        expect(findStatusAlert().props('variant')).toBe('info');
      });
    });

    describe('and ready', () => {
      beforeEach(async () => {
        createComponent({
          group: {
            enabled: true,
            access: access('LICENSED'),
            orbit: {
              __typename: 'OrbitNamespace',
              enabledAt: null,
              indexing: { __typename: 'OrbitIndexing', state: 'READY' },
            },
          },
        });
        await waitForPromises();
      });

      it('shows a success status alert with a link to Orbit', () => {
        expect(findStatusAlert().props('variant')).toBe('success');
        expect(findStatusAlert().props('primaryButtonLink')).toBe('/-/dashboard/orbit');
      });
    });

    describe('and GitLab Duo is not available', () => {
      beforeEach(async () => {
        createComponent({
          props: { duoAvailable: false },
          group: {
            enabled: true,
            access: access('LICENSED'),
            orbit: {
              __typename: 'OrbitNamespace',
              enabledAt: null,
              indexing: { __typename: 'OrbitIndexing', state: 'READY' },
            },
          },
        });
        await waitForPromises();
      });

      it('shows the Duo alert', () => {
        expect(findDuoAlert().exists()).toBe(true);
      });
    });
  });

  describe('polling', () => {
    useFakeDate(2026, 9, 15, 12, 0, 0);

    const POLL_INTERVAL = 15000;
    const QUEUED_POLL_INTERVAL = 60000;

    const createEnabledGroup = (orbit) =>
      createComponent({
        group: {
          enabled: true,
          access: access('LICENSED'),
          orbit: { __typename: 'OrbitNamespace', ...orbit },
        },
      });

    const waitOnePollInterval = async () => {
      jest.advanceTimersByTime(POLL_INTERVAL);
      await waitForPromises();
    };

    describe('while indexing', () => {
      beforeEach(async () => {
        createEnabledGroup({
          enabledAt: '2026-10-15T11:59:00Z',
          indexing: { __typename: 'OrbitIndexing', state: 'INDEXING' },
        });
        await waitForPromises();
      });

      it('has fetched the group one time', () => {
        expect(queryHandler).toHaveBeenCalledTimes(1);
      });

      describe('and one poll interval passes', () => {
        beforeEach(async () => {
          await waitOnePollInterval();
        });

        it('fetches the group again', () => {
          expect(queryHandler).toHaveBeenCalledTimes(2);
        });
      });
    });

    describe('when ready', () => {
      beforeEach(async () => {
        createEnabledGroup({
          enabledAt: null,
          indexing: { __typename: 'OrbitIndexing', state: 'READY' },
        });
        await waitForPromises();
      });

      describe('and one poll interval passes', () => {
        beforeEach(async () => {
          await waitOnePollInterval();
        });

        it('does not fetch the group again', () => {
          expect(queryHandler).toHaveBeenCalledTimes(1);
        });
      });
    });

    describe('when enabled long ago with no status (queued)', () => {
      beforeEach(async () => {
        createEnabledGroup({ enabledAt: '2026-10-15T10:00:00Z', indexing: null });
        await waitForPromises();
      });

      describe('and one poll interval passes', () => {
        beforeEach(async () => {
          await waitOnePollInterval();
        });

        it('does not fetch the group again', () => {
          expect(queryHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('and one queued poll interval passes', () => {
        beforeEach(async () => {
          jest.advanceTimersByTime(QUEUED_POLL_INTERVAL);
          await waitForPromises();
        });

        it('fetches the group again', () => {
          expect(queryHandler).toHaveBeenCalledTimes(2);
        });
      });
    });
  });

  describe('on GitLab Self-Managed', () => {
    const INSTANCE_DENIALS = { NO_LICENSE: 'FORBIDDEN', TRIAL_EXPIRED: 'TRIAL_ENDED' };
    const instanceAccess = (state, reason = null, trial = {}) => ({
      ...access(state, reason, trial),
      turnOnDenialReason: INSTANCE_DENIALS[reason] ?? null,
    });
    const createInstanceComponent = (group) =>
      createComponent({ group: { startOrbitTrial: false, ...group }, saas: false });

    describe.each`
      scenario                         | accessState      | reason             | alert
      ${'the instance has no license'} | ${'UNLICENSED'}  | ${'NO_LICENSE'}    | ${'instance_not_available'}
      ${'the instance trial ended'}    | ${'TRIAL_ENDED'} | ${'TRIAL_EXPIRED'} | ${'instance_trial_ended'}
    `('when $scenario', ({ accessState, reason, alert }) => {
      beforeEach(async () => {
        createInstanceComponent({ access: instanceAccess(accessState, reason) });
        await waitForPromises();
      });

      it(`shows the ${alert} alert and no toggle`, () => {
        expect(findGroupAlert().props('state')).toBe(alert);
        expect(findToggle().exists()).toBe(false);
      });
    });

    describe.each`
      scenario                                       | accessState             | reason
      ${'an administrator did not start the trial'}  | ${'TRIAL_ELIGIBLE'}     | ${null}
      ${'the instance is not eligible for a trial'}  | ${'TRIAL_NOT_ELIGIBLE'} | ${null}
      ${'the instance has no trial and no purchase'} | ${'UNLICENSED'}         | ${'NO_ACCESS'}
    `('when $scenario', ({ accessState, reason }) => {
      beforeEach(async () => {
        createInstanceComponent({ access: instanceAccess(accessState, reason) });
        await waitForPromises();
        findToggle().vm.$emit('change', true);
        await nextTick();
      });

      it('shows no alert and asks to confirm with no trial', () => {
        expect(findGroupAlert().exists()).toBe(false);
        expect(findTrialBanner().exists()).toBe(false);
        expect(findTurnOnConfirmModal().props('groups')).toMatchObject([{ startsTrial: false }]);
        expect(findTurnOnConfirmModal().props('instanceTrialEndsOn')).toBe(null);
      });

      describe('and the Owner confirms', () => {
        beforeEach(async () => {
          findTurnOnConfirmModal().vm.$emit('confirm');
          await waitForPromises();
        });

        it('turns Orbit on with no trial', () => {
          expect(startTrialHandler).not.toHaveBeenCalled();
          expect(updateHandler).toHaveBeenCalledWith({
            input: { groupPath: 'acme', enabled: true },
          });
        });
      });
    });

    describe('when Orbit is on and the instance is not eligible for a trial', () => {
      beforeEach(async () => {
        createInstanceComponent({ enabled: true, access: instanceAccess('TRIAL_NOT_ELIGIBLE') });
        await waitForPromises();
      });

      it('shows the Orbit status and no blocking alert', () => {
        expect(findGroupAlert().exists()).toBe(false);
        expect(findStatusAlert().exists()).toBe(true);
        expect(findToggle().props('value')).toBe(true);
      });
    });

    describe('when the instance trial is active and the server sends no trial', () => {
      beforeEach(async () => {
        createInstanceComponent({ access: { ...instanceAccess('TRIAL_ACTIVE'), trial: null } });
        await waitForPromises();
      });

      it('says that the instance has a trial, with no end date', () => {
        expect(findTrialBanner().text()).toContain(
          'This instance has a GitLab Orbit trial. All groups on this instance share the trial credits.',
        );
      });
    });

    describe('when the instance trial is active', () => {
      beforeEach(async () => {
        createInstanceComponent({
          access: instanceAccess('TRIAL_ACTIVE', null, { offer: null, expiresOn: '2026-11-13' }),
        });
        await waitForPromises();
      });

      it('says that the instance has a trial until its end date', () => {
        expect(findTrialBanner().text()).toContain(
          'This instance has a GitLab Orbit trial until Nov 13, 2026. All groups on this instance share the trial credits.',
        );
      });

      describe('and the Owner turns on Orbit', () => {
        beforeEach(async () => {
          findToggle().vm.$emit('change', true);
          await nextTick();
        });

        it('asks to confirm with the end date of the instance trial', () => {
          expect(findTurnOnConfirmModal().props('instanceTrialEndsOn')).toBe('2026-11-13');
          expect(findTurnOnConfirmModal().props('groups')).toMatchObject([{ startsTrial: false }]);
        });

        describe('and confirms', () => {
          beforeEach(async () => {
            findTurnOnConfirmModal().vm.$emit('confirm');
            await waitForPromises();
          });

          it('turns Orbit on with no new trial', () => {
            expect(startTrialHandler).not.toHaveBeenCalled();
            expect(updateHandler).toHaveBeenCalledWith({
              input: { groupPath: 'acme', enabled: true },
            });
          });
        });
      });
    });
  });

  describe('when the group needs a trial that the Owner cannot start', () => {
    beforeEach(async () => {
      createComponent({ group: { startOrbitTrial: false, access: access('TRIAL_ELIGIBLE') } });
      await waitForPromises();
    });

    it('shows the unlicensed alert, no trial banner, and no toggle', () => {
      expect(findGroupAlert().props('state')).toBe('unlicensed');
      expect(findTrialBanner().exists()).toBe(false);
      expect(findToggle().exists()).toBe(false);
    });
  });

  describe('a blocked state while Orbit is still on', () => {
    describe('when Orbit is on', () => {
      beforeEach(async () => {
        createComponent({
          group: {
            enabled: true,
            access: access('TRIAL_ENDED', 'TRIAL_EXPIRED'),
          },
        });
        await waitForPromises();
      });

      it('shows the alert and keeps the toggle so the Owner can turn Orbit off', () => {
        expect(findGroupAlert().props('state')).toBe('trial_ended');
        expect(findToggle().exists()).toBe(true);
      });
    });

    describe('when Orbit is off', () => {
      beforeEach(async () => {
        createComponent({
          group: {
            enabled: false,
            access: access('TRIAL_ENDED', 'TRIAL_EXPIRED'),
          },
        });
        await waitForPromises();
      });

      it('shows the alert and no toggle', () => {
        expect(findGroupAlert().props('state')).toBe('trial_ended');
        expect(findToggle().exists()).toBe(false);
      });
    });
  });
});
