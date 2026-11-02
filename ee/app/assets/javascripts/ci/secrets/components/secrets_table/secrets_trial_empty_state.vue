<script>
import { GlButton, GlCard, GlIcon, GlLink, GlPopover } from '@gitlab/ui';
import TrialIllustrationSvg from '@gitlab/svgs/dist/illustrations/empty-state/empty-secrets-md.svg?url';
import { helpPagePath } from '~/helpers/help_page_helper';
import { s__ } from '~/locale';
import {
  I18N_SECRETS_EMPTY_STATE,
  I18N_SETUP_IN_PROGRESS,
  SECRETS_MANAGER_BILLING_DOCS_LINK,
  SECRETS_MANAGER_PAID_ALERT,
} from 'ee/ci/secrets/constants';

export default {
  name: 'SecretsTrialEmptyState',
  components: {
    GlButton,
    GlCard,
    GlIcon,
    GlLink,
    GlPopover,
  },
  inject: {
    canEnableAddOn: { default: false },
    canStartTrial: { default: false },
    isOpenbaoHealthy: { default: true },
    isSaas: { default: false },
    isTrialOnboarding: { default: false },
    isEnablingAddOn: { default: false },
    isCheckingEntitlement: { default: false },
  },
  emits: ['start-trial', 'enable-add-on'],
  computed: {
    showConfigureOpenbaoLink() {
      return !this.isOpenbaoHealthy && !this.isSaas;
    },
    hasTrialActions() {
      return this.canStartTrial || this.canEnableAddOn;
    },
  },
  TrialIllustrationSvg,
  CONFIGURE_OPENBAO_LINK: helpPagePath('administration/secrets_manager/_index'),
  SECRETS_MANAGER_BILLING_DOCS_LINK,
  SECRETS_MANAGER_TRIAL_DOCS_LINK: helpPagePath('ci/secrets/secrets_manager/credit_usage', {
    anchor: 'start-a-trial',
  }),
  creditConsumptionAlert: SECRETS_MANAGER_PAID_ALERT,
  i18n: {
    ...I18N_SECRETS_EMPTY_STATE,
    enablingTrialTitle: s__('SecretsManager|Enabling GitLab Secrets Manager trial'),
    enablingTrialDescription: I18N_SETUP_IN_PROGRESS,
    enablingAddOnTitle: s__('SecretsManager|Enabling GitLab Secrets Manager'),
    billingFooter: s__(
      'SecretsManager|GitLab Secrets Manager consumes GitLab Credits to store and fetch secrets.',
    ),
  },
};
</script>
<template>
  <gl-card body-class="gl-flex gl-flex-col gl-items-center gl-text-center gl-py-8">
    <template #header>
      <strong>{{ s__('SecretsManager|Secrets') }}</strong>
      <p data-testid="group-subheader" class="gl-mb-0 gl-text-subtle">
        {{ $options.i18n.groupSubheader }}
      </p>
    </template>
    <!-- eslint-disable-next-line @gitlab/vue-require-i18n-attribute-strings -->
    <img :src="$options.TrialIllustrationSvg" alt="" class="gl-mb-4" />
    <h2 class="gl-text-size-h2">
      {{ $options.i18n.title }}
    </h2>
    <p class="gl-mx-auto gl-mb-5 gl-max-w-75">
      {{ $options.i18n.description }}
    </p>
    <gl-button
      v-if="showConfigureOpenbaoLink"
      :href="$options.CONFIGURE_OPENBAO_LINK"
      target="_blank"
      rel="noopener noreferrer"
      data-testid="configure-openbao-link"
    >
      {{ s__('SecretsManager|Configure OpenBao') }}
    </gl-button>
    <div v-if="isOpenbaoHealthy" class="gl-flex gl-flex-col gl-items-center gl-gap-4">
      <div v-if="hasTrialActions" class="gl-flex gl-items-center gl-gap-3">
        <gl-button
          v-if="canEnableAddOn"
          ref="enableAddOnButton"
          variant="confirm"
          category="primary"
          :loading="isEnablingAddOn || isCheckingEntitlement"
          :disabled="isTrialOnboarding"
          data-testid="enable-add-on-button"
          @click="$emit('enable-add-on')"
        >
          {{ s__('SecretsManager|Enable with GitLab Credits') }}
        </gl-button>
        <gl-button
          v-if="canStartTrial"
          ref="startTrialButton"
          variant="confirm"
          category="secondary"
          :loading="isTrialOnboarding"
          :disabled="isEnablingAddOn || isCheckingEntitlement"
          data-testid="start-trial-button"
          @click="$emit('start-trial')"
        >
          {{ __('Start 30-day trial') }}
        </gl-button>
      </div>
      <p v-else class="gl-mb-0" data-testid="trial-contact-owner">
        {{
          s__(
            'SecretsManager|Contact your group owner or instance administrator to start a trial or enable with GitLab Credits.',
          )
        }}
      </p>
      <gl-link
        :href="$options.SECRETS_MANAGER_TRIAL_DOCS_LINK"
        target="_blank"
        rel="noopener noreferrer"
        data-testid="learn-more-trial-link"
      >
        {{ s__('SecretsManager|Learn more about the 30-day trial') }}
      </gl-link>
    </div>
    <gl-popover
      v-if="canStartTrial"
      :target="() => $refs.startTrialButton"
      :show="isTrialOnboarding"
      :title="$options.i18n.enablingTrialTitle"
      placement="bottom"
      triggers="manual"
    >
      {{ $options.i18n.enablingTrialDescription }}
    </gl-popover>
    <gl-popover
      v-if="canEnableAddOn"
      :target="() => $refs.enableAddOnButton"
      :show="isEnablingAddOn"
      :title="$options.i18n.enablingAddOnTitle"
      placement="bottom"
      triggers="manual"
    >
      {{ $options.i18n.enablingTrialDescription }}
    </gl-popover>
    <p data-testid="billing-info" class="gl-mb-0 gl-mt-8">
      <gl-icon name="information-o" variant="info" class="gl-mr-2" />
      {{ $options.i18n.billingFooter }}
      <gl-link :href="$options.SECRETS_MANAGER_BILLING_DOCS_LINK" target="_blank">
        {{ $options.creditConsumptionAlert.linkText }}
      </gl-link>
    </p>
  </gl-card>
</template>
