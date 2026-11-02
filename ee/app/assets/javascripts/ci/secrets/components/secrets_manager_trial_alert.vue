<script>
import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import { getDayDifference } from '~/lib/utils/datetime_utility';
import {
  BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED,
  ENTITLEMENT_STATE_BLOCKED,
  ENTITLEMENT_STATE_TRIAL,
  I18N_TRIAL_ALERT,
  SECRETS_MANAGER_BILLING_DOCS_LINK,
  TRIAL_ALERT_OPTIONS_BLOCKED,
  TRIAL_ALERT_OPTIONS_TRIAL_REQUIRED,
  TRIAL_CREDITS_LOW_PERCENTAGE,
  WRITE_DENIAL_REASON_TRIAL_REQUIRED,
} from '../constants';

export default {
  name: 'SecretsManagerTrialAlert',
  components: {
    GlAlert,
    GlLink,
    GlSprintf,
  },
  SECRETS_MANAGER_BILLING_DOCS_LINK,
  inject: {
    isOfflineLicense: { default: false },
    subscriptionsUrl: { from: 'subscriptionsUrl' },
  },
  props: {
    entitlement: {
      type: Object,
      required: false,
      default: null,
    },
    // Readable by everyone who can open the page, unlike the entitlement.
    writeDenialReason: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    creditsRemaining() {
      return this.entitlement.creditsRemaining;
    },
    creditsRemainingPercentage() {
      const { creditsTotal } = this.entitlement;
      if (this.creditsRemaining == null || !creditsTotal) {
        return 0;
      }

      return Math.floor((this.creditsRemaining / creditsTotal) * 100);
    },
    isCreditsLow() {
      return this.creditsRemainingPercentage < TRIAL_CREDITS_LOW_PERCENTAGE;
    },
    trialDaysRemaining() {
      if (!this.entitlement.trialExpiresAt) {
        return null;
      }

      return getDayDifference(new Date(), new Date(this.entitlement.trialExpiresAt));
    },
    alertOptions() {
      // With the entitlement, the beta transition alert already explains this.
      if (this.writeDenialReason === WRITE_DENIAL_REASON_TRIAL_REQUIRED) {
        return this.entitlement ? null : TRIAL_ALERT_OPTIONS_TRIAL_REQUIRED;
      }

      if (this.writeDenialReason) {
        return this.blockedAlertOptions(this.writeDenialReason);
      }

      if (!this.entitlement) {
        return null;
      }

      const { state, onDemandEnabled, blockedReason } = this.entitlement;

      if (state === ENTITLEMENT_STATE_BLOCKED) {
        return this.blockedAlertOptions(blockedReason);
      }

      if (state === ENTITLEMENT_STATE_TRIAL) {
        // The trial label is date-based, so it survives an empty trial wallet.
        // With on-demand on, usage is already billed to GitLab Credits, same as PAID.
        if (onDemandEnabled && this.creditsRemaining === 0) {
          return null;
        }

        return {
          variant: this.isCreditsLow ? 'danger' : 'warning',
          title: this.trialTitle,
          description: onDemandEnabled
            ? I18N_TRIAL_ALERT.descriptionOnDemandEnabled
            : I18N_TRIAL_ALERT.descriptionOnDemandDisabled,
        };
      }

      return null;
    },
    trialTitle() {
      const days = this.trialDaysRemaining;

      if (this.isCreditsLow) {
        if (days === null) {
          return sprintf(
            s__('SecretsManagerTrial|Less than 10%% of GitLab Secrets Manager trial credits left.'),
          );
        }

        if (days <= 0) {
          return sprintf(
            s__(
              'SecretsManagerTrial|Less than 10%% of GitLab Secrets Manager trial credits left. If not used up, they expire today.',
            ),
          );
        }

        return sprintf(
          n__(
            'SecretsManagerTrial|Less than 10%% of GitLab Secrets Manager trial credits left. If not used up, they expire in %{days} day.',
            'SecretsManagerTrial|Less than 10%% of GitLab Secrets Manager trial credits left. If not used up, they expire in %{days} days.',
            days,
          ),
          { days },
        );
      }

      const percent = this.creditsRemainingPercentage;

      if (days === null) {
        return sprintf(
          s__('SecretsManagerTrial|%{percent}%% of GitLab Secrets Manager trial credits left.'),
          { percent },
        );
      }

      if (days <= 0) {
        return sprintf(
          s__(
            'SecretsManagerTrial|%{percent}%% of GitLab Secrets Manager trial credits left. If not used up, they expire today.',
          ),
          { percent },
        );
      }

      return sprintf(
        n__(
          'SecretsManagerTrial|%{percent}%% of GitLab Secrets Manager trial credits left. If not used up, they expire in %{days} day.',
          'SecretsManagerTrial|%{percent}%% of GitLab Secrets Manager trial credits left. If not used up, they expire in %{days} days.',
          days,
        ),
        { percent, days },
      );
    },
  },
  methods: {
    // An air-gapped instance can't enable on-demand billing; only a new license unblocks it.
    blockedAlertOptions(reason) {
      const options = TRIAL_ALERT_OPTIONS_BLOCKED[reason] ?? null;

      if (reason === BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED && this.isOfflineLicense) {
        return { ...options, description: I18N_TRIAL_ALERT.descriptionOfflineLicense };
      }

      return options;
    },
  },
};
</script>
<template>
  <gl-alert
    v-if="alertOptions"
    :variant="alertOptions.variant"
    :title="alertOptions.title"
    :dismissible="false"
    class="gl-my-5"
    data-testid="secrets-trial-alert"
  >
    <gl-sprintf :message="alertOptions.description">
      <template #link="{ content }">
        <gl-link :href="$options.SECRETS_MANAGER_BILLING_DOCS_LINK" target="_blank">{{
          content
        }}</gl-link>
      </template>
      <template #portalLink="{ content }">
        <gl-link :href="subscriptionsUrl" target="_blank">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
  </gl-alert>
</template>
