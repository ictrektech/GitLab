import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlLink, GlSkeletonLoader, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import {
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_PROVISIONING,
  SECRET_MANAGER_STATUS_DEPROVISIONING,
  ENTITY_PROJECT,
  ENTITY_GROUP,
} from 'ee/ci/secrets/constants';
import getProjectSecretManagerStatusQuery from 'ee/ci/secrets/graphql/queries/get_project_secret_manager_status.query.graphql';
import getEntitlementQuery from 'ee/ci/secrets/graphql/queries/get_secrets_manager_entitlement.graphql';
import getOpenbaoHealthQuery from 'ee/ci/secrets/graphql/queries/get_openbao_health.query.graphql';
import getEnrollmentQuery from 'ee/pages/projects/shared/permissions/secrets_manager/graphql/get_gsm_namespace_enrollment.query.graphql';
import getGroupSecretManagerStatusQuery from 'ee/ci/secrets/graphql/queries/get_group_secret_manager_status.query.graphql';
import startTrialMutation from 'ee/ci/secrets/graphql/mutations/start_secrets_manager_trial.mutation.graphql';
import enableAddOnMutation from 'ee/ci/secrets/graphql/mutations/enable_secrets_manager_add_on.mutation.graphql';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import SecretsBetaTransitionAlert from 'ee/ci/secrets/components/secrets_beta_transition_alert.vue';
import SecretsManagerPaidAlert from 'ee/ci/secrets/components/secrets_manager_paid_alert.vue';
import SecretsManagerTrialAlert from 'ee/ci/secrets/components/secrets_manager_trial_alert.vue';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';
import PermissionsSettings from 'ee/pages/projects/shared/permissions/secrets_manager/components/secrets_manager_permissions_settings.vue';
import SaasEnrollmentToggle from 'ee/pages/projects/shared/permissions/secrets_manager/components/secrets_manager_saas_enrollment_toggle.vue';
import SecretManagerSettings, {
  POLL_INTERVAL,
} from 'ee/pages/projects/shared/permissions/secrets_manager/secrets_manager_settings.vue';
import {
  enableAddOnSuccessResponse,
  startTrialErrorResponse,
  startTrialSuccessResponse,
} from 'ee_jest/ci/secrets/mock_data';
import {
  entitlementResponse,
  enrollmentStatusResponse,
  openbaoHealthResponse,
  secretManagerSettingsResponse,
  groupSecretManagerSettingsResponse,
} from './mock_data';

Vue.use(VueApollo);

describe('SecretManagerSettings', () => {
  let wrapper;
  let mockSecretManagerStatus;
  let mockGetEntitlement;
  let mockOpenbaoHealth;
  let mockGetEnrollment;
  let mockStartTrial;
  let mockEnableAddOn;

  const activeResponse = secretManagerSettingsResponse(SECRET_MANAGER_STATUS_ACTIVE);
  const provisioningResponse = secretManagerSettingsResponse(SECRET_MANAGER_STATUS_PROVISIONING);
  const deprovisioningResponse = secretManagerSettingsResponse(
    SECRET_MANAGER_STATUS_DEPROVISIONING,
  );
  const inactiveResponse = secretManagerSettingsResponse(null);
  const secretsManagerStatusErrorResponse = secretManagerSettingsResponse(null, [
    { message: 'Some error occurred' },
  ]);

  const groupActiveResponse = groupSecretManagerSettingsResponse(SECRET_MANAGER_STATUS_ACTIVE);
  const groupProvisioningResponse = groupSecretManagerSettingsResponse(
    SECRET_MANAGER_STATUS_PROVISIONING,
  );
  const groupDeprovisioningResponse = groupSecretManagerSettingsResponse(
    SECRET_MANAGER_STATUS_DEPROVISIONING,
  );
  const groupInactiveResponse = groupSecretManagerSettingsResponse(null);

  const fullPath = 'gitlab-org/gitlab';
  const topLevelGroupFullPath = 'gitlab-org';

  const createComponent = async ({ context = ENTITY_PROJECT, mocks = {}, ...props } = {}) => {
    const handlers = [
      [getEntitlementQuery, mockGetEntitlement],
      [getOpenbaoHealthQuery, mockOpenbaoHealth],
      [getProjectSecretManagerStatusQuery, mockSecretManagerStatus],
      [getGroupSecretManagerStatusQuery, mockSecretManagerStatus],
      [getEnrollmentQuery, mockGetEnrollment],
      [startTrialMutation, mockStartTrial],
      [enableAddOnMutation, mockEnableAddOn],
    ];

    const defaultProps = {
      canEnrollNamespace: true,
      canManageSecretsManager: true,
      context,
      fullPath,
      isNamespaceEnrollable: false,
      topLevelGroupFullPath,
    };

    wrapper = shallowMountExtended(SecretManagerSettings, {
      apolloProvider: createMockApollo(handlers),
      propsData: {
        ...defaultProps,
        ...props,
      },
      mocks,
      stubs: {
        GlSprintf,
        // Keeps `onDemandEnabled` declared: Vue 3 treats `on*` attributes on
        // auto-stubs as event handlers.
        EnableAddOnModal: stubComponent(EnableAddOnModal),
      },
    });

    await waitForPromises();
    await nextTick();
  };

  const findBetaAlert = () => wrapper.findComponent(SecretsBetaTransitionAlert);
  const findTrialAlert = () => wrapper.findComponent(SecretsManagerTrialAlert);
  const findPaidAlert = () => wrapper.findComponent(SecretsManagerPaidAlert);
  const findEnableAddOnModal = () => wrapper.findComponent(EnableAddOnModal);
  const findStartTrialModal = () => wrapper.findComponent(StartTrialModal);
  const findError = () => wrapper.findByTestId('secret-manager-error');
  const findShowSettingsError = () => wrapper.findByTestId('secret-manager-show-settings-error');
  const findLearnMoreLink = () => wrapper.findComponent(GlLink);
  const findNonTlgSettingsDescription = () => wrapper.findByTestId('non-tlg-settings-description');
  const findNonTlgSettingsTitle = () => wrapper.findByTestId('non-tlg-settings-title');
  const findPermissionsSettings = () => wrapper.findComponent(PermissionsSettings);
  const findOpenbaoUnhealthyAlert = () => wrapper.findByTestId('openbao-unhealthy-alert');
  const findSettings = () => wrapper.findByTestId('secret-manager');
  const findTrialEligibleGuidance = () => wrapper.findByTestId('trial-eligible-guidance-alert');
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findSaasEnrollmentToggle = () => wrapper.findComponent(SaasEnrollmentToggle);

  const advanceToNextFetch = (milliseconds) => {
    jest.advanceTimersByTime(milliseconds);
  };

  const pollNextStatus = async (queryResponse) => {
    mockSecretManagerStatus.mockResolvedValue(queryResponse);
    advanceToNextFetch(POLL_INTERVAL);

    await waitForPromises();
    await nextTick();
  };

  beforeEach(() => {
    mockSecretManagerStatus = jest.fn();
    mockGetEntitlement = jest.fn().mockResolvedValue(entitlementResponse());
    mockOpenbaoHealth = jest.fn().mockResolvedValue(openbaoHealthResponse());
    mockGetEnrollment = jest.fn().mockResolvedValue(enrollmentStatusResponse());
    mockStartTrial = jest.fn().mockResolvedValue(startTrialSuccessResponse());
    mockEnableAddOn = jest.fn().mockResolvedValue(enableAddOnSuccessResponse());
  });

  describe('template', () => {
    beforeEach(() => {
      mockSecretManagerStatus.mockResolvedValue(inactiveResponse);
    });

    describe('when user does not have permission to manage secrets manager', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(activeResponse);
        await createComponent({ canManageSecretsManager: false });
      });

      it('passes the permission to the permissions settings', () => {
        expect(findPermissionsSettings().props('canManageSecretsManager')).toBe(false);
      });
    });

    describe('when queries are loading', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders skeleton loader', () => {
        expect(findSkeletonLoader().exists()).toBe(true);
        expect(findSettings().exists()).toBe(false);
      });
    });

    describe('when queries have loaded', () => {
      beforeEach(async () => {
        await createComponent({ isNamespaceEnrollable: true });
      });

      it('hides skeleton loader and renders the settings', () => {
        expect(findSkeletonLoader().exists()).toBe(false);
        expect(findSettings().exists()).toBe(true);
      });
    });

    // The section's visibility depends on the status (isActive), so the
    // skeleton must hold until it resolves, or the section pops in on ACTIVE.
    describe('when only the status query is still loading', () => {
      beforeEach(() => {
        mockSecretManagerStatus.mockReturnValue(new Promise(() => {}));
        createComponent();
        return waitForPromises();
      });

      it('keeps the skeleton loader', () => {
        expect(findSkeletonLoader().exists()).toBe(true);
        expect(findSettings().exists()).toBe(false);
      });
    });

    // subgroup or project
    describe('when namespace is not enrollable', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(activeResponse);
        await createComponent({ isNamespaceEnrollable: false });
      });

      it('does not query enrollment', () => {
        expect(mockGetEnrollment).toHaveBeenCalledTimes(0);
      });

      it('does not render SaaS enrollment toggle', () => {
        expect(findSaasEnrollmentToggle().exists()).toBe(false);
      });

      it('renders the settings title, description, and learn more link', () => {
        expect(findNonTlgSettingsTitle().text()).toBe('GitLab Secrets Manager');
        expect(findNonTlgSettingsDescription().exists()).toBe(true);
        expect(findLearnMoreLink().attributes('href')).toBe(
          '/help/ci/secrets/secrets_manager/_index',
        );
      });
    });

    describe('when namespace is a top-level group', () => {
      beforeEach(async () => {
        await createComponent({ isNamespaceEnrollable: true });
      });

      it('queries enrollment', () => {
        expect(mockGetEnrollment).toHaveBeenCalledTimes(1);
      });

      it('renders SaaS enrollment toggle', () => {
        expect(findSaasEnrollmentToggle().exists()).toBe(true);
        expect(findSaasEnrollmentToggle().props()).toMatchObject({
          canManageEnrollment: true,
          fullPath: 'gitlab-org/gitlab',
          hasEnrollmentQueryError: false,
          isEnrolled: true,
        });
      });

      it('does not render the non-tlg settings title or learn more link', () => {
        expect(findNonTlgSettingsTitle().exists()).toBe(false);
        expect(findNonTlgSettingsDescription().exists()).toBe(false);
        expect(findLearnMoreLink().exists()).toBe(false);
      });
    });

    // only applies to top-level group
    // the Rails view hides the setting for child groups and child projects when TLG is not enrolled
    describe('when root namespace is not enrolled', () => {
      beforeEach(() => {
        mockGetEnrollment = jest
          .fn()
          .mockResolvedValue(enrollmentStatusResponse({ enrolled: false }));
      });

      it('skips secrets manager status query', async () => {
        await createComponent({ isNamespaceEnrollable: true });

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(0);
      });

      it('passes enrollment state to SaaS toggle', async () => {
        await createComponent({ isNamespaceEnrollable: true });

        expect(findSaasEnrollmentToggle().props('isEnrolled')).toBe(false);
      });
    });

    // An explicit opt-out resolves to null on the backend, identical to
    // "not enrolled" above, so it needs no separate frontend case.
  });

  describe('when enrollment query fails for enrollable namespace', () => {
    beforeEach(async () => {
      mockGetEnrollment = jest.fn().mockRejectedValue(new Error('API error'));
      await createComponent({ isNamespaceEnrollable: true });
    });

    it('shows error message', () => {
      expect(findSaasEnrollmentToggle().props('hasEnrollmentQueryError')).toBe(true);
      expect(findError().text()).toBe(
        'An error occurred while fetching the secrets manager enrollment status. Please refresh the page.',
      );
    });
  });

  describe('entitlement query', () => {
    describe('when topLevelGroupFullPath is empty', () => {
      beforeEach(async () => {
        await createComponent({ topLevelGroupFullPath: '' });
      });

      it('skips the entitlement query', () => {
        expect(mockGetEntitlement).not.toHaveBeenCalled();
      });
    });

    describe('entitlement banners on the top-level group', () => {
      const createTlgComponent = async ({
        enrolled = true,
        canStartTrial = true,
        active = true,
        ...entitlement
      } = {}) => {
        mockSecretManagerStatus.mockResolvedValue(
          active ? groupActiveResponse : groupSecretManagerSettingsResponse(null),
        );
        mockGetEntitlement = jest.fn().mockResolvedValue(entitlementResponse(entitlement));
        mockGetEnrollment = jest.fn().mockResolvedValue(enrollmentStatusResponse({ enrolled }));
        await createComponent({
          context: ENTITY_GROUP,
          fullPath: topLevelGroupFullPath,
          isNamespaceEnrollable: true,
          canStartTrial,
        });
      };

      it('passes the entitlement to the trial alert', async () => {
        await createTlgComponent({ state: 'TRIAL' });

        expect(findTrialAlert().props('entitlement')).toMatchObject({ state: 'TRIAL' });
        expect(findPaidAlert().exists()).toBe(false);
      });

      it.each([true, false])(
        'passes enrolled (%s) as enabled to the paid alert when paid',
        async (enrolled) => {
          await createTlgComponent({ state: 'PAID', enrolled });

          expect(findPaidAlert().props('enabled')).toBe(enrolled);
        },
      );

      it('hides the settings for a beta group that is no longer trial eligible', async () => {
        await createTlgComponent({ state: 'INELIGIBLE', betaWindowEligible: true, active: false });

        expect(findSettings().exists()).toBe(false);
      });

      it('hides the CTAs when the user cannot start a trial', async () => {
        await createTlgComponent({
          state: 'TRIAL_ELIGIBLE',
          betaWindowEligible: true,
          canStartTrial: false,
        });

        expect(findBetaAlert().props('showCta')).toBe(false);
      });

      describe('for a beta group', () => {
        beforeEach(async () => {
          await createTlgComponent({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true });
        });

        it('shows the settings with the beta alert and CTAs', () => {
          expect(findSettings().exists()).toBe(true);
          expect(findBetaAlert().props()).toMatchObject({
            isBeta: true,
            isTrialEligible: true,
            betaProgramEnded: false,
            showCta: true,
          });
        });

        it('opens the start trial modal and starts the trial on confirm', async () => {
          findBetaAlert().vm.$emit('start-trial');
          await nextTick();
          expect(findStartTrialModal().props('visible')).toBe(true);

          findStartTrialModal().vm.$emit('start-trial');
          await waitForPromises();

          expect(findStartTrialModal().props('visible')).toBe(false);
          expect(mockStartTrial).toHaveBeenCalledWith({ groupPath: topLevelGroupFullPath });
          expect(mockGetEntitlement).toHaveBeenCalledTimes(2);
          expect(findError().exists()).toBe(false);
        });

        it('opens the enable add-on modal and enables the add-on on confirm', async () => {
          findBetaAlert().vm.$emit('enable-add-on');
          await nextTick();
          expect(findEnableAddOnModal().props('visible')).toBe(true);

          findEnableAddOnModal().vm.$emit('enable');
          await waitForPromises();

          expect(findEnableAddOnModal().props('visible')).toBe(false);
          expect(mockEnableAddOn).toHaveBeenCalledWith({ groupPath: topLevelGroupFullPath });
          expect(mockGetEntitlement).toHaveBeenCalledTimes(2);
        });

        it('keeps the block rendered while the entitlement refetches', async () => {
          mockGetEntitlement.mockReturnValue(new Promise(() => {}));

          findStartTrialModal().vm.$emit('start-trial');
          await waitForPromises();

          expect(findSkeletonLoader().exists()).toBe(false);
          expect(findSettings().exists()).toBe(true);
        });

        it('surfaces a mutation error', async () => {
          mockStartTrial.mockResolvedValue(
            startTrialErrorResponse([
              'This group is not eligible to start a Secrets Manager trial.',
            ]),
          );

          findStartTrialModal().vm.$emit('start-trial');
          await waitForPromises();

          expect(findError().text()).toBe(
            'This group is not eligible to start a Secrets Manager trial.',
          );
          expect(mockGetEntitlement).toHaveBeenCalledTimes(1);
        });

        it('shows the request error without the GraphQL prefix when the mutation fails', async () => {
          mockStartTrial.mockRejectedValue(new Error('GraphQL error: Something went wrong'));

          findStartTrialModal().vm.$emit('start-trial');
          await waitForPromises();

          expect(findError().text()).toBe('Something went wrong');
        });

        it('disables the enrollment toggle while the mutation is in flight', async () => {
          findStartTrialModal().vm.$emit('start-trial');
          await nextTick();

          expect(findSaasEnrollmentToggle().props('disabled')).toBe(true);

          await waitForPromises();

          expect(findSaasEnrollmentToggle().props('disabled')).toBe(false);
        });
      });
    });

    it('renders no entitlement banners on a subgroup or project', async () => {
      mockSecretManagerStatus.mockResolvedValue(activeResponse);
      mockGetEntitlement = jest
        .fn()
        .mockResolvedValue(
          entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
        );
      await createComponent({ isNamespaceEnrollable: false });

      expect(findBetaAlert().exists()).toBe(false);
      expect(findTrialAlert().exists()).toBe(false);
    });

    describe.each([
      { state: 'BLOCKED', blockedReason: 'ON_DEMAND_DISABLED' },
      { state: 'BLOCKED', blockedReason: 'TRIAL_EXPIRED' },
      { state: 'BLOCKED', blockedReason: 'CREDITS_EXHAUSTED' },
      { state: 'BLOCKED', blockedReason: 'GRACE' },
      { state: 'BLOCKED', blockedReason: 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED' },
    ])(
      'when entitlement state is $state with reason $blockedReason',
      ({ state, blockedReason }) => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue(inactiveResponse);
          mockGetEntitlement = jest
            .fn()
            .mockResolvedValue(entitlementResponse({ state, blockedReason }));
          await createComponent({
            isNamespaceEnrollable: true,
          });
        });

        it('disables the SaaS enrollment toggle', () => {
          expect(findSaasEnrollmentToggle().props('disabled')).toBe(true);
        });
      },
    );

    // Before a trial or paid add-on is selected the paid experience already
    // grants access, so there is nothing actionable here. The trial-eligible
    // state points the Owner at the secrets page (where the trial and add-on
    // CTAs live); ineligible renders nothing since a trial pointer would be
    // wrong there (the state includes fail-closed entitlement errors).
    describe.each(['TRIAL_ELIGIBLE', 'INELIGIBLE'])('when entitlement state is %s', (state) => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(inactiveResponse);
        mockGetEntitlement = jest.fn().mockResolvedValue(entitlementResponse({ state }));
        await createComponent({
          isNamespaceEnrollable: true,
        });
      });

      it('hides the whole settings section', () => {
        expect(findSettings().exists()).toBe(false);
        expect(findSaasEnrollmentToggle().exists()).toBe(false);
      });

      it(`${state === 'TRIAL_ELIGIBLE' ? 'shows' : 'does not show'} the secrets page guidance alert`, () => {
        expect(findTrialEligibleGuidance().exists()).toBe(state === 'TRIAL_ELIGIBLE');
      });

      it('shows the settings section and enrollment toggle when the secrets manager is already active', async () => {
        mockSecretManagerStatus.mockResolvedValue(activeResponse);
        await createComponent({
          isNamespaceEnrollable: true,
        });

        expect(findSettings().exists()).toBe(true);
        expect(findSaasEnrollmentToggle().exists()).toBe(true);
        expect(findTrialEligibleGuidance().exists()).toBe(false);
      });
    });

    describe('trial-eligible guidance alert', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(inactiveResponse);
        mockGetEntitlement = jest
          .fn()
          .mockResolvedValue(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }));
        await createComponent({
          isNamespaceEnrollable: true,
        });
      });

      it('links to the group secrets manager page', () => {
        expect(findTrialEligibleGuidance().text()).toBe(
          'To use GitLab Secrets Manager, start a trial or enable it with GitLab Credits.',
        );
        expect(findTrialEligibleGuidance().findComponent(GlLink).attributes('href')).toBe(
          `/groups/${fullPath}/-/secrets`,
        );
      });

      it('is not rendered for a non-enrollable (self-managed) group', async () => {
        await createComponent({
          isNamespaceEnrollable: false,
        });

        expect(findTrialEligibleGuidance().exists()).toBe(false);
      });

      it('is not rendered for a beta group, which gets the transition alert CTAs instead', async () => {
        mockGetEntitlement = jest
          .fn()
          .mockResolvedValue(
            entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
          );
        await createComponent({
          isNamespaceEnrollable: true,
        });

        expect(findTrialEligibleGuidance().exists()).toBe(false);
        expect(findBetaAlert().exists()).toBe(true);
      });
    });

    // An Owner who paid for the add-on and then opted out must keep the
    // enrollment toggle to opt back in, even with nothing provisioned --
    // hiding it here is the dead state from
    // https://gitlab.com/gitlab-org/gitlab/-/work_items/628207.
    describe('when a paid top-level group is unprovisioned and opted out', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(inactiveResponse);
        mockGetEnrollment = jest
          .fn()
          .mockResolvedValue(enrollmentStatusResponse({ enrolled: false }));
        await createComponent({
          isNamespaceEnrollable: true,
        });
      });

      it('keeps the settings section and enrollment toggle visible', () => {
        expect(findSettings().exists()).toBe(true);
        expect(findSaasEnrollmentToggle().exists()).toBe(true);
      });
    });

    describe.each([
      { state: 'TRIAL', onDemandEnabled: false },
      { state: 'PAID', onDemandEnabled: false },
      { state: 'OFFLINE_PAID', onDemandEnabled: false },
    ])('when entitlement state is $state with on-demand disabled', ({ state, onDemandEnabled }) => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(inactiveResponse);
        mockGetEntitlement = jest
          .fn()
          .mockResolvedValue(entitlementResponse({ state, onDemandEnabled }));
        await createComponent({
          isNamespaceEnrollable: true,
        });
      });

      it('keeps the SaaS enrollment toggle enabled', () => {
        expect(findSaasEnrollmentToggle().props('disabled')).toBe(false);
      });
    });
  });

  describe('SaaS enrollment toggle', () => {
    mockGetEnrollment = jest.fn();

    beforeEach(async () => {
      mockGetEnrollment.mockResolvedValueOnce(enrollmentStatusResponse({ enrolled: false }));
      await createComponent({ isNamespaceEnrollable: true });
    });

    it('refetches enrollment and secrets manager status when enrollment toggle is flipped', async () => {
      expect(mockGetEnrollment).toHaveBeenCalledTimes(1);
      expect(mockSecretManagerStatus).toHaveBeenCalledTimes(0); // skipped since namespace is unenrolled
      expect(findSaasEnrollmentToggle().props('isEnrolled')).toBe(false);

      mockGetEnrollment.mockResolvedValueOnce(enrollmentStatusResponse());
      findSaasEnrollmentToggle().vm.$emit('toggled');
      await waitForPromises();
      await nextTick();

      expect(mockGetEnrollment).toHaveBeenCalledTimes(2);
      expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      expect(findSaasEnrollmentToggle().props('isEnrolled')).toBe(true);
    });
  });

  describe('when rendered inside a settings block', () => {
    it('forwards hideInlineText to the enrollment toggle', async () => {
      await createComponent({ isNamespaceEnrollable: true, hideInlineText: true });

      expect(findSaasEnrollmentToggle().props('hideInlineText')).toBe(true);
    });

    describe('for a non-enrollable namespace', () => {
      beforeEach(() => {
        mockSecretManagerStatus.mockResolvedValue(activeResponse);
      });

      it('suppresses the inline title and description', async () => {
        await createComponent({
          isNamespaceEnrollable: false,
          hideInlineText: true,
        });

        expect(findNonTlgSettingsTitle().exists()).toBe(false);
        expect(findNonTlgSettingsDescription().exists()).toBe(false);
      });
    });
  });

  describe('when not rendered inside a settings block', () => {
    beforeEach(() => {
      mockSecretManagerStatus.mockResolvedValue(activeResponse);
    });

    it('keeps the inline title and description for a non-enrollable namespace', async () => {
      await createComponent({
        isNamespaceEnrollable: false,
      });

      expect(findNonTlgSettingsTitle().exists()).toBe(true);
      expect(findNonTlgSettingsDescription().exists()).toBe(true);
    });
  });

  describe('when secrets manager status query receives an error', () => {
    beforeEach(async () => {
      mockSecretManagerStatus.mockResolvedValue(secretsManagerStatusErrorResponse);
      await createComponent({ isNamespaceEnrollable: true });
    });

    it('shows error message', () => {
      expect(findError().text()).toBe('Some error occurred');
    });

    it('does not render permission settings', () => {
      expect(findPermissionsSettings().exists()).toBe(false);
    });

    // A failed status query leaves isActive false, which hides the settings
    // section for non-enrollable contexts. The error must not vanish with it,
    // or the failure is silent and polling has already stopped.
    describe('for a non-enrollable context', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(secretsManagerStatusErrorResponse);
        await createComponent({
          isNamespaceEnrollable: false,
        });
      });

      it('hides the settings but keeps the error visible', () => {
        expect(findSettings().exists()).toBe(false);
        expect(findShowSettingsError().text()).toBe('Some error occurred');
      });
    });
  });

  describe.each([
    {
      context: ENTITY_PROJECT,
      contextActiveResponse: activeResponse,
      contextProvisioningResponse: provisioningResponse,
      contextInactiveResponse: inactiveResponse,
      contextDeprovisioningResponse: deprovisioningResponse,
    },
    {
      context: ENTITY_GROUP,
      contextActiveResponse: groupActiveResponse,
      contextProvisioningResponse: groupProvisioningResponse,
      contextInactiveResponse: groupInactiveResponse,
      contextDeprovisioningResponse: groupDeprovisioningResponse,
    },
  ])(
    '$context context',
    ({
      context,
      contextActiveResponse,
      contextProvisioningResponse,
      contextInactiveResponse,
      contextDeprovisioningResponse,
    }) => {
      describe('when secrets manager status query receives ACTIVE status', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue(contextActiveResponse);
          await createComponent({ context });
        });

        it('renders permission settings', () => {
          expect(findPermissionsSettings().exists()).toBe(true);
        });

        describe('when namespace is enrolled', () => {
          beforeEach(async () => {
            await createComponent({ context, isNamespaceEnrollable: true });
          });

          it('renders permission settings', () => {
            expect(findPermissionsSettings().exists()).toBe(true);
          });

          it('hides permission settings when the namespace unenrolls', async () => {
            mockGetEnrollment.mockResolvedValue(enrollmentStatusResponse({ enrolled: false }));
            findSaasEnrollmentToggle().vm.$emit('toggled');
            await waitForPromises();
            await nextTick();

            expect(findPermissionsSettings().exists()).toBe(false);
          });
        });

        describe('when namespace is not enrolled', () => {
          beforeEach(async () => {
            mockGetEnrollment.mockResolvedValue(enrollmentStatusResponse({ enrolled: false }));
            await createComponent({ context, isNamespaceEnrollable: true });
          });

          it('does not render permission settings', () => {
            expect(findPermissionsSettings().exists()).toBe(false);
          });
        });
      });

      describe('when secrets manager status query receives INACTIVE status', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue(contextInactiveResponse);
          await createComponent({ context });
        });

        it('does not render permission settings', () => {
          expect(findPermissionsSettings().exists()).toBe(false);
        });

        it('stops polling for status', async () => {
          await pollNextStatus(contextInactiveResponse);

          expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
        });
      });

      describe('when secrets manager status query receives PROVISIONING status', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue(contextProvisioningResponse);
          await createComponent({ context });
        });

        it('does not render permission settings', () => {
          expect(findPermissionsSettings().exists()).toBe(false);
        });

        it('keeps polling while PROVISIONING and stops once the status is ACTIVE', async () => {
          await pollNextStatus(contextProvisioningResponse);
          await pollNextStatus(contextActiveResponse);
          await pollNextStatus(contextActiveResponse);

          expect(mockSecretManagerStatus).toHaveBeenCalledTimes(3);
          expect(findPermissionsSettings().exists()).toBe(true);
        });
      });

      describe('when secrets manager status query receives DEPROVISIONING status', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue(contextDeprovisioningResponse);
          await createComponent({ context });
        });

        it('does not render permission settings', () => {
          expect(findPermissionsSettings().exists()).toBe(false);
        });

        it('keeps polling while DEPROVISIONING and stops once the status is INACTIVE', async () => {
          await pollNextStatus(contextDeprovisioningResponse);
          await pollNextStatus(contextInactiveResponse);
          await pollNextStatus(contextInactiveResponse);

          expect(mockSecretManagerStatus).toHaveBeenCalledTimes(3);
        });
      });

      describe('when secrets manager status query receives NULL status', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue(contextInactiveResponse);
          await createComponent({ context });
        });

        it('does not render permission settings', () => {
          expect(findPermissionsSettings().exists()).toBe(false);
        });
      });

      describe('for top-level groups', () => {
        beforeEach(async () => {
          await createComponent({
            context,
            isNamespaceEnrollable: true,
          });
        });

        it('does not show non-tlg settings title', () => {
          expect(findNonTlgSettingsTitle().exists()).toBe(false);
          expect(findNonTlgSettingsDescription().exists()).toBe(false);
        });
      });

      describe('for subgroups and projects', () => {
        describe('when secrets manager is provisioned', () => {
          beforeEach(async () => {
            mockSecretManagerStatus.mockResolvedValue(contextActiveResponse);
            await createComponent({
              context,
              isNamespaceEnrollable: false,
            });
          });

          it('shows non-tlg settings title', () => {
            expect(findNonTlgSettingsTitle().exists()).toBe(true);
            expect(findNonTlgSettingsDescription().exists()).toBe(true);
          });
        });

        describe('when secrets manager is not provisioned', () => {
          beforeEach(() => {
            mockSecretManagerStatus.mockResolvedValue(contextInactiveResponse);
          });

          describe('when no trial or paid add-on is selected', () => {
            beforeEach(async () => {
              mockGetEntitlement = jest
                .fn()
                .mockResolvedValue(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }));
              await createComponent({
                context,
                isNamespaceEnrollable: false,
              });
            });

            it('hide secrets manager settings', () => {
              expect(findSettings().exists()).toBe(false);
            });
          });

          // There is nothing to act on: the enrollment toggle only renders for
          // enrollable (SaaS top-level group) namespaces.
          describe('when a trial or paid add-on is selected', () => {
            beforeEach(async () => {
              await createComponent({
                context,
                isNamespaceEnrollable: false,
              });
            });

            it('hides secrets manager settings', () => {
              expect(findSettings().exists()).toBe(false);
            });
          });
        });
      });
    },
  );

  describe('when OpenBao is unhealthy', () => {
    beforeEach(async () => {
      mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(false));
      mockSecretManagerStatus.mockResolvedValue(activeResponse);
      await createComponent();
    });

    it('shows the unhealthy alert', () => {
      expect(findOpenbaoUnhealthyAlert().exists()).toBe(true);
      expect(findOpenbaoUnhealthyAlert().findComponent(GlAlert).props('variant')).toBe('danger');
    });

    it('hides permissions settings even when active', () => {
      expect(findPermissionsSettings().exists()).toBe(false);
    });
  });

  describe('when OpenBao health query fails', () => {
    beforeEach(async () => {
      mockOpenbaoHealth.mockRejectedValue(new Error('Network error'));
      mockSecretManagerStatus.mockResolvedValue(activeResponse);
      await createComponent();
    });

    it('shows the unhealthy alert', () => {
      expect(findOpenbaoUnhealthyAlert().exists()).toBe(true);
    });
  });

  describe('when OpenBao is healthy', () => {
    beforeEach(async () => {
      mockSecretManagerStatus.mockResolvedValue(activeResponse);
      await createComponent();
    });

    it('does not show the unhealthy alert', () => {
      expect(findOpenbaoUnhealthyAlert().exists()).toBe(false);
    });

    it('renders permission settings', () => {
      expect(findPermissionsSettings().exists()).toBe(true);
    });
  });
});
