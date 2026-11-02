<script>
import { GlAlert, GlLink, GlSkeletonLoader, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { groupSecretsPath } from 'ee/lib/utils/path_helpers/group';
import {
  ENTITLEMENT_STATE_PAID,
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_INACTIVE,
  SECRET_MANAGER_STATUS_PROVISIONING,
  SECRET_MANAGER_STATUS_DEPROVISIONING,
  ENTITY_PROJECT,
  ENTITY_GROUP,
} from 'ee/ci/secrets/constants';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import SecretsBetaTransitionAlert from 'ee/ci/secrets/components/secrets_beta_transition_alert.vue';
import SecretsManagerPaidAlert from 'ee/ci/secrets/components/secrets_manager_paid_alert.vue';
import SecretsManagerTrialAlert from 'ee/ci/secrets/components/secrets_manager_trial_alert.vue';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';
import {
  formatGraphQLError,
  hasSelectedTrialOrPaidAddOn,
  isProvisioningBlockedByEntitlement,
} from 'ee/ci/secrets/utils';
import getOpenbaoHealthQuery from 'ee/ci/secrets/graphql/queries/get_openbao_health.query.graphql';
import getEntitlementQuery from 'ee/ci/secrets/graphql/queries/get_secrets_manager_entitlement.graphql';
import startTrialMutation from 'ee/ci/secrets/graphql/mutations/start_secrets_manager_trial.mutation.graphql';
import enableAddOnMutation from 'ee/ci/secrets/graphql/mutations/enable_secrets_manager_add_on.mutation.graphql';
import { SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG } from './context_config';
import getEnrollment from './graphql/get_gsm_namespace_enrollment.query.graphql';
import PermissionsSettings from './components/secrets_manager_permissions_settings.vue';
import SaasEnrollmentToggle from './components/secrets_manager_saas_enrollment_toggle.vue';

export const POLL_INTERVAL = 2000;

const DESCRIPTION_MESSAGES = {
  [ENTITY_PROJECT]: s__(
    'SecretsManagerPermissions|Store secrets in the secrets manager, which can then be fetched by this project.',
  ),
  [ENTITY_GROUP]: s__(
    'SecretsManagerPermissions|Store secrets in the secrets manager, which can then be fetched by any project in this group and its subgroups.',
  ),
};

export default {
  name: 'SecretsManagerSettings',
  components: {
    EnableAddOnModal,
    GlAlert,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
    PermissionsSettings,
    SaasEnrollmentToggle,
    SecretsBetaTransitionAlert,
    SecretsManagerPaidAlert,
    SecretsManagerTrialAlert,
    StartTrialModal,
  },
  props: {
    canEnrollNamespace: {
      type: Boolean,
      required: false,
      default: false,
    },
    canManageSecretsManager: {
      type: Boolean,
      required: true,
    },
    canStartTrial: {
      type: Boolean,
      required: false,
      default: false,
    },
    context: {
      type: String,
      required: true,
    },
    fullPath: {
      type: String,
      required: true,
    },
    // Inside the standalone settings block (the group Secure tab) the block
    // supplies the heading and description, so the component's own inline
    // title/label/description are suppressed to avoid duplication.
    hideInlineText: {
      type: Boolean,
      required: false,
      default: false,
    },
    isNamespaceEnrollable: {
      type: Boolean,
      required: false,
      default: false,
    },
    topLevelGroupFullPath: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      entitlement: null,
      errorMessage: '',
      hasEnrollmentQueryError: false,
      isEnablingAddOn: false,
      isEnrolled: false,
      isOpenbaoHealthy: true,
      isStartingTrial: false,
      secretManagerStatus: SECRET_MANAGER_STATUS_INACTIVE,
      showEnableAddOnModal: false,
      showStartTrialModal: false,
    };
  },
  computed: {
    contextConfig() {
      return SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG[this.context];
    },
    isActive() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_ACTIVE;
    },
    isEnrollableAndNotEnrolled() {
      return this.isNamespaceEnrollable && !this.isEnrolled;
    },
    isBlockedByEntitlement() {
      return isProvisioningBlockedByEntitlement(this.entitlement);
    },
    isBetaUser() {
      return Boolean(this.entitlement?.betaWindowEligible);
    },
    isConverting() {
      return this.isStartingTrial || this.isEnablingAddOn;
    },
    isPaid() {
      return this.entitlement?.state === ENTITLEMENT_STATE_PAID;
    },
    isTrialEligible() {
      return this.entitlement?.state === ENTITLEMENT_STATE_TRIAL_ELIGIBLE;
    },
    isLoadingEnrollment() {
      return this.$apollo.queries.isEnrolled.loading;
    },
    // The entitlement decides whether the enrollment toggle is rendered at all.
    // Initial load only, so a refetch after a CTA doesn't swap the block for the skeleton.
    isLoadingEntitlement() {
      return this.$apollo.queries.entitlement.loading && !this.entitlement;
    },
    isLoadingProvisionStatus() {
      return this.$apollo.queries.secretManagerStatus?.loading ?? false;
    },
    // The section's visibility depends on isActive, so the status fetch also
    // holds the skeleton, except while provisioning or deprovisioning polls.
    isLoadingStatusForVisibility() {
      return this.isLoadingProvisionStatus && !this.isProvisioning && !this.isDeprovisioning;
    },
    isLoadingOpenbaoHealth() {
      return this.$apollo.queries.isOpenbaoHealthy.loading;
    },
    isLoadingInitialState() {
      return (
        this.isLoadingOpenbaoHealth ||
        this.isLoadingEnrollment ||
        this.isLoadingEntitlement ||
        this.isLoadingStatusForVisibility
      );
    },
    isProvisioning() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_PROVISIONING;
    },
    isDeprovisioning() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_DEPROVISIONING;
    },
    hasError() {
      return this.errorMessage.length > 0;
    },
    descriptionMessage() {
      return DESCRIPTION_MESSAGES[this.context];
    },
    provisioningToggleLabel() {
      return s__('SecretsManagerPermissions|GitLab Secrets Manager');
    },
    // Subgroups and projects show their own title. Inside the standalone Secure
    // block the block supplies that heading, so the inline one is suppressed.
    showNonTlgTitle() {
      return !this.isNamespaceEnrollable && !this.hideInlineText;
    },
    // The entitlement belongs to the top-level group, so its banners only
    // render on the TLG's own settings, never on subgroups or projects.
    showEntitlementBanners() {
      return this.isNamespaceEnrollable && Boolean(this.entitlement);
    },
    showPermissionsTable() {
      if (!this.isOpenbaoHealthy) {
        return false;
      }

      // isEnrolled is only fetched for enrollable namespaces (SaaS top-level
      // groups), so gate on isEnrollableAndNotEnrolled rather than isEnrolled
      // to keep the table visible for subgroups, projects, and self-managed.
      return this.isActive && !this.isEnrollableAndNotEnrolled;
    },
    secretsPagePath() {
      return groupSecretsPath(this.fullPath);
    },
    // The enrollment toggle only renders once a trial or add-on is selected,
    // but the Secure section heading around this app is server-rendered for
    // enrollable groups. Point the Owner at the secrets page (where the trial
    // and add-on CTAs live) instead of leaving the heading with an empty body.
    // Beta groups are excluded: they render the settings with the beta
    // transition alert's own CTAs instead.
    showTrialEligibleGuidance() {
      return (
        this.isNamespaceEnrollable &&
        !this.isBetaUser &&
        !this.isActive &&
        this.entitlement?.state === ENTITLEMENT_STATE_TRIAL_ELIGIBLE
      );
    },
    showsEnrollmentToggle() {
      return this.isNamespaceEnrollable && hasSelectedTrialOrPaidAddOn(this.entitlement);
    },
    showsBetaTransitionCtas() {
      return this.isNamespaceEnrollable && this.isBetaUser && this.isTrialEligible;
    },
    // The settings are only rendered when something in them is actionable, so
    // an unprovisioned subgroup, project, or self-managed group shows nothing.
    // Mirrors SecretsManagement::Availability.namespace_configurable? on the backend.
    showSettings() {
      return this.showsEnrollmentToggle || this.isActive || this.showsBetaTransitionCtas;
    },
  },
  apollo: {
    entitlement: {
      query: getEntitlementQuery,
      context: { featureCategory: 'secrets_management' },
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
      error() {
        this.errorMessage = s__(
          'SecretsManagerEntitlement|An error occurred while fetching the secrets manager entitlement state. Please refresh the page.',
        );
      },
    },
    isOpenbaoHealthy: {
      query: getOpenbaoHealthQuery,
      context: { featureCategory: 'secrets_management' },
      update(data) {
        return data.openbaoHealth;
      },
      error() {
        this.isOpenbaoHealthy = false;
      },
    },
    isEnrolled: {
      query: getEnrollment,
      context: { featureCategory: 'secrets_management' },
      skip() {
        return !this.isNamespaceEnrollable;
      },
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        // An explicit opt-out resolves to null on the backend, so it reads the
        // same as never enrolled here.
        const enrolled = Boolean(data.namespaceSecretsManagerEnrollment);

        // after enrolling and refetching the status, fetch provisioning status
        // since the query may have been skipped before
        if (enrolled) {
          this.$apollo.queries.secretManagerStatus.refetch();
        }

        return enrolled;
      },
      error() {
        this.hasEnrollmentQueryError = true;
        this.errorMessage = s__(
          'SecretsManagerPermissions|An error occurred while fetching the secrets manager enrollment status. Please refresh the page.',
        );
      },
    },
    secretManagerStatus: {
      query() {
        return this.contextConfig.getStatus.query;
      },
      context: { featureCategory: 'secrets_management' },
      skip() {
        return this.isEnrollableAndNotEnrolled;
      },
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        const { secretsManager } = data;
        const newStatus = secretsManager?.status || SECRET_MANAGER_STATUS_INACTIVE;

        if (
          newStatus === SECRET_MANAGER_STATUS_ACTIVE ||
          newStatus === SECRET_MANAGER_STATUS_INACTIVE
        ) {
          this.$apollo.queries.secretManagerStatus.stopPolling();
        }

        return newStatus;
      },
      error(e) {
        this.$apollo.queries.secretManagerStatus.stopPolling(POLL_INTERVAL);
        this.errorMessage =
          e.graphQLErrors?.[0]?.message ||
          s__(
            'SecretsManagerPermissions|An error occurred while fetching the secrets manager status.',
          );
      },
      pollInterval: POLL_INTERVAL,
    },
  },
  methods: {
    fetchEnrollmentStatus() {
      this.$apollo.queries.isEnrolled.refetch();
    },
    // A group only sees these CTAs while beta-enrolled, so unlike the secrets
    // page there is nothing to enroll or provision here; the entitlement
    // refetch is what flips the block into its trial or paid state.
    async runEntitlementMutation({ mutation, payloadKey, fallbackMessage }) {
      this.errorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation,
          variables: { groupPath: this.topLevelGroupFullPath },
          context: { featureCategory: 'secrets_management' },
        });
        const { errors = [] } = data?.[payloadKey] || {};

        if (errors.length > 0) {
          throw new Error(errors[0]);
        }
      } catch (error) {
        this.errorMessage = formatGraphQLError(error.message, fallbackMessage);
        return;
      }

      // A failed refetch is reported by the entitlement query's own error handler.
      await this.$apollo.queries.entitlement.refetch().catch(() => {});
    },
    async startTrial() {
      if (this.isConverting) return;

      this.showStartTrialModal = false;
      this.isStartingTrial = true;

      await this.runEntitlementMutation({
        mutation: startTrialMutation,
        payloadKey: 'secretsManagerStartTrial',
        fallbackMessage: s__('SecretsManager|An error occurred while starting the trial.'),
      });

      this.isStartingTrial = false;
    },
    async enableAddOn() {
      if (this.isConverting) return;

      this.showEnableAddOnModal = false;
      this.isEnablingAddOn = true;

      await this.runEntitlementMutation({
        mutation: enableAddOnMutation,
        payloadKey: 'secretsManagerEnableAddOn',
        fallbackMessage: s__(
          'SecretsManager|An error occurred while enabling GitLab Secrets Manager.',
        ),
      });

      this.isEnablingAddOn = false;
    },
  },
  LEARN_MORE_LINK: helpPagePath('ci/secrets/secrets_manager/_index'),
};
</script>

<template>
  <gl-skeleton-loader v-if="isLoadingInitialState" />
  <gl-alert
    v-else-if="showTrialEligibleGuidance"
    variant="info"
    :dismissible="false"
    data-testid="trial-eligible-guidance-alert"
  >
    <gl-sprintf
      :message="
        s__(
          'SecretsManagerPermissions|To use GitLab Secrets Manager, %{linkStart}start a trial or enable it with GitLab Credits%{linkEnd}.',
        )
      "
    >
      <template #link="{ content }">
        <gl-link :href="secretsPagePath">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
  </gl-alert>
  <div v-else-if="showSettings" data-testid="secret-manager">
    <saas-enrollment-toggle
      v-if="isNamespaceEnrollable"
      :can-manage-enrollment="canEnrollNamespace"
      :full-path="fullPath"
      :is-enrolled="isEnrolled"
      :disabled="isBlockedByEntitlement || isConverting"
      :has-enrollment-query-error="hasEnrollmentQueryError"
      :hide-inline-text="hideInlineText"
      @toggled="fetchEnrollmentStatus"
    />
    <template v-if="showNonTlgTitle">
      <p data-testid="non-tlg-settings-title" class="gl-mb-1 gl-text-base gl-font-bold">
        {{ provisioningToggleLabel }}
      </p>
      <p class="gl-mb-2 gl-text-subtle" data-testid="non-tlg-settings-description">
        {{ descriptionMessage }}
        <gl-link v-if="!isNamespaceEnrollable" :href="$options.LEARN_MORE_LINK">
          {{ __('Learn more.') }}
        </gl-link>
      </p>
    </template>
    <p v-if="hasError" class="gl-mt-2 gl-text-danger" data-testid="secret-manager-error">
      {{ errorMessage }}
    </p>
    <template v-if="showEntitlementBanners">
      <secrets-beta-transition-alert
        :is-beta="isBetaUser"
        :is-trial-eligible="isTrialEligible"
        :beta-program-ended="Boolean(entitlement.betaProgramEnded)"
        :is-enabling-add-on="isEnablingAddOn"
        :is-trial-onboarding="isStartingTrial"
        :show-cta="canStartTrial"
        @start-trial="showStartTrialModal = true"
        @enable-add-on="showEnableAddOnModal = true"
      />
      <secrets-manager-trial-alert :entitlement="entitlement" />
      <secrets-manager-paid-alert v-if="isPaid" :enabled="isEnrolled" />
      <enable-add-on-modal
        :visible="showEnableAddOnModal"
        :on-demand-enabled="Boolean(entitlement.onDemandEnabled)"
        @enable="enableAddOn"
        @hide="showEnableAddOnModal = false"
      />
      <start-trial-modal
        :visible="showStartTrialModal"
        scope="group"
        @start-trial="startTrial"
        @hide="showStartTrialModal = false"
      />
    </template>
    <permissions-settings
      v-if="showPermissionsTable"
      :can-manage-secrets-manager="canManageSecretsManager"
      :full-path="fullPath"
      :context="context"
    />
    <gl-alert
      v-if="!isOpenbaoHealthy"
      variant="danger"
      :dismissible="false"
      class="gl-mb-4 gl-mt-4"
      data-testid="openbao-unhealthy-alert"
    >
      {{
        s__(
          'SecretsManager|Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
        )
      }}
    </gl-alert>
  </div>
  <!-- A failed status or entitlement query can leave the settings hidden
    (isActive stays false, the entitlement stays null), and the error must
    not vanish with them. The in-section copy above covers visible settings. -->
  <span
    v-else-if="hasError"
    class="gl-mt-2 gl-text-danger"
    data-testid="secret-manager-show-settings-error"
  >
    {{ errorMessage }}
  </span>
</template>
