<script>
import { GlAlert, GlButton, GlLink, GlPopover, GlSprintf } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import { localeDateFormat } from '~/lib/utils/datetime/locale_dateformat';
import { MILLISECONDS_IN_DAY } from '~/lib/utils/datetime/date_calculation_utility';
import {
  BETA_CUTOFF_DATE,
  I18N_SETUP_IN_PROGRESS,
  SECRETS_MANAGER_BILLING_DOCS_LINK,
} from '../constants';

// Shown to beta-cohort namespaces while the entitlement is still
// trial_eligible. The parent decides where it mounts and whether the CTAs
// render (`showCta`), since who may convert differs per page.
//
// Two variants depending on `betaProgramEnded`:
//   - false (grace window): warning alert nudging users to convert
//     before their direct-read access ends.
//   - true (post grace):   danger alert -- Secrets Manager is now
//     disabled until the user enables it with credits or starts a trial.
export default {
  name: 'SecretsBetaTransitionAlert',
  components: {
    GlAlert,
    GlButton,
    GlLink,
    GlPopover,
    GlSprintf,
  },
  props: {
    isBeta: {
      type: Boolean,
      required: false,
      default: false,
    },
    // Backend sets this to true now that the beta grace period is over.
    betaProgramEnded: {
      type: Boolean,
      required: false,
      default: false,
    },
    isTrialEligible: {
      type: Boolean,
      required: false,
      default: false,
    },
    isCheckingEntitlement: {
      type: Boolean,
      required: false,
      default: false,
    },
    isEnablingAddOn: {
      type: Boolean,
      required: false,
      default: false,
    },
    isTrialOnboarding: {
      type: Boolean,
      required: false,
      default: false,
    },
    showCta: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['start-trial', 'enable-add-on'],
  SECRETS_MANAGER_BILLING_DOCS_LINK,
  I18N_SETUP_IN_PROGRESS,
  computed: {
    showAlert() {
      return this.isBeta && this.isTrialEligible;
    },
    variant() {
      return this.betaProgramEnded ? 'danger' : 'warning';
    },
    formattedCutoff() {
      return localeDateFormat.asDateTimeFull.format(new Date(BETA_CUTOFF_DATE));
    },
    // Humanized countdown to BETA_CUTOFF_DATE. Days when >=24h remain;
    // hours otherwise. Clamped to a minimum of "1 hour" so the copy stays
    // sensible even if the launch is delayed past the cutoff.
    timeRemainingText() {
      const MILLISECONDS_IN_HOUR = MILLISECONDS_IN_DAY / 24;
      const msRemaining = new Date(BETA_CUTOFF_DATE).getTime() - Date.now();

      if (msRemaining >= MILLISECONDS_IN_DAY) {
        const days = Math.floor(msRemaining / MILLISECONDS_IN_DAY);
        return sprintf(
          n__(
            'SecretsManager|Your free beta ends in %{count} day.',
            'SecretsManager|Your free beta ends in %{count} days.',
            days,
          ),
          { count: days },
        );
      }

      const hours = Math.max(1, Math.floor(msRemaining / MILLISECONDS_IN_HOUR));
      return sprintf(
        n__(
          'SecretsManager|Your free beta ends in %{count} hour.',
          'SecretsManager|Your free beta ends in %{count} hours.',
          hours,
        ),
        { count: hours },
      );
    },
    title() {
      if (this.betaProgramEnded) {
        return s__(
          'SecretsManager|Your Beta period is over and GitLab Secrets Manager has been disabled',
        );
      }

      return this.timeRemainingText;
    },
    description() {
      return this.betaProgramEnded
        ? s__(
            'SecretsManager|Enable with GitLab Credits to continue using GitLab Secrets Manager and avoid service disruptions. %{linkStart}How does GitLab Secrets Manager use GitLab Credits?%{linkEnd}',
          )
        : sprintf(
            s__(
              'SecretsManager|After %{cutoffDate}, GitLab Secrets Manager usage will require GitLab Credits. To avoid a service disruption, enable GitLab Secrets Manager with GitLab Credits. %{linkStart}How does GitLab Secrets Manager use GitLab Credits?%{linkEnd}',
            ),
            { cutoffDate: this.formattedCutoff },
          );
    },
  },
};
</script>
<template>
  <gl-alert
    v-if="showAlert"
    :variant="variant"
    :title="title"
    :dismissible="false"
    class="gl-my-5"
    data-testid="secrets-beta-transition-alert"
  >
    <gl-sprintf :message="description">
      <template #link="{ content }">
        <gl-link :href="$options.SECRETS_MANAGER_BILLING_DOCS_LINK" target="_blank">{{
          content
        }}</gl-link>
      </template>
    </gl-sprintf>
    <template v-if="showCta" #actions>
      <gl-button
        ref="enableAddOnButton"
        variant="confirm"
        category="primary"
        :loading="isEnablingAddOn || isCheckingEntitlement"
        :disabled="isTrialOnboarding"
        class="gl-mr-3"
        data-testid="beta-alert-enable-add-on"
        @click="$emit('enable-add-on')"
      >
        {{ s__('SecretsManager|Enable with GitLab Credits') }}
      </gl-button>
      <gl-button
        ref="startTrialButton"
        variant="confirm"
        category="secondary"
        :loading="isTrialOnboarding"
        :disabled="isEnablingAddOn || isCheckingEntitlement"
        data-testid="beta-alert-start-trial"
        @click="$emit('start-trial')"
      >
        {{ __('Start 30-day trial') }}
      </gl-button>
      <gl-popover
        :target="() => $refs.enableAddOnButton"
        :show="isEnablingAddOn"
        :title="s__('SecretsManager|Enabling GitLab Secrets Manager')"
        placement="bottom"
        triggers="manual"
      >
        {{ $options.I18N_SETUP_IN_PROGRESS }}
      </gl-popover>
      <gl-popover
        :target="() => $refs.startTrialButton"
        :show="isTrialOnboarding"
        :title="s__('SecretsManager|Enabling GitLab Secrets Manager trial')"
        placement="bottom"
        triggers="manual"
      >
        {{ $options.I18N_SETUP_IN_PROGRESS }}
      </gl-popover>
    </template>
  </gl-alert>
</template>
