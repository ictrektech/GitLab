import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import adminInstanceAccessQuery from 'ee/orbit/settings/admin/graphql/admin_instance_access.query.graphql';
import orbitInstanceStartTrialMutation from 'ee/orbit/graphql/mutations/orbit_instance_start_trial.mutation.graphql';
import { ADMIN_CACHE_CONFIG } from 'ee/orbit/settings/admin/graphql/cache_config';
import AdminInstanceAccess from 'ee/orbit/settings/admin/admin_instance_access.vue';
import AdminInstanceAccessCard from 'ee/orbit/settings/admin/admin_instance_access_card.vue';
import { instanceAccess, instanceAccessResponse, instanceStartTrialResponse } from './mock_data';

Vue.use(VueApollo);

describe('AdminInstanceAccess', () => {
  let wrapper;
  let instanceAccessHandler;
  let startTrialHandler;

  const createComponent = async ({ access = instanceAccess('LICENSED', 'PLAN'), handler } = {}) => {
    instanceAccessHandler = handler ?? jest.fn().mockResolvedValue(instanceAccessResponse(access));
    startTrialHandler = jest.fn().mockResolvedValue(instanceStartTrialResponse());

    wrapper = shallowMountExtended(AdminInstanceAccess, {
      apolloProvider: createMockApollo(
        [
          [adminInstanceAccessQuery, instanceAccessHandler],
          [orbitInstanceStartTrialMutation, startTrialHandler],
        ],
        {},
        ADMIN_CACHE_CONFIG,
      ),
    });
    await waitForPromises();
  };

  const findAccessCard = () => wrapper.findComponent(AdminInstanceAccessCard);
  const findTrialError = () => wrapper.findComponentByTestId('orbit-instance-trial-error');

  describe.each`
    state                         | reason             | card
    ${'LICENSED'}                 | ${'PLAN'}          | ${true}
    ${'LICENSED'}                 | ${'PROMO_ADD_ON'}  | ${true}
    ${'TRIAL_ELIGIBLE'}           | ${null}            | ${true}
    ${'TRIAL_ACTIVE'}             | ${null}            | ${true}
    ${'TRIAL_ENDED'}              | ${'TRIAL_EXPIRED'} | ${true}
    ${'UNLICENSED'}               | ${'NO_LICENSE'}    | ${true}
    ${'NOT_CONFIGURED'}           | ${null}            | ${false}
    ${'TRIAL_STATUS_UNAVAILABLE'} | ${null}            | ${false}
  `('when the instance access is $state $reason', ({ state, reason, card }) => {
    beforeEach(() => createComponent({ access: instanceAccess(state, reason) }));

    it(`${card ? 'shows' : 'hides'} the access card`, () => {
      expect(findAccessCard().exists()).toBe(card);
    });
  });

  describe('when the instance access cannot load', () => {
    beforeEach(() =>
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('Network error')) }),
    );

    it('hides the card', () => {
      expect(findAccessCard().exists()).toBe(false);
    });
  });

  describe('starting the instance trial', () => {
    beforeEach(() => createComponent({ access: instanceAccess('TRIAL_ELIGIBLE') }));

    it('does not start a trial before the administrator confirms', () => {
      expect(startTrialHandler).not.toHaveBeenCalled();
      expect(findAccessCard().props()).toMatchObject({ starting: false, confirmVisible: false });
    });

    it('opens the confirm on show-confirm', async () => {
      findAccessCard().vm.$emit('show-confirm');
      await nextTick();

      expect(findAccessCard().props('confirmVisible')).toBe(true);
    });

    it('closes the confirm on hide-confirm', async () => {
      findAccessCard().vm.$emit('show-confirm');
      await nextTick();
      findAccessCard().vm.$emit('hide-confirm');
      await nextTick();

      expect(findAccessCard().props('confirmVisible')).toBe(false);
    });

    describe('when the trial starts', () => {
      beforeEach(async () => {
        findAccessCard().vm.$emit('show-confirm');
        instanceAccessHandler.mockResolvedValue(
          instanceAccessResponse(instanceAccess('TRIAL_ACTIVE', null, { expiresOn: '2026-11-13' })),
        );
        findAccessCard().vm.$emit('start-trial');
        await nextTick();
      });

      it('shows the start as running', () => {
        expect(startTrialHandler).toHaveBeenCalledTimes(1);
        expect(findAccessCard().props('starting')).toBe(true);
      });

      it('reloads the instance access and shows the active trial', async () => {
        await waitForPromises();

        expect(instanceAccessHandler).toHaveBeenCalledTimes(2);
        expect(findAccessCard().props()).toMatchObject({
          starting: false,
          confirmVisible: false,
          access: { state: 'TRIAL_ACTIVE' },
        });
        expect(findTrialError().exists()).toBe(false);
      });
    });

    describe('when the server refuses the trial', () => {
      beforeEach(async () => {
        startTrialHandler.mockResolvedValue(
          instanceStartTrialResponse(['Contact sales to get GitLab Orbit for this instance.']),
        );
        findAccessCard().vm.$emit('show-confirm');
        findAccessCard().vm.$emit('start-trial');
        await waitForPromises();
      });

      it('closes the confirm', () => {
        expect(findAccessCard().props('confirmVisible')).toBe(false);
      });

      it('shows the server message in a danger alert', () => {
        expect(findTrialError().text()).toContain(
          'Contact sales to get GitLab Orbit for this instance.',
        );
        expect(findTrialError().props('title')).toBe('Could not start your trial');
      });

      it('hides the alert on dismiss', async () => {
        findTrialError().vm.$emit('dismiss');
        await nextTick();

        expect(findTrialError().exists()).toBe(false);
      });
    });

    describe('when the request does not reach GitLab', () => {
      beforeEach(async () => {
        startTrialHandler.mockRejectedValue(new Error('Network error'));
        findAccessCard().vm.$emit('start-trial');
        await waitForPromises();
      });

      it('shows the connection message and reloads the access', () => {
        expect(findTrialError().text()).toContain(
          'The request did not reach GitLab. Check your connection and try again.',
        );
        expect(instanceAccessHandler).toHaveBeenCalledTimes(2);
        expect(findAccessCard().props('starting')).toBe(false);
      });
    });
  });
});
