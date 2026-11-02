<script>
import { NetworkStatus } from '@apollo/client/core';
import { computed } from 'vue';
import { GlLoadingIcon, GlToastMixin } from '@gitlab/ui';
import { s__ } from '~/locale';
import { createAlert, VARIANT_SUCCESS } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { fetchPolicies } from '~/lib/graphql';
import { formatGraphQLError } from 'ee/ci/secrets/utils';
import enrollNamespaceMutation from 'ee/ci/secrets/graphql/mutations/enroll_namespace_secrets_manager.mutation.graphql';
import RouterViewWithSlot from '~/vue_shared/spa/components/router_view_with_slot';
import {
  BENIGN_ENROLL_ERRORS,
  BENIGN_PROVISION_ERRORS,
  BENIGN_TRIAL_ERRORS,
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
  ENTITY_GROUP,
  I18N_ADD_ON_ENABLED_ALERT,
  I18N_TRIAL_STARTED_ALERT,
  INDEX_ROUTE_NAME,
  NEW_ROUTE_NAME,
  POLL_INTERVAL,
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_ERROR,
  SECRET_MANAGER_STATUS_PROVISIONING,
} from '../constants';
import getEntitlementQuery from '../graphql/queries/get_secrets_manager_entitlement.graphql';
import getOpenbaoHealthQuery from '../graphql/queries/get_openbao_health.query.graphql';
import startTrialMutation from '../graphql/mutations/start_secrets_manager_trial.mutation.graphql';
import enableAddOnMutation from '../graphql/mutations/enable_secrets_manager_add_on.mutation.graphql';
import refreshEntitlementMutation from '../graphql/mutations/refresh_secrets_manager_entitlement.mutation.graphql';
import SecretsBetaTransitionAlert from './secrets_beta_transition_alert.vue';
import SecretsManagerTrialAlert from './secrets_manager_trial_alert.vue';
import EnableAddOnModal from './enable_add_on_modal.vue';
import StartTrialModal from './start_trial_modal.vue';

export default {
  name: 'SecretsApp',
  components: {
    GlLoadingIcon,
    RouterViewWithSlot,
    SecretsBetaTransitionAlert,
    SecretsManagerTrialAlert,
    EnableAddOnModal,
    StartTrialModal,
  },
  mixins: [GlToastMixin],
  inject: [
    'canStartTrial',
    'contextConfig',
    'fullPath',
    'isSaas',
    'managePermissionsPath',
    'topLevelGroupFullPath',
  ],
  provide() {
    return {
      canCreateSecret: computed(() => this.canCreateSecret),
      canUpdateSecret: computed(() => this.canUpdateSecret),
      canDeleteSecret: computed(() => this.canDeleteSecret),
      entitlement: computed(() => this.entitlement),
      hasNoReadAccess: computed(() => this.hasNoReadAccess),
      isBetaReadOnly: computed(() => this.isBetaReadOnly),
      isBetaUser: computed(() => this.isBetaUser),
      isCheckingEntitlement: computed(() => this.isCheckingEntitlement),
      isEnablingAddOn: computed(() => this.isEnablingAddOn),
      isOpenbaoHealthy: computed(() => this.isOpenbaoHealthy),
      isProvisioning: computed(() => this.isProvisioning),
      isReadOnly: computed(() => this.isReadOnly),
      isTrialOnboarding: computed(() => this.isTrialOnboarding),
      secretManagerStatus: computed(() => this.secretManagerStatus),
      showNoReadAccessAlert: computed(() => this.showNoReadAccessAlert),
    };
  },
  data() {
    return {
      entitlement: null,
      entitlementNetworkStatus: NetworkStatus.loading,
      secretManagerStatus: undefined,
      isEntityBlocked: false,
      isStrictReadOnly: false,
      writeDenialReason: null,
      userPermissions: null,
      isOpenbaoHealthy: true,
      isProvisioning: false,
      isTrialOnboarding: false,
      isCheckingEntitlement: false,
      entitlementCheckFailed: false,
      isEnablingAddOn: false,
      showEnableAddOnModal: false,
      showStartTrialModal: false,
    };
  },
  apollo: {
    entitlement: {
      query: getEntitlementQuery,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      notifyOnNetworkStatusChange: true,
      skip() {
        return !this.topLevelGroupFullPath;
      },
      variables() {
        return {
          fullPath: this.topLevelGroupFullPath,
        };
      },
      update(data) {
        return data.group?.secretsManagerEntitlement;
      },
      result({ networkStatus }) {
        this.entitlementNetworkStatus = networkStatus;
      },
      error(e) {
        createAlert({
          message: formatGraphQLError(e.message),
          captureError: true,
          error: e,
        });
      },
    },
    isOpenbaoHealthy: {
      query: getOpenbaoHealthQuery,
      update(data) {
        if (!data.openbaoHealth) {
          this.showOpenbaoUnhealthyAlert();
          this.redirectToIndex();
        }
        return data.openbaoHealth;
      },
      error() {
        this.isOpenbaoHealthy = false;
        this.showOpenbaoUnhealthyAlert();
        this.redirectToIndex();
      },
    },
    secretManagerStatus: {
      query() {
        return this.contextConfig.getStatus.query;
      },

      skip() {
        // Beta cohort users keep read access during trial_eligible, so we
        // still need the status to render their secrets table. Non-beta
        // users skip the status until the trial starts or they enable the
        // add-on -- both need the status to poll provisioning through to
        // ACTIVE.
        const isSettingUpTrial =
          this.isTrialEligible &&
          !this.isTrialOnboarding &&
          !this.isEnablingAddOn &&
          !this.isBetaUser;
        return this.isEntitlementLoading || isSettingUpTrial;
      },
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        // when not provisioned, secretsManagerStatus will return null
        if (data.secretsManager == null) {
          this.$apollo.queries.secretManagerStatus.stopPolling();
          this.userPermissions = null;
          return null;
        }

        const {
          readOnly,
          status,
          userPermissions,
          writeDenialReason,
          entity: { archived, markedForDeletion },
        } = data.secretsManager;

        this.isEntityBlocked = archived || markedForDeletion;
        this.isStrictReadOnly = readOnly;
        this.userPermissions = userPermissions ?? null;
        this.writeDenialReason = writeDenialReason ?? null;

        // if the user visits the page while provisioning is already
        // in-progress, make sure we poll the status for changes
        if (status === SECRET_MANAGER_STATUS_PROVISIONING) {
          this.isProvisioning = true;
          this.$apollo.queries.secretManagerStatus.startPolling(POLL_INTERVAL);
        } else {
          this.$apollo.queries.secretManagerStatus.stopPolling();
        }

        return status;
      },
      error(e) {
        this.$apollo.queries.secretManagerStatus.stopPolling();
        this.secretManagerStatus = SECRET_MANAGER_STATUS_ERROR;
        createAlert({
          message: formatGraphQLError(e.message),
          captureError: true,
          error: e,
        });
      },
      pollInterval: POLL_INTERVAL,
    },
  },
  computed: {
    hasStatusError() {
      return this.secretManagerStatus && this.secretManagerStatus === SECRET_MANAGER_STATUS_ERROR;
    },
    isEntitlementLoading() {
      return this.$apollo.queries.entitlement.loading;
    },
    isEntitlementInitialLoading() {
      return this.isEntitlementLoading && this.entitlementNetworkStatus === NetworkStatus.loading;
    },
    // Whether this namespace opted in during the free-beta program. The
    // backend records it per realm (namespace enrollment `beta` on SaaS,
    // instance enrollment on self-managed), so the entitlement is the single
    // source of truth here. Beta users keep their secrets visible and
    // writable while `trial_eligible`.
    isBetaUser() {
      return Boolean(this.entitlement?.betaWindowEligible);
    },
    isBetaProgramEnded() {
      return Boolean(this.entitlement?.betaProgramEnded);
    },
    // Beta users keep rotation features while trial_eligible until the
    // entitlement reports betaProgramEnded.
    isBetaReadOnly() {
      return this.isBetaUser && this.isTrialEligible && this.isBetaProgramEnded;
    },
    isReadOnly() {
      return this.isEntityBlocked || this.isStrictReadOnly || Boolean(this.writeDenialReason);
    },
    // userPermissions already account for the entitlement and strict read-only
    // mode, but not for archived or pending-deletion namespaces.
    canCreateSecret() {
      return !this.isEntityBlocked && Boolean(this.userPermissions?.createSecrets);
    },
    canUpdateSecret() {
      return !this.isEntityBlocked && Boolean(this.userPermissions?.updateSecrets);
    },
    canDeleteSecret() {
      return !this.isEntityBlocked && Boolean(this.userPermissions?.deleteSecrets);
    },
    // Users with valid role but no OpenBao read grant
    hasNoReadAccess() {
      return (
        this.secretManagerStatus === SECRET_MANAGER_STATUS_ACTIVE &&
        !this.userPermissions?.readMetadata
      );
    },
    // The capabilities lookup also fails closed when OpenBao is down, which
    // the unhealthy alert already covers, so wait for a healthy result.
    showNoReadAccessAlert() {
      return (
        this.hasNoReadAccess &&
        this.isOpenbaoHealthy &&
        !this.$apollo.queries.isOpenbaoHealthy.loading
      );
    },
    isTrialEligible() {
      return this.entitlement?.state === ENTITLEMENT_STATE_TRIAL_ELIGIBLE;
    },
    // Only a TLG Owner on the TLG page can convert; the trial-start UI
    // renders there. Subgroups and projects see the alert without actions.
    showBetaTransitionAlertCta() {
      return this.canStartTrial && this.fullPath === this.topLevelGroupFullPath;
    },
    // Self-managed only sees the post-beta variant: its
    // `end_secrets_manager_beta_program` flag has no rollout yet, so the
    // grace countdown there would be stale.
    showBetaTransitionAlert() {
      return this.isSaas || this.isBetaProgramEnded;
    },
    // "Initial" here means "we've never had a resolved value" -- distinct
    // from `isEntitlementLoading` which stays true across refetches and
    // background polls. We need entitlement first
    // (to know if the user is trial-eligible), and only wait on status if
    // the entitlement says we're past trial-eligible (trial-eligible users
    // skip the status query entirely, so `undefined` there is expected,
    // not "still loading").
    isLoadingInitialQueries() {
      return (
        this.isEntitlementInitialLoading ||
        (!this.isTrialEligible && this.secretManagerStatus === undefined)
      );
    },
    provisioningSuccessMessage() {
      return this.contextConfig.type === ENTITY_GROUP
        ? s__(
            'SecretsManager|GitLab Secrets Manager has been enabled for this group. %{linkStart}Manage permissions.%{linkEnd}',
          )
        : s__(
            'SecretsManager|GitLab Secrets Manager has been enabled for this project. %{linkStart}Manage permissions.%{linkEnd}',
          );
    },
  },
  watch: {
    // Finalizes both provisioning flows:
    //   - Subgroup/project "New secret" button: routes to the new-secret
    //     form and shows a scope-specific success alert.
    //   - TLG trial chain (`startTrial`): refetches the entitlement so the
    //     UI moves out of the trial empty state, then shows the trial-
    //     started alert.
    // On ERROR, both flows surface a failure alert and let the user retry.
    secretManagerStatus(newStatus) {
      if (!this.isProvisioning) return;

      if (newStatus === SECRET_MANAGER_STATUS_ERROR) {
        this.isProvisioning = false;

        if (this.isTrialOnboarding) {
          this.isTrialOnboarding = false;
        }

        if (this.isEnablingAddOn) {
          this.isEnablingAddOn = false;
        }

        createAlert({
          message: s__(
            'SecretsManager|Something went wrong while setting up the secrets manager. Please try again.',
          ),
          captureError: true,
        });
        return;
      }

      if (newStatus !== SECRET_MANAGER_STATUS_ACTIVE) return;

      this.isProvisioning = false;

      if (this.isTrialOnboarding) {
        this.completeTrialOnboarding();
        return;
      }

      if (this.isEnablingAddOn) {
        this.finalizeAddOnEnable();
        return;
      }

      this.$router.push({ name: NEW_ROUTE_NAME });
      createAlert({
        message: this.provisioningSuccessMessage,
        messageLinks: { link: this.managePermissionsPath },
        variant: VARIANT_SUCCESS,
      });
    },
  },
  methods: {
    showOpenbaoUnhealthyAlert() {
      createAlert({
        title: s__('SecretsManager|Cannot connect to OpenBao'),
        message: s__(
          'SecretsManager|Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
        ),
      });
    },
    redirectToIndex() {
      if (this.$route?.name !== INDEX_ROUTE_NAME) {
        this.$router.push({ name: INDEX_ROUTE_NAME });
      }
    },
    // Fires the initialize mutation and refetches the status query so
    // polling picks up (PROVISIONING → ACTIVE). Errors listed in
    // benignErrors are swallowed so callers chaining retries after partial
    // progress see a no-op instead of a failure.
    async runProvisioningMutation({ benignErrors = [] } = {}) {
      this.isProvisioning = true;

      const { data } = await this.$apollo.mutate({
        mutation: this.contextConfig.enableSecretsManager.mutation,
        variables: { fullPath: this.fullPath },
      });

      const { errors } = this.contextConfig.enableSecretsManager.lookup(data) || {};

      if (errors?.length && !benignErrors.includes(errors[0])) {
        throw new Error(errors[0]);
      }

      await this.$apollo.queries.secretManagerStatus.refetch();
    },
    async provisionSecretsManager() {
      try {
        await this.runProvisioningMutation();
      } catch (error) {
        this.isProvisioning = false;

        // Payload errors (thrown as plain Errors above) are user-facing
        // denials from the backend, e.g. an entitlement restriction; show
        // them as-is instead of a generic message that invites retries.
        const isPayloadError = !error.graphQLErrors && !error.networkError;

        createAlert({
          message: isPayloadError
            ? error.message
            : s__(
                'SecretsManager|GitLab Secrets Manager could not be enabled. If the problem persists, contact your group owner or instance administrator.',
              ),
          captureError: true,
          error,
        });
      }
    },
    showSecretsToast(message) {
      this.$toast.show(message);
    },
    // Runs one step of the trial-button onboarding chain. Treats any error
    // in benignErrors (backend messages like "already enrolled" / "trial
    // already active") as success so the chain can proceed to the next step.
    // Non-benign errors throw so the caller can short-circuit the rest of
    // the chain.
    async runOnboardingMutation({ mutation, variables, payloadKey, benignErrors = [] }) {
      const { data } = await this.$apollo.mutate({ mutation, variables });
      const { errors } = data[payloadKey] || {};

      if (!errors?.length) return;
      if (benignErrors.includes(errors[0])) return;

      throw new Error(errors[0]);
    },
    completeTrialOnboarding() {
      this.isTrialOnboarding = false;
      this.isProvisioning = false;
      this.$apollo.queries.entitlement.refetch();
      createAlert({
        message: I18N_TRIAL_STARTED_ALERT,
        messageLinks: { link: this.managePermissionsPath },
        variant: VARIANT_SUCCESS,
      });
    },
    // TLG one-click onboarding: enroll → start trial → provision. The status
    // watcher finalizes once polling reaches ACTIVE; already-provisioned beta
    // groups never change status, so finalize inline for them.
    async startTrial() {
      if (this.isTrialOnboarding || this.isEnablingAddOn) return;

      this.showStartTrialModal = false;
      this.isTrialOnboarding = true;

      try {
        await this.runOnboardingMutation({
          mutation: enrollNamespaceMutation,
          variables: { fullPath: this.topLevelGroupFullPath },
          payloadKey: 'namespaceSecretsManagerEnroll',
          benignErrors: BENIGN_ENROLL_ERRORS,
        });

        await this.runOnboardingMutation({
          mutation: startTrialMutation,
          variables: { groupPath: this.topLevelGroupFullPath },
          payloadKey: 'secretsManagerStartTrial',
          benignErrors: BENIGN_TRIAL_ERRORS,
        });

        await this.runProvisioningMutation({ benignErrors: BENIGN_PROVISION_ERRORS });

        if (this.isTrialOnboarding && this.secretManagerStatus === SECRET_MANAGER_STATUS_ACTIVE) {
          this.completeTrialOnboarding();
        }
      } catch (error) {
        this.isTrialOnboarding = false;
        this.isProvisioning = false;
        createAlert({
          message:
            error.message || s__('SecretsManager|An error occurred while starting the trial.'),
          captureError: true,
          error,
        });
      }
    },
    finalizeAddOnEnable() {
      this.isEnablingAddOn = false;
      this.isProvisioning = false;
      this.$apollo.queries.entitlement.refetch();
      createAlert({
        message: I18N_ADD_ON_ENABLED_ALERT,
        messageLinks: { link: this.managePermissionsPath },
        variant: VARIANT_SUCCESS,
      });
    },
    // Consent given in the Customers Portal can be newer than the cached
    // entitlement, so re-check before showing the "no GitLab Credits" dialog.
    async openEnableAddOnModal() {
      if (this.isCheckingEntitlement) return;

      this.entitlementCheckFailed = false;

      if (!this.entitlement?.onDemandEnabled) {
        await this.refreshEntitlement();
      }

      this.showEnableAddOnModal = true;
    },
    async refreshEntitlement() {
      this.isCheckingEntitlement = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: refreshEntitlementMutation,
          variables: { groupPath: this.topLevelGroupFullPath },
          context: { featureCategory: 'secrets_management' },
        });
        const { entitlement } = data?.secretsManagerRefreshEntitlement ?? {};

        if (entitlement) {
          this.entitlement = entitlement;
        } else {
          this.entitlementCheckFailed = true;
        }
      } catch (error) {
        // The dialog still opens, with the entitlement the page already has and a warning.
        this.entitlementCheckFailed = true;
        Sentry.captureException(error);
      } finally {
        this.isCheckingEntitlement = false;
      }
    },
    async enableAddOn() {
      if (this.isEnablingAddOn || this.isTrialOnboarding) return;

      this.showEnableAddOnModal = false;
      this.isEnablingAddOn = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: enableAddOnMutation,
          variables: { groupPath: this.topLevelGroupFullPath },
        });

        const { errors } = data.secretsManagerEnableAddOn || {};
        if (errors?.length) {
          throw new Error(errors[0]);
        }

        await this.$apollo.queries.secretManagerStatus.refetch();

        if (this.secretManagerStatus === SECRET_MANAGER_STATUS_ACTIVE) {
          this.finalizeAddOnEnable();
        } else {
          this.isProvisioning = true;
        }
      } catch (error) {
        this.isEnablingAddOn = false;
        this.isProvisioning = false;
        createAlert({
          message:
            error.message ||
            s__('SecretsManager|An error occurred while enabling GitLab Secrets Manager.'),
          captureError: true,
          error,
        });
      }
    },
  },
};
</script>
<template>
  <!-- Only show loading icon on initial fetch. Subsequent refetches and polls should not unmount the router view, which would reset local component state (e.g. the empty state's provisioning button spinner). -->
  <gl-loading-icon
    v-if="isLoadingInitialQueries"
    data-testid="secrets-manager-loading-status"
    class="gl-mt-5"
  />
  <div v-else-if="!hasStatusError">
    <secrets-manager-trial-alert
      v-if="entitlement || writeDenialReason"
      :entitlement="entitlement"
      :write-denial-reason="writeDenialReason"
    />
    <secrets-beta-transition-alert
      v-if="showBetaTransitionAlert"
      :is-beta="isBetaUser"
      :is-trial-eligible="isTrialEligible"
      :beta-program-ended="isBetaProgramEnded"
      :is-checking-entitlement="isCheckingEntitlement"
      :is-enabling-add-on="isEnablingAddOn"
      :is-trial-onboarding="isTrialOnboarding"
      :show-cta="showBetaTransitionAlertCta"
      @start-trial="showStartTrialModal = true"
      @enable-add-on="openEnableAddOnModal"
    />
    <enable-add-on-modal
      :visible="showEnableAddOnModal"
      :on-demand-enabled="Boolean(entitlement && entitlement.onDemandEnabled)"
      :entitlement-check-failed="entitlementCheckFailed"
      @enable="enableAddOn"
      @hide="showEnableAddOnModal = false"
    />
    <start-trial-modal
      :visible="showStartTrialModal"
      scope="group"
      @start-trial="startTrial"
      @hide="showStartTrialModal = false"
    />
    <router-view-with-slot #default="{ Component }">
      <component
        :is="Component"
        ref="router-view"
        @provision-secrets-manager="provisionSecretsManager"
        @show-secrets-toast="showSecretsToast"
        @start-trial="showStartTrialModal = true"
        @enable-add-on="openEnableAddOnModal"
      />
    </router-view-with-slot>
  </div>
</template>
