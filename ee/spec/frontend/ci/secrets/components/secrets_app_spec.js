import { GlSprintf, GlTableLite } from '@gitlab/ui';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import Vue, { nextTick } from 'vue';
import { createAlert, VARIANT_SUCCESS } from '~/alert';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import createRouter from 'ee/ci/secrets/router';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SecretsApp from 'ee/ci/secrets/components/secrets_app.vue';
import SecretsBetaTransitionAlert from 'ee/ci/secrets/components/secrets_beta_transition_alert.vue';
import SecretsManagerTrialAlert from 'ee/ci/secrets/components/secrets_manager_trial_alert.vue';
import SecretsEmptyState from 'ee/ci/secrets/components/secrets_empty_state.vue';
import SecretsTrialEmptyState from 'ee/ci/secrets/components/secrets_table/secrets_trial_empty_state.vue';
import SecretActionsCell from 'ee/ci/secrets/components/secrets_table/secret_actions_cell.vue';
import { SECRETS_MANAGER_CONTEXT_CONFIG } from 'ee/ci/secrets/context_config';
import enrollNamespaceMutation from 'ee/ci/secrets/graphql/mutations/enroll_namespace_secrets_manager.mutation.graphql';
import getOpenbaoHealthQuery from 'ee/ci/secrets/graphql/queries/get_openbao_health.query.graphql';
import getEntitlementQuery from 'ee/ci/secrets/graphql/queries/get_secrets_manager_entitlement.graphql';
import startTrialMutation from 'ee/ci/secrets/graphql/mutations/start_secrets_manager_trial.mutation.graphql';
import enableAddOnMutation from 'ee/ci/secrets/graphql/mutations/enable_secrets_manager_add_on.mutation.graphql';
import refreshEntitlementMutation from 'ee/ci/secrets/graphql/mutations/refresh_secrets_manager_entitlement.mutation.graphql';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';
import {
  BLOCKED_REASON_TRIAL_EXPIRED,
  POLL_INTERVAL,
  ENTITY_GROUP,
  ENTITY_PROJECT,
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_PROVISIONING,
} from 'ee/ci/secrets/constants';
import {
  enableSecretManagerResponse,
  enrollNamespaceAlreadyEnrolledResponse,
  enrollNamespaceErrorResponse,
  enrollNamespaceSuccessResponse,
  entitlementResponse,
  mockGroupSecretsResponse,
  mockProjectSecretsResponse,
  openbaoHealthResponse,
  secretManagerStatusResponse,
  startTrialSuccessResponse,
  startTrialErrorResponse,
  enableAddOnSuccessResponse,
  enableAddOnErrorResponse,
  refreshEntitlementResponse,
} from '../mock_data';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

describe('SecretsApp', () => {
  let wrapper;
  let apolloProvider;
  let mockSecretManagerStatus;
  let mockOpenbaoHealth;
  let mockEntitlementQuery;
  let mockEnableSecretsManager;
  let mockEnrollNamespace;
  let mockStartTrial;
  let mockEnableAddOn;
  let mockRefreshEntitlement;

  Vue.use(VueRouter);
  Vue.use(VueApollo);
  const mockToastShow = jest.fn();

  const findRouterView = () => wrapper.findComponent({ ref: 'router-view' });

  const managePermissionsPath = '/path/to/edit#js-shared-permissions';

  const defaultProvide = {
    canProvision: true,
    canStartTrial: false,
    fullPath: '/path/to/entity',
    managePermissionsPath,
    subscriptionsUrl: 'https://customers.example.com',
    topLevelGroupFullPath: '',
    isSaas: false,
  };

  const createRouterForTest = () => createRouter('/-/secrets');

  const createComponent = async ({
    stubs,
    router,
    provide,
    isLoading = false,
    context = ENTITY_PROJECT,
    secretsListResponse = { data: { secretsList: { edges: [] } } },
  } = {}) => {
    const contextConfig = SECRETS_MANAGER_CONTEXT_CONFIG[context];
    const handlers = [
      [contextConfig.getStatus.query, mockSecretManagerStatus],
      [getOpenbaoHealthQuery, mockOpenbaoHealth],
      [getEntitlementQuery, mockEntitlementQuery],
      [contextConfig.enableSecretsManager.mutation, mockEnableSecretsManager],
      [enrollNamespaceMutation, mockEnrollNamespace],
      [startTrialMutation, mockStartTrial],
      [enableAddOnMutation, mockEnableAddOn],
      [refreshEntitlementMutation, mockRefreshEntitlement],
      [contextConfig.getSecrets.query, jest.fn().mockResolvedValue(secretsListResponse)],
      [
        contextConfig.getSecretsNeedingRotation.query,
        jest.fn().mockResolvedValue({ data: { secretsNeedingRotation: { nodes: [] } } }),
      ],
    ];

    apolloProvider = createMockApollo(handlers);

    wrapper = mountExtended(SecretsApp, {
      router: router || createRouterForTest(),
      provide: {
        contextConfig,
        ...defaultProvide,
        ...provide,
      },
      stubs,
      apolloProvider,
      mocks: {
        $toast: { show: mockToastShow },
      },
    });

    if (!isLoading) {
      await waitForPromises();
      await nextTick();
    }
  };

  const createPaidExperienceComponent = async (provide = {}, options = {}) => {
    await createComponent({
      ...options,
      provide: {
        isSaas: true,
        topLevelGroupFullPath: 'top-level-group',
        ...provide,
      },
      stubs: {
        GlSprintf,
      },
    });
  };

  const findEmptyState = () => wrapper.findComponent(SecretsEmptyState);
  const findSecretActionsCell = () => wrapper.findComponent(SecretActionsCell);
  const findNewSecretButton = () => wrapper.findComponentByTestId('new-secret-button');
  const findTrialEmptyState = () => wrapper.findComponent(SecretsTrialEmptyState);
  const findEmptyStateNewSecretBtn = () =>
    wrapper.findComponentByTestId('empty-state-new-secret-button');
  const findLoadingIcon = () => wrapper.findByTestId('secrets-manager-loading-status');
  const findTrialAlert = () => wrapper.findComponent(SecretsManagerTrialAlert);
  const findBetaTransitionAlert = () => wrapper.findComponent(SecretsBetaTransitionAlert);
  const findEnableAddOnModal = () => wrapper.findComponent(EnableAddOnModal);
  const findStartTrialModal = () => wrapper.findComponent(StartTrialModal);
  // Both trial CTAs open the confirmation modal; the chain starts on its primary action.
  const confirmStartTrial = async () => {
    findStartTrialModal().vm.$emit('start-trial');
    await waitForPromises();
    await nextTick();
  };

  const advanceToNextFetch = (milliseconds) => {
    jest.advanceTimersByTime(milliseconds);
  };

  const pollNextStatus = async (status, context = 'project') => {
    mockSecretManagerStatus.mockResolvedValue(secretManagerStatusResponse(status, context));
    advanceToNextFetch(POLL_INTERVAL);

    await waitForPromises();
    await nextTick();
  };

  beforeEach(() => {
    mockSecretManagerStatus = jest.fn();
    mockOpenbaoHealth = jest.fn();
    mockEntitlementQuery = jest.fn().mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));
    mockEnableSecretsManager = jest.fn();
    mockEnrollNamespace = jest.fn().mockResolvedValue(enrollNamespaceSuccessResponse());
    mockStartTrial = jest.fn().mockResolvedValue(startTrialSuccessResponse());
    mockEnableAddOn = jest.fn().mockResolvedValue(enableAddOnSuccessResponse());
    mockRefreshEntitlement = jest.fn().mockResolvedValue(refreshEntitlementResponse());

    mockSecretManagerStatus.mockResolvedValue(
      secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE),
    );
    mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(true));
  });

  describe.each`
    context
    ${ENTITY_PROJECT}
    ${ENTITY_GROUP}
  `('SecretsApp in $context context', ({ context }) => {
    beforeEach(() => {
      mockSecretManagerStatus.mockClear();
      mockSecretManagerStatus.mockResolvedValue(
        secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context),
      );
    });

    describe('skipping secrets manager status query', () => {
      it('skips status query while entitlement is loading', async () => {
        mockEntitlementQuery.mockReturnValue(new Promise(() => {}));
        await createComponent({
          provide: {
            topLevelGroupFullPath: 'top-level-group',
          },
          isLoading: true,
        });

        expect(mockSecretManagerStatus).not.toHaveBeenCalled();
        expect(findLoadingIcon().exists()).toBe(true);
      });

      it('skips status query when trial eligible', async () => {
        mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }));
        await createComponent({
          provide: {
            topLevelGroupFullPath: 'top-level-group',
          },
          stubs: { GlSprintf },
        });

        expect(mockSecretManagerStatus).not.toHaveBeenCalled();
        expect(findLoadingIcon().exists()).toBe(false);
      });

      it('runs status query after entitlement resolves as non-trial-eligible', async () => {
        mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));
        await createComponent({
          provide: {
            topLevelGroupFullPath: 'top-level-group',
          },
        });

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
        expect(findLoadingIcon().exists()).toBe(false);
        expect(findRouterView().exists()).toBe(true);
      });

      it('does not show loading icon when status query returns null', async () => {
        mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
        await createComponent({
          provide: {
            topLevelGroupFullPath: 'top-level-group',
          },
        });

        expect(findLoadingIcon().exists()).toBe(false);
        expect(findRouterView().exists()).toBe(true);
      });
    });

    describe('when secrets manager status is being fetched', () => {
      beforeEach(() => {
        createComponent({ isLoading: true, context });
      });

      it('renders the loading state', () => {
        expect(findLoadingIcon().exists()).toBe(true);
      });

      it('does not render the router view', () => {
        expect(findRouterView().exists()).toBe(false);
      });
    });

    describe('when secrets manager is being provisioned', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, context),
        );
        await createComponent({ context });
      });

      // empty state owns the provisioning UI
      it('renders the router view', () => {
        expect(findRouterView().exists()).toBe(true);
      });

      it('does not render the loading state', () => {
        expect(findLoadingIcon().exists()).toBe(false);
      });

      it('polls for updated status while provisioning', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        await pollNextStatus(SECRET_MANAGER_STATUS_PROVISIONING, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);
      });

      it('stops polling when provisioned', async () => {
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);

        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);
      });
    });

    // e.g. provisioning was started in another tab and the user
    // opened/refreshed this page mid-provisioning.
    describe('when the page loads while provisioning is already in-progress', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, context),
        );
        await createComponent({ context, router: createRouterForTest(context) });
      });

      it('shows the loading button in the empty state', () => {
        expect(findEmptyStateNewSecretBtn().props('loading')).toBe(true);
      });

      it('fires the success flow when status flips to ACTIVE', async () => {
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(createAlert).toHaveBeenCalled();
      });
    });

    describe('when secrets manager has been provisioned', () => {
      beforeEach(async () => {
        await createComponent({ context });
      });

      it('renders the router view', () => {
        expect(findRouterView().exists()).toBe(true);
      });

      it('stops polling for status', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      });
    });

    describe('when secrets manager is not provisioned', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
        await createComponent({ context });
      });

      it('stops polling', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        await pollNextStatus(null, context);

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      });
    });

    describe('when there is an error with fetching the secrets manager status', () => {
      const error = new Error('GraphQL error: API error');

      beforeEach(async () => {
        mockSecretManagerStatus.mockRejectedValue(error);
        await createComponent({ context });
      });

      it('renders an error message', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'API error',
          captureError: true,
          error,
        });
      });

      it('stops polling', async () => {
        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);

        advanceToNextFetch(POLL_INTERVAL);

        await waitForPromises();
        await nextTick();

        expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
      });

      it('does not render the loading state or router view', () => {
        expect(findLoadingIcon().exists()).toBe(false);
        expect(findRouterView().exists()).toBe(false);
      });
    });

    describe('when entity is not archived or marked for deletion', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: false, markedForDeletion: false },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      });

      it('shows action buttons', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(true);
      });
    });

    describe('when entity is archived', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: true, markedForDeletion: false },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      });

      it('sets secrets manager to read-only mode by hiding action buttons', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(false);
      });
    });

    describe('when entity is marked for deletion', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: false, markedForDeletion: true },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      });

      it('sets secrets manager to read-only mode by hiding action buttons', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(false);
      });
    });

    describe('when entity is archived and OpenBao grants every action', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, {
            entity: { archived: true, markedForDeletion: false },
          }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
          secretsListResponse:
            context === ENTITY_GROUP ? mockGroupSecretsResponse() : mockProjectSecretsResponse(),
        });
      });

      it('hides all actions, including delete', () => {
        expect(findNewSecretButton().exists()).toBe(false);
        expect(findSecretActionsCell().exists()).toBe(false);
      });
    });

    describe('createSecrets OpenBao permission', () => {
      const createComponentWithPermission = async (userPermissions) => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, { userPermissions }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
        });
      };

      describe('when OpenBao grants create', () => {
        beforeEach(async () => {
          await createComponentWithPermission({ createSecrets: true });
        });

        it('shows the New secret button', () => {
          expect(findEmptyStateNewSecretBtn().exists()).toBe(true);
        });
      });

      describe('when OpenBao denies create', () => {
        beforeEach(async () => {
          await createComponentWithPermission({ createSecrets: false });
        });

        it('hides the New secret button', () => {
          expect(findEmptyStateNewSecretBtn().exists()).toBe(false);
        });
      });

      describe('when the response has no userPermissions', () => {
        beforeEach(async () => {
          await createComponentWithPermission(null);
        });

        it('fails closed and hides the New secret button', () => {
          expect(findEmptyStateNewSecretBtn().exists()).toBe(false);
        });
      });
    });

    describe('OpenBao permissions on the secrets table', () => {
      const createComponentWithPermission = async (userPermissions) => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, context, { userPermissions }),
        );

        await createComponent({
          context,
          router: createRouterForTest(context),
          secretsListResponse:
            context === ENTITY_GROUP ? mockGroupSecretsResponse() : mockProjectSecretsResponse(),
        });
      };

      describe('when OpenBao grants read only', () => {
        beforeEach(async () => {
          await createComponentWithPermission({
            createSecrets: false,
            updateSecrets: false,
            deleteSecrets: false,
          });
        });

        it('hides all actions', () => {
          expect(findNewSecretButton().exists()).toBe(false);
          expect(findSecretActionsCell().exists()).toBe(false);
        });
      });

      describe('when OpenBao grants create and update but not delete', () => {
        beforeEach(async () => {
          await createComponentWithPermission({ deleteSecrets: false });
        });

        it('shows create and edit, and hides delete', () => {
          expect(findNewSecretButton().exists()).toBe(true);
          expect(findSecretActionsCell().props()).toMatchObject({
            canDelete: false,
            canUpdate: true,
          });
        });
      });

      describe('when the response has no userPermissions', () => {
        beforeEach(async () => {
          await createComponentWithPermission(null);
        });

        it('fails closed and hides all actions', () => {
          expect(findNewSecretButton().exists()).toBe(false);
          expect(findSecretActionsCell().exists()).toBe(false);
        });
      });
    });

    describe('when the user has no OpenBao read grant', () => {
      const findNoReadAccessAlert = () => wrapper.findByTestId('no-read-access-alert');

      const createComponentWithoutReadGrant = async ({
        status = SECRET_MANAGER_STATUS_ACTIVE,
        isLoading = false,
      } = {}) => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(status, context, {
            userPermissions: { readMetadata: false },
          }),
        );

        await createComponent({
          context,
          isLoading,
          router: createRouterForTest(context),
          secretsListResponse:
            context === ENTITY_GROUP ? mockGroupSecretsResponse() : mockProjectSecretsResponse(),
        });
      };

      describe('when the secrets manager is active and OpenBao is healthy', () => {
        beforeEach(async () => {
          await createComponentWithoutReadGrant();
        });

        it('shows the empty state with the no read access alert', () => {
          expect(findEmptyState().exists()).toBe(true);
          expect(findNoReadAccessAlert().exists()).toBe(true);
          expect(wrapper.findComponent(GlTableLite).exists()).toBe(false);
          expect(createAlert).not.toHaveBeenCalled();
        });
      });

      describe('when the secrets manager is provisioning', () => {
        beforeEach(async () => {
          await createComponentWithoutReadGrant({ status: SECRET_MANAGER_STATUS_PROVISIONING });
        });

        it('does not show the alert', () => {
          expect(findNoReadAccessAlert().exists()).toBe(false);
        });
      });

      describe('when the OpenBao health check is loading', () => {
        beforeEach(async () => {
          mockOpenbaoHealth.mockReturnValue(new Promise(() => {}));
          await createComponentWithoutReadGrant();
        });

        it('does not show the alert', () => {
          expect(findNoReadAccessAlert().exists()).toBe(false);
        });
      });

      describe('when OpenBao is unhealthy', () => {
        beforeEach(async () => {
          mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(false));
          await createComponentWithoutReadGrant();
        });

        it('does not show the alert', () => {
          expect(findNoReadAccessAlert().exists()).toBe(false);
        });
      });
    });
  });

  describe('toast message', () => {
    beforeEach(async () => {
      await createComponent({
        router: createRouterForTest(ENTITY_PROJECT),
      });
    });

    it('renders toast message when show-secrets-toast is emitted', async () => {
      findRouterView().vm.$emit('show-secrets-toast', 'This is a toast message.');
      await nextTick();

      expect(mockToastShow).toHaveBeenCalledWith('This is a toast message.');
    });
  });

  describe('when OpenBao is unhealthy', () => {
    beforeEach(async () => {
      mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(false));
      await createComponent({
        router: createRouterForTest(ENTITY_PROJECT),
      });
    });

    it('shows an alert with unhealthy message', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Cannot connect to OpenBao',
        message:
          'Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
      });
    });

    it('renders the router view', () => {
      expect(findRouterView().exists()).toBe(true);
    });

    it('redirects to index route when on a different route', async () => {
      const router = createRouterForTest(ENTITY_PROJECT);
      await router.push({ name: 'new' }).catch(() => {});

      mockOpenbaoHealth.mockResolvedValue(openbaoHealthResponse(false));
      await createComponent({ router });

      expect(router.currentRoute.name).toBe('index');
    });
  });

  describe('when OpenBao health query fails', () => {
    beforeEach(async () => {
      mockOpenbaoHealth.mockRejectedValue(new Error('Network error'));
      await createComponent({
        router: createRouter('/-/secrets'),
      });
    });

    it('shows an alert with unhealthy message', () => {
      expect(createAlert).toHaveBeenCalledWith({
        title: 'Cannot connect to OpenBao',
        message:
          'Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
      });
    });

    it('renders the router view', () => {
      expect(findRouterView().exists()).toBe(true);
    });
  });

  describe('entitlement query', () => {
    it('calls the entitlement query with the correct variables', async () => {
      await createPaidExperienceComponent();

      expect(mockEntitlementQuery).toHaveBeenCalledWith({ fullPath: 'top-level-group' });
    });

    it('renders an error when entitlement query fails', async () => {
      const error = new Error('GraphQL error: Entitlement error');
      mockEntitlementQuery.mockRejectedValue(error);
      await createPaidExperienceComponent();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Entitlement error',
        captureError: true,
        error,
      });
    });

    it('skips the entitlement query when topLevelGroupFullPath is empty', async () => {
      await createPaidExperienceComponent({ topLevelGroupFullPath: '' });

      expect(mockEntitlementQuery).not.toHaveBeenCalled();
    });

    it('shows loading state when entitlement query is skipped but status is still loading', async () => {
      mockSecretManagerStatus.mockReturnValue(new Promise(() => {}));
      await createPaidExperienceComponent({ topLevelGroupFullPath: '' });

      expect(findLoadingIcon().exists()).toBe(true);
      expect(findRouterView().exists()).toBe(false);
    });

    describe('when the secrets manager reports a write denial reason', () => {
      beforeEach(async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, 'project', {
            writeDenialReason: 'TRIAL_EXPIRED',
            userPermissions: { createSecrets: false, updateSecrets: false },
          }),
        );
        await createComponent({
          provide: {
            topLevelGroupFullPath: 'top-level-group',
          },
          secretsListResponse: mockProjectSecretsResponse(),
        });
      });

      it('allows only deletes', () => {
        expect(findNewSecretButton().exists()).toBe(false);
        expect(findSecretActionsCell().props()).toMatchObject({
          canUpdate: false,
          canDelete: true,
        });
      });
    });

    describe('when the user cannot read the entitlement', () => {
      beforeEach(() => {
        mockEntitlementQuery.mockResolvedValue({
          data: {
            group: {
              id: 'gid://gitlab/Group/96',
              secretsManagerEntitlement: null,
              __typename: 'Group',
            },
          },
        });
      });

      it('is writable when there is no write denial reason', async () => {
        await createPaidExperienceComponent(
          {},
          { secretsListResponse: mockProjectSecretsResponse() },
        );

        expect(findNewSecretButton().exists()).toBe(true);
        expect(findTrialAlert().exists()).toBe(false);
      });

      describe.each(['CREDITS_EXHAUSTED', 'TRIAL_REQUIRED'])(
        'when the secrets manager reports the %s write denial reason',
        (writeDenialReason) => {
          beforeEach(async () => {
            mockSecretManagerStatus.mockResolvedValue(
              secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, 'project', {
                writeDenialReason,
                userPermissions: { createSecrets: false, updateSecrets: false },
              }),
            );
            await createPaidExperienceComponent(
              {},
              { secretsListResponse: mockProjectSecretsResponse() },
            );
          });

          it('allows only deletes', () => {
            expect(findNewSecretButton().exists()).toBe(false);
            expect(findSecretActionsCell().props()).toMatchObject({
              canUpdate: false,
              canDelete: true,
            });
          });

          it('passes the reason to the trial alert', () => {
            expect(findTrialAlert().props()).toMatchObject({
              entitlement: null,
              writeDenialReason,
            });
          });
        },
      );
    });
  });

  describe('trial alert', () => {
    it('receives the resolved entitlement', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'BLOCKED', blockedReason: BLOCKED_REASON_TRIAL_EXPIRED }),
      );
      await createPaidExperienceComponent();

      expect(findTrialAlert().props('entitlement')).toMatchObject({
        state: 'BLOCKED',
        blockedReason: BLOCKED_REASON_TRIAL_EXPIRED,
      });
    });
  });

  // `isBetaUser` is derived from the entitlement's `betaWindowEligible`, which
  // the backend resolves per realm (namespace enrollment `beta` on SaaS,
  // instance enrollment + provisioned secrets manager on self-managed).
  describe('beta transition alert', () => {
    it('passes correct props for a beta namespace', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
      );

      await createPaidExperienceComponent();

      const alert = findBetaTransitionAlert();
      expect(alert.props('isBeta')).toBe(true);
      expect(alert.props('isTrialEligible')).toBe(true);
      expect(alert.props('betaProgramEnded')).toBe(false);
    });

    it('passes betaProgramEnded=true when the entitlement reports the beta cutoff', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({
          state: 'TRIAL_ELIGIBLE',
          betaWindowEligible: true,
          betaProgramEnded: true,
        }),
      );

      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('betaProgramEnded')).toBe(true);
    });

    it.each`
      canStartTrial | fullPath                 | showCta
      ${true}       | ${'top-level-group'}     | ${true}
      ${true}       | ${'top-level-group/sub'} | ${false}
      ${false}      | ${'top-level-group'}     | ${false}
    `(
      'passes showCta=$showCta when canStartTrial=$canStartTrial on $fullPath',
      async ({ canStartTrial, fullPath, showCta }) => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
        );

        await createPaidExperienceComponent({ canStartTrial, fullPath });

        expect(findBetaTransitionAlert().props('showCta')).toBe(showCta);
      },
    );

    describe('on self-managed', () => {
      it('does not render while the beta program is still running', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
        );

        await createPaidExperienceComponent({ isSaas: false });

        expect(findBetaTransitionAlert().exists()).toBe(false);
      });

      it('renders once the beta program has ended', async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL_ELIGIBLE',
            betaWindowEligible: true,
            betaProgramEnded: true,
          }),
        );

        await createPaidExperienceComponent({ isSaas: false });

        expect(findBetaTransitionAlert().props('betaProgramEnded')).toBe(true);
      });
    });

    it('passes isBeta=false when the entitlement is not beta-window eligible', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: false }),
      );

      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('isBeta')).toBe(false);
    });

    it('passes isBeta=false when the entitlement omits betaWindowEligible', async () => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: null }),
      );

      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('isBeta')).toBe(false);
    });
  });

  describe('beta cohort', () => {
    beforeEach(() => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({ state: 'TRIAL_ELIGIBLE', betaWindowEligible: true }),
      );
    });

    it('runs the secrets manager status query (beta users read their secrets)', async () => {
      await createPaidExperienceComponent();

      expect(mockSecretManagerStatus).toHaveBeenCalledTimes(1);
    });

    it('provides the beta transition alert with isBeta=true', async () => {
      await createPaidExperienceComponent();

      expect(findBetaTransitionAlert().props('isBeta')).toBe(true);
    });

    // isBetaReadOnly is exposed via provide()/inject, not a prop on the
    // routed component, so assert the computed directly.
    it('stays writable while the beta program has not ended', async () => {
      await createPaidExperienceComponent();

      expect(wrapper.vm.isBetaReadOnly).toBe(false);
      expect(wrapper.vm.isReadOnly).toBe(false);
    });

    describe('when the beta program has ended', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL_ELIGIBLE',
            betaWindowEligible: true,
            betaProgramEnded: true,
          }),
        );
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, 'project', {
            writeDenialReason: 'TRIAL_REQUIRED',
          }),
        );
        await createPaidExperienceComponent();
      });

      it('drops to read-only', () => {
        expect(wrapper.vm.isBetaReadOnly).toBe(true);
        expect(wrapper.vm.isReadOnly).toBe(true);
      });
    });

    // A provisioned beta group answers ACTIVE from the outset and never
    // changes status, so the chain cannot rely on a status transition.
    describe('when the alert CTA starts the trial on a provisioned beta group', () => {
      const findSecretsTable = () => wrapper.findComponent(GlTableLite);

      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL_ELIGIBLE',
            betaWindowEligible: true,
            betaProgramEnded: true,
          }),
        );
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({
            context: ENTITY_GROUP,
            errors: ['Secrets manager already initialized for the group.'],
          }),
        );
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP),
        );

        await createPaidExperienceComponent(
          { fullPath: 'top-level-group' },
          {
            context: ENTITY_GROUP,
            router: createRouterForTest(ENTITY_GROUP),
            secretsListResponse: mockGroupSecretsResponse(),
          },
        );

        findBetaTransitionAlert().vm.$emit('start-trial');
        await nextTick();
      });

      it('opens the confirmation modal without starting the chain', () => {
        expect(findStartTrialModal().props('visible')).toBe(true);
        expect(mockEnrollNamespace).not.toHaveBeenCalled();
      });

      it('runs the trial chain against the top-level group once confirmed', async () => {
        await confirmStartTrial();

        expect(findStartTrialModal().props('visible')).toBe(false);
        expect(mockStartTrial).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('keeps the secrets table visible instead of the trial empty state', async () => {
        await confirmStartTrial();

        expect(findSecretsTable().exists()).toBe(true);
        expect(findTrialEmptyState().exists()).toBe(false);
      });

      it('finalizes without a status change: clears loading, refetches the entitlement, shows the alert', async () => {
        await confirmStartTrial();

        expect(findBetaTransitionAlert().props('isTrialOnboarding')).toBe(false);
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith({
          message:
            'The GitLab Secrets Manager trial has been enabled for all groups and projects within this namespace. %{linkStart}Manage group permissions.%{linkEnd}',
          messageLinks: { link: managePermissionsPath },
          variant: VARIANT_SUCCESS,
        });
      });
    });

    describe('when the alert CTA starts the trial on an unprovisioned beta group', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({
            state: 'TRIAL_ELIGIBLE',
            betaWindowEligible: true,
            betaProgramEnded: true,
          }),
        );
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({ context: ENTITY_GROUP }),
        );
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });

        await createPaidExperienceComponent(
          { fullPath: 'top-level-group' },
          { context: ENTITY_GROUP, router: createRouterForTest(ENTITY_GROUP) },
        );

        // Provisioning mutation flips the backend to PROVISIONING; the chain's
        // status refetch picks that up and polling takes over.
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
        );
        findBetaTransitionAlert().vm.$emit('start-trial');
        await nextTick();
        await confirmStartTrial();
      });

      it('keeps the standard empty state and the CTA loading while provisioning polls', () => {
        expect(findTrialEmptyState().exists()).toBe(false);
        expect(findEmptyState().exists()).toBe(true);
        expect(findBetaTransitionAlert().props('isTrialOnboarding')).toBe(true);
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('finalizes once polling reaches ACTIVE', async () => {
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(findBetaTransitionAlert().props('isTrialOnboarding')).toBe(false);
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
        expect(createAlert).toHaveBeenCalledTimes(1);
      });
    });

    // A beta group that converted to the trial and got blocked follows normal
    // entitlement even while the beta program runs -- the backend only sets
    // betaWindowEligible for never-converted groups (trial_eligible / ineligible).
    describe('when a converted beta group is blocked during the beta program', () => {
      beforeEach(async () => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'BLOCKED', blockedReason: 'TRIAL_EXPIRED' }),
        );
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_ACTIVE, 'project', {
            writeDenialReason: 'TRIAL_EXPIRED',
          }),
        );
        await createPaidExperienceComponent();
      });

      it('drops to read-only like any blocked entitlement', () => {
        expect(wrapper.vm.isReadOnly).toBe(true);
      });
    });
  });

  describe('enable add-on', () => {
    const enableSuccessAlert = {
      message:
        'The GitLab Secrets Manager has been enabled for all groups and projects in this namespace. %{linkStart}Manage group permissions.%{linkEnd}',
      messageLinks: { link: managePermissionsPath },
      variant: VARIANT_SUCCESS,
    };

    const setUpBetaEligible = async ({ onDemandEnabled = true, betaProgramEnded = false } = {}) => {
      mockEntitlementQuery.mockResolvedValue(
        entitlementResponse({
          state: 'TRIAL_ELIGIBLE',
          onDemandEnabled,
          betaWindowEligible: true,
          betaProgramEnded,
        }),
      );
      await createPaidExperienceComponent();
    };

    const openModal = async () => {
      findBetaTransitionAlert().vm.$emit('enable-add-on');
      await nextTick();
    };

    const emitEnable = async () => {
      findEnableAddOnModal().vm.$emit('enable');
      await waitForPromises();
      await nextTick();
    };

    it('opens the modal when the alert emits `enable-add-on`', async () => {
      await setUpBetaEligible();
      expect(findEnableAddOnModal().props('visible')).toBe(false);

      await openModal();

      expect(findEnableAddOnModal().props('visible')).toBe(true);
    });

    it('passes onDemandEnabled from the entitlement to the modal', async () => {
      await setUpBetaEligible({ onDemandEnabled: false });

      expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
    });

    it('opens without re-checking the entitlement when on-demand billing is accepted', async () => {
      await setUpBetaEligible();
      await openModal();

      expect(mockRefreshEntitlement).not.toHaveBeenCalled();
      expect(findEnableAddOnModal().props('visible')).toBe(true);
    });

    describe('when the cached entitlement says on-demand billing is not accepted', () => {
      beforeEach(async () => {
        mockRefreshEntitlement.mockResolvedValue(
          refreshEntitlementResponse({ entitlement: { betaWindowEligible: true } }),
        );
        await setUpBetaEligible({ onDemandEnabled: false });
      });

      it('re-checks the entitlement for the top-level group, showing progress, before opening the modal', async () => {
        await openModal();

        expect(mockRefreshEntitlement).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
        expect(findBetaTransitionAlert().props('isCheckingEntitlement')).toBe(true);
        expect(findEnableAddOnModal().props('visible')).toBe(false);

        await waitForPromises();

        expect(findBetaTransitionAlert().props('isCheckingEntitlement')).toBe(false);
        expect(findEnableAddOnModal().props('visible')).toBe(true);
      });

      it('opens the modal with the consent given since the page loaded', async () => {
        await openModal();
        await waitForPromises();

        expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(true);
        expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(false);
      });

      it('clears the failed-check alert when a later check succeeds', async () => {
        mockRefreshEntitlement.mockRejectedValueOnce(new Error('unreachable'));
        await openModal();
        await waitForPromises();
        findEnableAddOnModal().vm.$emit('hide');
        await nextTick();

        await openModal();
        await waitForPromises();

        expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(false);
      });

      it('checks once when the enable action fires again while the check runs', async () => {
        findBetaTransitionAlert().vm.$emit('enable-add-on');
        findBetaTransitionAlert().vm.$emit('enable-add-on');
        await waitForPromises();

        expect(mockRefreshEntitlement).toHaveBeenCalledTimes(1);
      });

      it('keeps the beta alert after the re-check', async () => {
        await openModal();
        await waitForPromises();

        expect(findBetaTransitionAlert().props('isBeta')).toBe(true);
        expect(wrapper.findByTestId('secrets-beta-transition-alert').exists()).toBe(true);
      });

      it('keeps the ended-beta state after the re-check', async () => {
        mockRefreshEntitlement.mockResolvedValue(
          refreshEntitlementResponse({
            entitlement: { betaWindowEligible: true, betaProgramEnded: true },
          }),
        );
        await setUpBetaEligible({ onDemandEnabled: false, betaProgramEnded: true });

        await openModal();
        await waitForPromises();

        expect(findBetaTransitionAlert().props('betaProgramEnded')).toBe(true);
        expect(wrapper.findByTestId('secrets-beta-transition-alert').exists()).toBe(true);
      });

      it('keeps the cached entitlement when the re-check returns no entitlement', async () => {
        mockRefreshEntitlement.mockResolvedValue(
          refreshEntitlementResponse({
            entitlement: null,
            errors: ['Unable to reach the subscription service. Please try again later.'],
          }),
        );

        await openModal();
        await waitForPromises();

        expect(findEnableAddOnModal().props('visible')).toBe(true);
        expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
        expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(true);
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('keeps the cached entitlement and reports the error when the re-check fails', async () => {
        const error = new Error('rate limited');
        mockRefreshEntitlement.mockRejectedValue(error);

        await openModal();
        await waitForPromises();

        expect(findEnableAddOnModal().props('visible')).toBe(true);
        expect(findEnableAddOnModal().props('onDemandEnabled')).toBe(false);
        expect(findEnableAddOnModal().props('entitlementCheckFailed')).toBe(true);
        expect(createAlert).not.toHaveBeenCalled();
        expect(Sentry.captureException).toHaveBeenCalledWith(error);
      });
    });

    // The trial and add-on flows share one status watcher; starting a trial
    // while the add-on enable is in flight would leave one flow stuck.
    it('does not start a trial while the add-on is being enabled', async () => {
      mockEnableAddOn.mockReturnValue(new Promise(() => {})); // add-on hangs -> isEnablingAddOn stays true
      await setUpBetaEligible();
      await openModal();
      await emitEnable();

      findRouterView().vm.$emit('start-trial');
      await nextTick();
      await confirmStartTrial();

      expect(mockEnrollNamespace).not.toHaveBeenCalled();
    });

    describe('on success', () => {
      beforeEach(async () => {
        await setUpBetaEligible();
        await openModal();
        await emitEnable();
      });

      it('calls the enable add-on mutation with the top-level group path', () => {
        expect(mockEnableAddOn).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('shows the success alert and refetches the entitlement', () => {
        expect(createAlert).toHaveBeenCalledWith(enableSuccessAlert);
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });

      it('clears the enabling state on the alert', () => {
        expect(findBetaTransitionAlert().props('isEnablingAddOn')).toBe(false);
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        mockEnableAddOn.mockResolvedValue(enableAddOnErrorResponse());
        await setUpBetaEligible();
        await openModal();
        await emitEnable();
      });

      it('surfaces the backend error and resets the enabling state', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'This group is not eligible to enable the Secrets Manager add-on.',
          }),
        );
        expect(findBetaTransitionAlert().props('isEnablingAddOn')).toBe(false);
      });
    });

    // Non-beta trial-eligible users reach the empty state, where the status
    // query is skipped until the add-on enable un-skips it so provisioning
    // can poll through to ACTIVE.
    describe('from the trial empty state', () => {
      const setUpTrialEligible = async ({ onDemandEnabled = true } = {}) => {
        mockEntitlementQuery.mockResolvedValue(
          entitlementResponse({ state: 'TRIAL_ELIGIBLE', onDemandEnabled }),
        );
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
        );
        await createComponent({
          context: ENTITY_GROUP,
          router: createRouterForTest(ENTITY_GROUP),
          provide: {
            canEnableAddOn: true,
            topLevelGroupFullPath: 'top-level-group',
          },
        });
      };

      it('opens the modal when the empty state emits `enable-add-on`', async () => {
        await setUpTrialEligible();
        expect(findEnableAddOnModal().props('visible')).toBe(false);

        findTrialEmptyState().vm.$emit('enable-add-on');
        await nextTick();

        expect(findEnableAddOnModal().props('visible')).toBe(true);
      });

      it('shows the enable button loading while the entitlement is re-checked', async () => {
        mockRefreshEntitlement.mockReturnValue(new Promise(() => {}));
        await setUpTrialEligible({ onDemandEnabled: false });

        findTrialEmptyState().vm.$emit('enable-add-on');
        await nextTick();

        expect(wrapper.findComponentByTestId('enable-add-on-button').props('loading')).toBe(true);
        expect(findEnableAddOnModal().props('visible')).toBe(false);
      });

      it('polls provisioning through to the success alert', async () => {
        await setUpTrialEligible();
        findTrialEmptyState().vm.$emit('enable-add-on');
        await nextTick();
        await emitEnable();

        // The empty state (which owns the Enable button spinner) must stay
        // mounted while provisioning polls, so the status watcher can fire.
        expect(findTrialEmptyState().exists()).toBe(true);

        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(mockEnableAddOn).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
        expect(createAlert).toHaveBeenCalledWith(enableSuccessAlert);
        // initial fetch + post-enable refetch once status reaches ACTIVE.
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('provision secrets manager', () => {
    const emitProvisionSecretsManager = async () => {
      findEmptyState().vm.$emit('provision-secrets-manager');
      await waitForPromises();
    };

    describe.each`
      context
      ${ENTITY_PROJECT}
      ${ENTITY_GROUP}
    `('in $context context', ({ context }) => {
      describe('on success', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
          mockEnableSecretsManager.mockResolvedValue(enableSecretManagerResponse({ context }));

          await createComponent({ context, router: createRouterForTest(context) });
          await emitProvisionSecretsManager();
        });

        it('calls the enable mutation with fullPath', () => {
          expect(mockEnableSecretsManager).toHaveBeenCalledWith({
            fullPath: defaultProvide.fullPath,
          });
        });

        it('refetches the secrets manager status', () => {
          // status was fetched on load; refetch after successful mutation.
          expect(mockSecretManagerStatus).toHaveBeenCalledTimes(2);
        });
      });

      describe('when the mutation returns errors', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
          mockEnableSecretsManager.mockResolvedValue(
            enableSecretManagerResponse({
              context,
              errors: ['Secrets Manager access is restricted for this namespace.'],
            }),
          );

          await createComponent({ context, router: createRouterForTest(context) });
          await emitProvisionSecretsManager();
        });

        // Payload errors are user-facing denials; showing them as-is names
        // the cause instead of inviting retries that cannot succeed.
        it('surfaces the backend error message', () => {
          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message: 'Secrets Manager access is restricted for this namespace.',
              captureError: true,
            }),
          );
        });

        it('clears the loading state on button', () => {
          // button loading is bound to isProvisioning; ensure it's reset after error.
          expect(findEmptyStateNewSecretBtn().props('loading')).toBe(false);
        });
      });

      describe('when the mutation fails', () => {
        beforeEach(async () => {
          mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
          mockEnableSecretsManager.mockRejectedValue(
            Object.assign(new Error('GraphQL network error'), { networkError: true }),
          );

          await createComponent({ context, router: createRouterForTest(context) });
          await emitProvisionSecretsManager();
        });

        it('creates a generic error alert and captures the error', () => {
          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message:
                'GitLab Secrets Manager could not be enabled. If the problem persists, contact your group owner or instance administrator.',
              captureError: true,
            }),
          );
        });

        it('clears the loading state on button', () => {
          expect(findEmptyStateNewSecretBtn().props('loading')).toBe(false);
        });
      });
    });
  });

  describe('start trial', () => {
    const emitStartTrial = async () => {
      findTrialEmptyState().vm.$emit('start-trial');
      await nextTick();
      await confirmStartTrial();
    };

    const trialSuccessAlert = {
      message:
        'The GitLab Secrets Manager trial has been enabled for all groups and projects within this namespace. %{linkStart}Manage group permissions.%{linkEnd}',
      messageLinks: { link: managePermissionsPath },
      variant: VARIANT_SUCCESS,
    };

    // Trial chain runs against a TLG, so we're always in ENTITY_GROUP context.
    const setUpTrialEligible = async () => {
      await createComponent({
        context: ENTITY_GROUP,
        router: createRouterForTest(ENTITY_GROUP),
        provide: {
          topLevelGroupFullPath: 'top-level-group',
        },
      });
    };

    beforeEach(() => {
      mockEntitlementQuery.mockResolvedValue(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }));
      // TLG provisioning mutation succeeds; backend then flips status to
      // PROVISIONING while the async job runs, and finally to ACTIVE.
      mockEnableSecretsManager.mockResolvedValue(
        enableSecretManagerResponse({ context: ENTITY_GROUP }),
      );
      mockSecretManagerStatus.mockResolvedValue(
        secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
      );
    });

    describe('when the empty state CTA is clicked', () => {
      beforeEach(async () => {
        await setUpTrialEligible();
        findTrialEmptyState().vm.$emit('start-trial');
        await nextTick();
      });

      it('opens the confirmation modal without starting the chain', () => {
        expect(findStartTrialModal().props('visible')).toBe(true);
        expect(mockEnrollNamespace).not.toHaveBeenCalled();
      });

      it('closes the modal and starts the chain on confirm', async () => {
        await confirmStartTrial();

        expect(findStartTrialModal().props('visible')).toBe(false);
        expect(mockEnrollNamespace).toHaveBeenCalled();
      });

      it('closes the modal without starting the chain on hide', async () => {
        findStartTrialModal().vm.$emit('hide');
        await nextTick();

        expect(findStartTrialModal().props('visible')).toBe(false);
        expect(mockEnrollNamespace).not.toHaveBeenCalled();
      });
    });

    describe('on successful onboarding', () => {
      beforeEach(async () => {
        await setUpTrialEligible();
        await emitStartTrial();
        // Simulate the backend provisioning job completing.
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('fires enrollment mutation with the top-level group path', () => {
        expect(mockEnrollNamespace).toHaveBeenCalledWith({ fullPath: 'top-level-group' });
      });

      it('fires trial mutation with the top-level group path', () => {
        expect(mockStartTrial).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('fires provisioning mutation with the current fullPath', () => {
        expect(mockEnableSecretsManager).toHaveBeenCalledWith({
          fullPath: defaultProvide.fullPath,
        });
      });

      it('refetches the entitlement after the chain succeeds', () => {
        // initial fetch + post-chain refetch (fires from the status watch)
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });

      it('shows a single success alert with the settings link', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('while provisioning is still polling', () => {
      const setUpPendingProvisioning = async () => {
        mockSecretManagerStatus.mockResolvedValue(
          secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, ENTITY_GROUP),
        );
        await setUpTrialEligible();
        await emitStartTrial();
      };

      it('keeps the trial empty state visible', async () => {
        await setUpPendingProvisioning();
        expect(findTrialEmptyState().exists()).toBe(true);
      });

      it('does not show the success alert', async () => {
        await setUpPendingProvisioning();
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('does not refetch the entitlement while polling', async () => {
        await setUpPendingProvisioning();
        // Only the initial fetch; the post-chain refetch must wait until
        // the status flips to ACTIVE so on-refetch UI reflects the final
        // (TRIAL) state rather than the transient trial-eligible state.
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(1);
      });

      it('shows success alert after polling ends and secrets manager is provisioned', async () => {
        await setUpPendingProvisioning();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });

      it('refetches the entitlement only after status reaches ACTIVE', async () => {
        await setUpPendingProvisioning();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        // initial fetch + post-chain refetch (fires only after ACTIVE)
        expect(mockEntitlementQuery).toHaveBeenCalledTimes(2);
      });
    });

    describe('New secret button after onboarding in the same visit', () => {
      beforeEach(async () => {
        // First fetch: trial_eligible; post-chain refetch: trial started.
        mockEntitlementQuery
          .mockResolvedValueOnce(entitlementResponse({ state: 'TRIAL_ELIGIBLE' }))
          .mockResolvedValue(entitlementResponse({ state: 'TRIAL' }));

        await setUpTrialEligible();
        await emitStartTrial();

        // Simulate the provisioning job completing with the fresh ACL answer.
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('shows the New secret button without a reload', () => {
        expect(findEmptyStateNewSecretBtn().exists()).toBe(true);
      });
    });

    describe('when enroll returns a benign already-enrolled error', () => {
      beforeEach(async () => {
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        await setUpTrialEligible();
        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('continues to trial', () => {
        expect(mockStartTrial).toHaveBeenCalledWith({ groupPath: 'top-level-group' });
      });

      it('shows a success message with the settings link', () => {
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when start trial returns a benign error', () => {
      beforeEach(async () => {
        mockStartTrial.mockResolvedValue(
          startTrialErrorResponse(['A Secrets Manager trial is already active for this group.']),
        );
        await setUpTrialEligible();
        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('continues to provisioning', () => {
        expect(mockEnableSecretsManager).toHaveBeenCalled();
      });

      it('shows a success message with the settings link', () => {
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when provisioning returns a benign already-initialized error', () => {
      beforeEach(async () => {
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({
            context: ENTITY_GROUP,
            errors: ['Secrets manager already initialized for the group.'],
          }),
        );
        await setUpTrialEligible();
        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);
      });

      it('shows the success alert', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when enrollment fails with a non-benign error', () => {
      beforeEach(async () => {
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceErrorResponse(['Not authorized']));
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('does not call start trial', () => {
        expect(mockStartTrial).not.toHaveBeenCalled();
      });

      it('does not call provisioning', () => {
        expect(mockEnableSecretsManager).not.toHaveBeenCalled();
      });

      it('shows an error alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'Not authorized' }),
        );
      });

      it('keeps the trial empty state visible for retry', () => {
        expect(findTrialEmptyState().exists()).toBe(true);
      });
    });

    describe('when start trial fails after enrollment succeeds', () => {
      beforeEach(async () => {
        mockStartTrial.mockResolvedValue(startTrialErrorResponse(['This group is not eligible']));
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('does not call provisioning', () => {
        expect(mockEnableSecretsManager).not.toHaveBeenCalled();
      });

      it('shows an error alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'This group is not eligible' }),
        );
      });

      it('re-runs the chain on retry', async () => {
        // partial-progress retry: enroll is idempotent and returns benign
        // error; trial now succeeds; provisioning completes; success alert
        // fires from the status watch.
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        mockStartTrial.mockResolvedValue(startTrialSuccessResponse());

        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(mockEnrollNamespace).toHaveBeenCalledTimes(2);
        expect(mockStartTrial).toHaveBeenCalledTimes(2);
        expect(mockEnableSecretsManager).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });

    describe('when a mutation in the chain throws (transport-level error)', () => {
      // Distinct from "mutation returns errors" (GraphQL payload errors,
      // covered above): this covers the promise-rejection path (network
      // failure, transport-level exception).
      beforeEach(async () => {
        mockEnrollNamespace.mockRejectedValue(new Error('Network error'));
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('surfaces the thrown error message', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'Network error',
            captureError: true,
          }),
        );
      });

      it('does not show the success alert', () => {
        expect(createAlert).not.toHaveBeenCalledWith(trialSuccessAlert);
      });

      it('keeps the trial empty state visible for retry', () => {
        expect(findTrialEmptyState().exists()).toBe(true);
      });
    });

    describe('when a mutation throws without a message', () => {
      // Covers the generic-copy fallback path: some transport errors surface
      // as an Error without a useful `.message`. The catch should fall back
      // to the generic "An error occurred..." copy so the user isn't shown
      // an empty alert.
      beforeEach(async () => {
        mockEnrollNamespace.mockRejectedValue(new Error());
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('shows the generic trial error alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'An error occurred while starting the trial.',
            captureError: true,
          }),
        );
      });
    });

    describe('when provisioning fails after trial succeeds', () => {
      beforeEach(async () => {
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({
            context: ENTITY_GROUP,
            errors: ['Provisioning backend unavailable'],
          }),
        );
        await setUpTrialEligible();
        await emitStartTrial();
      });

      it('shows the provisioning error', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'Provisioning backend unavailable' }),
        );
      });

      it('does not show the success alert', () => {
        expect(createAlert).not.toHaveBeenCalledWith(trialSuccessAlert);
      });

      it('keeps the trial empty state visible for retry', () => {
        expect(findTrialEmptyState().exists()).toBe(true);
      });

      it('re-runs the full chain on retry', async () => {
        // benign errors on enroll and trial (already done); provisioning
        // now succeeds and status flips to ACTIVE; single success alert.
        mockEnrollNamespace.mockResolvedValue(enrollNamespaceAlreadyEnrolledResponse());
        mockStartTrial.mockResolvedValue(
          startTrialErrorResponse(['A Secrets Manager trial is already active for this group.']),
        );
        mockEnableSecretsManager.mockResolvedValue(
          enableSecretManagerResponse({ context: ENTITY_GROUP }),
        );

        await emitStartTrial();
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, ENTITY_GROUP);

        expect(mockEnableSecretsManager).toHaveBeenCalledTimes(2);
        expect(createAlert).toHaveBeenCalledWith(trialSuccessAlert);
      });
    });
  });

  describe('provisioning success alert', () => {
    // simulate the empty state's click, then simulate the backend returning
    // PROVISIONING on the post-mutation refetch (so polling kicks in).
    const startProvisioningFlow = async (context) => {
      mockSecretManagerStatus.mockResolvedValue(
        secretManagerStatusResponse(SECRET_MANAGER_STATUS_PROVISIONING, context),
      );
      findEmptyState().vm.$emit('provision-secrets-manager');
      await waitForPromises();
    };

    describe.each`
      context           | expectedMessage
      ${ENTITY_PROJECT} | ${'GitLab Secrets Manager has been enabled for this project.'}
      ${ENTITY_GROUP}   | ${'GitLab Secrets Manager has been enabled for this group.'}
    `('in $context context', ({ context, expectedMessage }) => {
      beforeEach(async () => {
        // start with an unprovisioned state so the user can click "New secret"
        // to kick off provisioning.
        mockSecretManagerStatus.mockResolvedValue({ data: { secretsManager: null } });
        mockEnableSecretsManager.mockResolvedValue(enableSecretManagerResponse({ context }));
        await createComponent({ context, router: createRouterForTest(context) });
      });

      it('fires a success alert with a manage permissions link', async () => {
        await startProvisioningFlow(context);
        await pollNextStatus(SECRET_MANAGER_STATUS_ACTIVE, context);

        expect(createAlert).toHaveBeenCalledWith({
          message: `${expectedMessage} %{linkStart}Manage permissions.%{linkEnd}`,
          messageLinks: { link: managePermissionsPath },
          variant: VARIANT_SUCCESS,
        });
      });
    });
  });
});
