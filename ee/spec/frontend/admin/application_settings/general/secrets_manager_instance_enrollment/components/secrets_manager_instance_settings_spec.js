import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import SecretsManagerPaidAlert from 'ee/ci/secrets/components/secrets_manager_paid_alert.vue';
import SecretsManagerInstanceSettings from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/components/secrets_manager_instance_settings.vue';
import SecretsManagerInstanceEnrollmentToggle from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/components/secrets_manager_instance_enrollment_toggle.vue';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';
import getInstanceEntitlementQuery from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/queries/get_instance_secrets_manager_entitlement.query.graphql';
import getInstanceSecretsManagerEnrollmentQuery from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/queries/get_instance_secrets_manager_enrollment.query.graphql';
import enableInstanceSecretsManagerAddOnMutation from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/mutations/enable_instance_secrets_manager_add_on.mutation.graphql';
import startInstanceSecretsManagerTrialMutation from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/mutations/start_instance_secrets_manager_trial.mutation.graphql';
import refreshInstanceSecretsManagerEntitlementMutation from 'ee/admin/application_settings/general/secrets_manager_instance_enrollment/graphql/mutations/refresh_instance_secrets_manager_entitlement.mutation.graphql';

Vue.use(VueApollo);
jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');

describe('SecretsManagerInstanceSettings', () => {
  let wrapper;
  let mockEntitlementQuery;
  let mockEnrollmentQuery;
  let mockStartTrialMutation;
  let mockEnableAddOnMutation;
  let mockRefreshEntitlementMutation;

  const instanceEntitlementResponse = ({
    state = 'PAID',
    blockedReason = null,
    onDemandEnabled = true,
    offlineLicense = false,
    offlineFlexLicense = null,
  } = {}) => ({
    data: {
      secretsManagerInstanceEntitlement: {
        __typename: 'SecretsManagerEntitlement',
        state,
        blockedReason,
        trialStartedAt: null,
        trialExpiresAt: null,
        creditsRemaining: 50,
        creditsTotal: 500,
        onDemandEnabled,
        offlineLicense,
        offlineFlexLicense,
      },
    },
  });
  const enrollmentResponse = (enrolled) => ({
    data: {
      instanceSecretsManagerEnrollment: {
        __typename: 'SecretsManagerInstanceEnrollment',
        enrolled,
        beta: enrolled,
      },
    },
  });
  const startTrialResponse = ({ entitlement = { state: 'TRIAL' }, errors = [] } = {}) => ({
    data: {
      secretsManagerInstanceStartTrial: {
        __typename: 'SecretsManagerInstanceStartTrialPayload',
        entitlement: entitlement && {
          __typename: 'SecretsManagerEntitlement',
          blockedReason: null,
          trialStartedAt: '2026-09-10',
          trialExpiresAt: '2026-10-10',
          creditsRemaining: 500,
          creditsTotal: 500,
          onDemandEnabled: true,
          offlineLicense: false,
          offlineFlexLicense: null,
          ...entitlement,
        },
        errors,
      },
    },
  });
  const enableAddOnResponse = ({ entitlement = { state: 'PAID' }, errors = [] } = {}) => ({
    data: {
      secretsManagerInstanceEnableAddOn: {
        __typename: 'SecretsManagerInstanceEnableAddOnPayload',
        entitlement: entitlement && {
          __typename: 'SecretsManagerEntitlement',
          blockedReason: null,
          trialStartedAt: null,
          trialExpiresAt: null,
          creditsRemaining: null,
          creditsTotal: null,
          onDemandEnabled: true,
          offlineLicense: false,
          offlineFlexLicense: null,
          ...entitlement,
        },
        errors,
      },
    },
  });

  const refreshEntitlementResponse = ({ entitlement = {}, errors = [] } = {}) => ({
    data: {
      secretsManagerInstanceRefreshEntitlement: {
        __typename: 'SecretsManagerInstanceRefreshEntitlementPayload',
        entitlement: entitlement && {
          __typename: 'SecretsManagerEntitlement',
          state: 'TRIAL_ELIGIBLE',
          blockedReason: null,
          trialStartedAt: null,
          trialExpiresAt: null,
          creditsRemaining: null,
          creditsTotal: null,
          onDemandEnabled: true,
          offlineLicense: false,
          offlineFlexLicense: null,
          ...entitlement,
        },
        errors,
      },
    },
  });

  const findEnrollmentToggle = () => wrapper.findComponent(SecretsManagerInstanceEnrollmentToggle);
  const findErrorAlert = () => wrapper.findComponentByTestId('settings-error-alert');
  const findEnrollSuccessAlert = () => wrapper.findComponentByTestId('enroll-success-alert');
  const findPaidAlert = () => wrapper.findComponent(SecretsManagerPaidAlert);
  const findTrialEnrollmentWarning = () =>
    wrapper.findComponentByTestId('trial-enrollment-warning-alert');
  const findStartTrialButton = () => wrapper.findComponentByTestId('instance-start-trial-button');
  const findStartTrialModal = () => wrapper.findComponent(StartTrialModal);
  const findEnableAddOnButton = () =>
    wrapper.findComponentByTestId('instance-enable-add-on-button');
  const findEnableAddOnModal = () => wrapper.findComponent(EnableAddOnModal);

  const createComponent = () => {
    const apolloProvider = createMockApollo([
      [getInstanceEntitlementQuery, mockEntitlementQuery],
      [getInstanceSecretsManagerEnrollmentQuery, mockEnrollmentQuery],
      [startInstanceSecretsManagerTrialMutation, mockStartTrialMutation],
      [enableInstanceSecretsManagerAddOnMutation, mockEnableAddOnMutation],
      [refreshInstanceSecretsManagerEntitlementMutation, mockRefreshEntitlementMutation],
    ]);

    wrapper = shallowMountExtended(SecretsManagerInstanceSettings, {
      apolloProvider,
      stubs: {
        // Explicit stub so the `onDemandEnabled` prop stays declared. Vue 3
        // treats `on*`-named attributes on prop-less auto-stubs as event
        // handlers and warns.
        EnableAddOnModal: stubComponent(EnableAddOnModal),
      },
    });
  };

  beforeEach(() => {
    mockEntitlementQuery = jest.fn().mockResolvedValue(instanceEntitlementResponse());
    mockEnrollmentQuery = jest.fn().mockResolvedValue(enrollmentResponse(false));
    mockStartTrialMutation = jest.fn().mockResolvedValue(startTrialResponse());
    mockEnableAddOnMutation = jest.fn().mockResolvedValue(enableAddOnResponse());
    mockRefreshEntitlementMutation = jest.fn().mockResolvedValue(refreshEntitlementResponse());
  });

  describe('on mount', () => {
    it('queries the enrollment state and passes it to the toggle', async () => {
      createComponent();
      await waitForPromises();

      expect(mockEnrollmentQuery).toHaveBeenCalledTimes(1);
      expect(findEnrollmentToggle().props('isEnrolled')).toBe(false);
    });

    it('reflects an enrolled state', async () => {
      mockEnrollmentQuery.mockResolvedValueOnce(enrollmentResponse(true));
      createComponent();
      await waitForPromises();

      expect(findEnrollmentToggle().props('isEnrolled')).toBe(true);
    });

    it('sets the toggle to loading while the enrollment query is in flight', () => {
      createComponent();

      expect(findEnrollmentToggle().props('loading')).toBe(true);
    });

    it('does not render the error alert initially', async () => {
      createComponent();
      await waitForPromises();

      expect(findErrorAlert().exists()).toBe(false);
    });

    it('renders an inline error when the enrollment query fails', async () => {
      mockEnrollmentQuery.mockRejectedValueOnce(new Error('boom'));
      createComponent();
      await waitForPromises();

      expect(findErrorAlert().exists()).toBe(true);
      expect(findErrorAlert().text()).not.toBe('');
    });

    it('hides the error alert when dismissed', async () => {
      mockEnrollmentQuery.mockRejectedValueOnce(new Error('boom'));
      createComponent();
      await waitForPromises();

      findErrorAlert().vm.$emit('dismiss');
      await nextTick();

      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('enrollment state updates', () => {
    it('updates the toggle state when the toggle emits toggled', async () => {
      createComponent();
      await waitForPromises();

      findEnrollmentToggle().vm.$emit('toggled', true);
      await nextTick();

      expect(findEnrollmentToggle().props('isEnrolled')).toBe(true);
    });

    describe('enable success alert', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('is hidden by default', () => {
        expect(findEnrollSuccessAlert().exists()).toBe(false);
      });

      it('renders after enrolling', async () => {
        findEnrollmentToggle().vm.$emit('toggled', true);
        await nextTick();

        expect(findEnrollSuccessAlert().exists()).toBe(true);
      });

      it('is hidden again after unenrolling', async () => {
        findEnrollmentToggle().vm.$emit('toggled', true);
        await nextTick();

        findEnrollmentToggle().vm.$emit('toggled', false);
        await nextTick();

        expect(findEnrollSuccessAlert().exists()).toBe(false);
      });

      it('hides the alert when dismissed', async () => {
        findEnrollmentToggle().vm.$emit('toggled', true);
        await nextTick();

        findEnrollSuccessAlert().vm.$emit('dismiss');
        await nextTick();

        expect(findEnrollSuccessAlert().exists()).toBe(false);
      });
    });
  });

  describe('entitlement query', () => {
    describe('when query has loaded', () => {
      it('does not disable the toggle when on-demand is enabled', async () => {
        createComponent();
        await waitForPromises();

        expect(findEnrollmentToggle().props('disabled')).toBe(false);
      });

      it.each([
        { state: 'BLOCKED', blockedReason: 'ON_DEMAND_DISABLED' },
        { state: 'BLOCKED', blockedReason: 'TRIAL_EXPIRED' },
        { state: 'BLOCKED', blockedReason: 'CREDITS_EXHAUSTED' },
        { state: 'BLOCKED', blockedReason: 'GRACE' },
        { state: 'BLOCKED', blockedReason: 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED' },
        { state: 'INELIGIBLE', blockedReason: null },
      ])(
        'disables the toggle when entitlement state is $state with reason $blockedReason',
        async ({ state, blockedReason }) => {
          mockEntitlementQuery = jest
            .fn()
            .mockResolvedValue(instanceEntitlementResponse({ state, blockedReason }));
          createComponent();
          await waitForPromises();

          expect(findEnrollmentToggle().props('disabled')).toBe(true);
        },
      );

      it.each([{ state: 'TRIAL' }, { state: 'PAID' }, { state: 'OFFLINE_PAID' }])(
        'keeps the toggle enabled for $state state when on-demand is disabled',
        async ({ state }) => {
          mockEntitlementQuery = jest
            .fn()
            .mockResolvedValue(instanceEntitlementResponse({ state, onDemandEnabled: false }));
          createComponent();
          await waitForPromises();

          expect(findEnrollmentToggle().props('disabled')).toBe(false);
        },
      );

      it('renders an inline error when the entitlement query fails', async () => {
        mockEntitlementQuery = jest
          .fn()
          .mockRejectedValue(new Error('Failed to fetch entitlement.'));
        createComponent();
        await waitForPromises();

        expect(findErrorAlert().exists()).toBe(true);
      });
    });
  });

  describe('start trial flow', () => {
    const createTrialEligibleComponent = async ({ offlineLicense = false } = {}) => {
      mockEntitlementQuery = jest
        .fn()
        .mockResolvedValue(
          instanceEntitlementResponse({ state: 'TRIAL_ELIGIBLE', offlineLicense }),
        );
      createComponent();
      await waitForPromises();
    };

    describe('start trial button', () => {
      it('replaces the toggle when the entitlement is trial eligible', async () => {
        await createTrialEligibleComponent();

        expect(findStartTrialButton().exists()).toBe(true);
        expect(findEnrollmentToggle().exists()).toBe(false);
      });

      it('is hidden when the instance license is offline (airgapped)', async () => {
        await createTrialEligibleComponent({ offlineLicense: true });

        expect(findStartTrialButton().exists()).toBe(false);
        expect(findEnrollmentToggle().exists()).toBe(true);
      });

      it('is hidden when the entitlement is not trial eligible', async () => {
        createComponent();
        await waitForPromises();

        expect(findStartTrialButton().exists()).toBe(false);
        expect(findEnrollmentToggle().exists()).toBe(true);
      });
    });

    describe('start trial confirmation modal', () => {
      beforeEach(async () => {
        await createTrialEligibleComponent();
      });

      it('is hidden by default and opens when the start trial button is clicked', async () => {
        expect(findStartTrialModal().props('visible')).toBe(false);

        findStartTrialButton().vm.$emit('click');
        await nextTick();

        expect(findStartTrialModal().props('visible')).toBe(true);
      });

      it('is dismissable', async () => {
        findStartTrialButton().vm.$emit('click');
        await nextTick();

        findStartTrialModal().vm.$emit('hide');
        await nextTick();

        expect(findStartTrialModal().props('visible')).toBe(false);
      });
    });

    describe('starting the trial', () => {
      const confirmTrial = async () => {
        findStartTrialButton().vm.$emit('click');
        await nextTick();
        findStartTrialModal().vm.$emit('start-trial');
        await nextTick();
      };

      beforeEach(async () => {
        await createTrialEligibleComponent();
      });

      it('dismisses the modal and sets the button to loading while the mutation runs', async () => {
        await confirmTrial();

        expect(findStartTrialModal().props('visible')).toBe(false);
        expect(findStartTrialButton().props('loading')).toBe(true);
      });

      it('starts the trial, enrolls, and shows the success alert', async () => {
        await confirmTrial();
        await waitForPromises();

        expect(mockStartTrialMutation).toHaveBeenCalledTimes(1);
        expect(findEnrollSuccessAlert().exists()).toBe(true);
        expect(findStartTrialButton().exists()).toBe(false);
        expect(findEnrollmentToggle().props('isEnrolled')).toBe(true);
      });

      it('keeps the trial but shows a warning when enrollment fails after the trial starts', async () => {
        mockStartTrialMutation.mockResolvedValueOnce(
          startTrialResponse({ errors: ['Trial started; enrollment failed'] }),
        );

        await confirmTrial();
        await waitForPromises();

        expect(findTrialEnrollmentWarning().text()).toBe(
          'The trial has started, but the instance failed to enable the secrets manager. Please try again with the toggle below.',
        );
        expect(findErrorAlert().exists()).toBe(false);
        expect(findEnrollSuccessAlert().exists()).toBe(false);
        expect(findStartTrialButton().exists()).toBe(false);
        expect(findEnrollmentToggle().props('isEnrolled')).toBe(false);
      });

      it('clears the warning and shows the success alert after retrying with the toggle', async () => {
        mockStartTrialMutation.mockResolvedValueOnce(
          startTrialResponse({ errors: ['Trial started; enrollment failed'] }),
        );

        await confirmTrial();
        await waitForPromises();

        findEnrollmentToggle().vm.$emit('toggled', true);
        await nextTick();

        expect(findTrialEnrollmentWarning().exists()).toBe(false);
        expect(findEnrollSuccessAlert().exists()).toBe(true);
        expect(findEnrollmentToggle().props('isEnrolled')).toBe(true);
      });

      it('shows an error and keeps the button when the mutation fails', async () => {
        mockStartTrialMutation.mockResolvedValueOnce(
          startTrialResponse({ entitlement: null, errors: ['Trial failed'] }),
        );

        await confirmTrial();
        await waitForPromises();

        expect(findErrorAlert().text()).toBe(
          'The GitLab Secrets Manager trial could not be started. Please try again.',
        );
        expect(findEnrollSuccessAlert().exists()).toBe(false);
        expect(findStartTrialButton().exists()).toBe(true);
        expect(findEnrollmentToggle().exists()).toBe(false);
        expect(findStartTrialButton().props('loading')).toBe(false);
      });

      // The backend nulls the entitlement when the post-trial lookup fails,
      // even though the trial started and the instance is enrolled.
      it('treats a null entitlement with no errors as success and refetches the entitlement', async () => {
        mockStartTrialMutation.mockResolvedValueOnce(
          startTrialResponse({ entitlement: null, errors: [] }),
        );
        // the refetch resolves the post-trial state
        mockEntitlementQuery.mockResolvedValue(instanceEntitlementResponse({ state: 'TRIAL' }));

        await confirmTrial();
        await waitForPromises();

        expect(findErrorAlert().exists()).toBe(false);
        expect(findEnrollSuccessAlert().exists()).toBe(true);
        expect(findEnrollmentToggle().props('isEnrolled')).toBe(true);
        // initial load + refetch after the null-entitlement success
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });

      it('shows an error and keeps the button when the mutation throws', async () => {
        mockStartTrialMutation.mockRejectedValueOnce(new Error('boom'));

        await confirmTrial();
        await waitForPromises();

        expect(findErrorAlert().text()).toBe(
          'The GitLab Secrets Manager trial could not be started. Please try again.',
        );
        expect(findStartTrialButton().exists()).toBe(true);
      });
    });
  });

  describe('enable add-on flow', () => {
    const createTrialEligibleComponent = async ({ onDemandEnabled = true } = {}) => {
      mockEntitlementQuery = jest
        .fn()
        .mockResolvedValue(
          instanceEntitlementResponse({ state: 'TRIAL_ELIGIBLE', onDemandEnabled }),
        );
      createComponent();
      await waitForPromises();
    };

    describe('enable add-on button', () => {
      it('renders next to the trial button when the entitlement is trial eligible', async () => {
        await createTrialEligibleComponent();

        expect(findEnableAddOnButton().exists()).toBe(true);
        expect(findStartTrialButton().exists()).toBe(true);
        expect(findEnrollmentToggle().exists()).toBe(false);
      });

      it('is hidden when the entitlement is not trial eligible', async () => {
        createComponent();
        await waitForPromises();

        expect(findEnableAddOnButton().exists()).toBe(false);
      });

      it('is hidden when the instance license is offline (airgapped)', async () => {
        mockEntitlementQuery = jest
          .fn()
          .mockResolvedValue(
            instanceEntitlementResponse({ state: 'TRIAL_ELIGIBLE', offlineLicense: true }),
          );
        createComponent();
        await waitForPromises();

        expect(findEnableAddOnButton().exists()).toBe(false);
        expect(findEnrollmentToggle().exists()).toBe(true);
      });
    });

    describe('enable add-on confirmation modal', () => {
      beforeEach(async () => {
        await createTrialEligibleComponent();
      });

      it('is hidden by default and opens when the button is clicked', async () => {
        expect(findEnableAddOnModal().props('visible')).toBe(false);

        findEnableAddOnButton().vm.$emit('click');
        await nextTick();

        expect(findEnableAddOnModal().props('visible')).toBe(true);
        expect(mockEnableAddOnMutation).not.toHaveBeenCalled();
      });

      it('passes onDemandEnabled from the entitlement', () => {
        expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(true);
      });

      it('passes onDemandEnabled=false when on-demand billing is not accepted', async () => {
        await createTrialEligibleComponent({ onDemandEnabled: false });

        expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
      });

      it('opens without re-checking the entitlement when on-demand billing is accepted', async () => {
        findEnableAddOnButton().vm.$emit('click');
        await waitForPromises();

        expect(mockRefreshEntitlementMutation).not.toHaveBeenCalled();
        expect(findEnableAddOnModal().props('visible')).toBe(true);
      });

      describe('when the cached entitlement says on-demand billing is not accepted', () => {
        beforeEach(async () => {
          await createTrialEligibleComponent({ onDemandEnabled: false });
        });

        it('re-checks the entitlement, showing progress, before opening the modal', async () => {
          findEnableAddOnButton().vm.$emit('click');
          await nextTick();

          expect(mockRefreshEntitlementMutation).toHaveBeenCalledTimes(1);
          expect(findEnableAddOnButton().props('loading')).toBe(true);
          expect(findStartTrialButton().props('disabled')).toBe(true);
          expect(findEnableAddOnModal().props('visible')).toBe(false);

          await waitForPromises();

          expect(findEnableAddOnButton().props('loading')).toBe(false);
          expect(findEnableAddOnModal().props('visible')).toBe(true);
        });

        it('opens the modal with the consent given since the page loaded', async () => {
          findEnableAddOnButton().vm.$emit('click');
          await waitForPromises();

          expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(true);
          expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(false);
        });

        it('clears the failed-check alert when a later check succeeds', async () => {
          mockRefreshEntitlementMutation.mockRejectedValueOnce(new Error('unreachable'));
          findEnableAddOnButton().vm.$emit('click');
          await waitForPromises();
          findEnableAddOnModal().vm.$emit('hide');
          await nextTick();

          findEnableAddOnButton().vm.$emit('click');
          await waitForPromises();

          expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(false);
        });

        it('checks once when the button is clicked again while the check runs', async () => {
          findEnableAddOnButton().vm.$emit('click');
          findEnableAddOnButton().vm.$emit('click');
          await waitForPromises();

          expect(mockRefreshEntitlementMutation).toHaveBeenCalledTimes(1);
        });

        it('keeps the cached entitlement when the re-check returns no entitlement', async () => {
          mockRefreshEntitlementMutation.mockResolvedValueOnce(
            refreshEntitlementResponse({
              entitlement: null,
              errors: ['Unable to reach the subscription service. Please try again later.'],
            }),
          );

          findEnableAddOnButton().vm.$emit('click');
          await waitForPromises();

          expect(findEnableAddOnModal().props('visible')).toBe(true);
          expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
          expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(true);
          expect(findErrorAlert().exists()).toBe(false);
        });

        it('keeps the cached entitlement and reports the error when the re-check fails', async () => {
          const error = new Error('rate limited');
          mockRefreshEntitlementMutation.mockRejectedValueOnce(error);

          findEnableAddOnButton().vm.$emit('click');
          await waitForPromises();

          expect(findEnableAddOnModal().props('visible')).toBe(true);
          expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
          expect(findEnableAddOnButton().props('loading')).toBe(false);
          expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(true);
          expect(findErrorAlert().exists()).toBe(false);
          expect(Sentry.captureException).toHaveBeenCalledWith(error);
        });
      });

      it('closes without enabling when dismissed', async () => {
        findEnableAddOnButton().vm.$emit('click');
        await nextTick();

        findEnableAddOnModal().vm.$emit('hide');
        await nextTick();

        expect(findEnableAddOnModal().props('visible')).toBe(false);
        expect(mockEnableAddOnMutation).not.toHaveBeenCalled();
      });
    });

    describe('enabling the add-on', () => {
      const confirmEnableAddOn = async () => {
        findEnableAddOnButton().vm.$emit('click');
        await nextTick();
        findEnableAddOnModal().vm.$emit('enable');
        await nextTick();
      };

      beforeEach(async () => {
        await createTrialEligibleComponent();
      });

      it('dismisses the modal, sets the button to loading, and disables the trial button', async () => {
        await confirmEnableAddOn();

        expect(findEnableAddOnModal().props('visible')).toBe(false);
        expect(findEnableAddOnButton().props('loading')).toBe(true);
        expect(findStartTrialButton().props('disabled')).toBe(true);
      });

      it('enables the add-on and shows the success alert', async () => {
        await confirmEnableAddOn();
        await waitForPromises();

        expect(mockEnableAddOnMutation).toHaveBeenCalledTimes(1);
        expect(findEnrollSuccessAlert().exists()).toBe(true);
        expect(findEnableAddOnButton().exists()).toBe(false);
        expect(findEnrollmentToggle().props('isEnrolled')).toBe(true);
      });

      it('shows the mutation error and keeps the buttons when enabling fails', async () => {
        mockEnableAddOnMutation.mockResolvedValueOnce(
          enableAddOnResponse({
            entitlement: null,
            errors: ['This instance is not eligible to enable the Secrets Manager add-on.'],
          }),
        );

        await confirmEnableAddOn();
        await waitForPromises();

        expect(findErrorAlert().text()).toBe(
          'This instance is not eligible to enable the Secrets Manager add-on.',
        );
        expect(findEnrollSuccessAlert().exists()).toBe(false);
        expect(findEnableAddOnButton().exists()).toBe(true);
        expect(findEnableAddOnButton().props('loading')).toBe(false);
      });

      it('shows a generic error when the mutation throws', async () => {
        mockEnableAddOnMutation.mockRejectedValueOnce(new Error('boom'));

        await confirmEnableAddOn();
        await waitForPromises();

        expect(findErrorAlert().text()).toBe(
          'The GitLab Secrets Manager add-on could not be enabled. Please try again.',
        );
        expect(findEnableAddOnButton().exists()).toBe(true);
      });

      it('disables the enable add-on button while a trial is starting', async () => {
        findStartTrialButton().vm.$emit('click');
        await nextTick();
        findStartTrialModal().vm.$emit('start-trial');
        await nextTick();

        expect(findEnableAddOnButton().props('disabled')).toBe(true);
      });
    });
  });

  describe('trial note', () => {
    it('shows the trial note when the license is not offline', async () => {
      createComponent();
      await waitForPromises();

      expect(findEnrollmentToggle().props('showTrialNote')).toBe(true);
    });

    it('hides the trial note when the instance license is offline (airgapped)', async () => {
      mockEntitlementQuery = jest
        .fn()
        .mockResolvedValue(
          instanceEntitlementResponse({ state: 'OFFLINE_PAID', offlineLicense: true }),
        );
      createComponent();
      await waitForPromises();

      expect(findEnrollmentToggle().props('showTrialNote')).toBe(false);
    });
  });

  describe('credit consumption alert', () => {
    const createWithEntitlement = async (entitlement) => {
      mockEntitlementQuery = jest.fn().mockResolvedValue(instanceEntitlementResponse(entitlement));
      createComponent();
      await waitForPromises();
    };

    it.each`
      state               | offlineLicense | offlineFlexLicense | shown
      ${'TRIAL_ELIGIBLE'} | ${false}       | ${null}            | ${true}
      ${'TRIAL'}          | ${false}       | ${null}            | ${true}
      ${'PAID'}           | ${false}       | ${null}            | ${true}
      ${'OFFLINE_PAID'}   | ${true}        | ${true}            | ${true}
      ${'OFFLINE_PAID'}   | ${true}        | ${false}           | ${false}
      ${'BLOCKED'}        | ${true}        | ${null}            | ${false}
    `(
      'shown is $shown for $state (offline: $offlineLicense, Flex: $offlineFlexLicense)',
      async ({ state, offlineLicense, offlineFlexLicense, shown }) => {
        await createWithEntitlement({
          state,
          blockedReason: state === 'BLOCKED' ? 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED' : null,
          offlineLicense,
          offlineFlexLicense,
        });

        expect(findPaidAlert().exists()).toBe(shown);
      },
    );
  });

  describe('offline license alert', () => {
    const findOfflineLicenseAlert = () => wrapper.findComponentByTestId('offline-license-alert');

    it.each`
      state             | offlineLicense | shown
      ${'BLOCKED'}      | ${true}        | ${true}
      ${'BLOCKED'}      | ${false}       | ${false}
      ${'OFFLINE_PAID'} | ${true}        | ${false}
    `(
      'shown is $shown for $state (offline: $offlineLicense)',
      async ({ state, offlineLicense, shown }) => {
        mockEntitlementQuery = jest.fn().mockResolvedValue(
          instanceEntitlementResponse({
            state,
            blockedReason: state === 'BLOCKED' ? 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED' : null,
            offlineLicense,
          }),
        );
        createComponent();
        await waitForPromises();

        expect(findOfflineLicenseAlert().exists()).toBe(shown);
      },
    );

    it('tells the admin to purchase a license', async () => {
      mockEntitlementQuery = jest.fn().mockResolvedValue(
        instanceEntitlementResponse({
          state: 'BLOCKED',
          blockedReason: 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED',
          offlineLicense: true,
        }),
      );
      createComponent();
      await waitForPromises();

      expect(findOfflineLicenseAlert().props('variant')).toBe('warning');
      expect(findOfflineLicenseAlert().text()).toBe(
        'Contact your subscription owner to purchase a license and enable GitLab Secrets Manager.',
      );
    });
  });
});
