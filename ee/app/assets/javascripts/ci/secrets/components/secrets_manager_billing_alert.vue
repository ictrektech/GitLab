<script>
import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { I18N_OPEN_BETA_ALERT } from 'ee/ci/secrets/constants';

// Pre-paid-experience notice only; the paid experience has state-specific
// alerts (trial, beta transition, credit consumption) instead.
export default {
  name: 'SecretsManagerBillingAlert',
  components: {
    GlAlert,
    GlLink,
    GlSprintf,
  },
  GITLAB_CREDITS_DOCS_LINK: helpPagePath('subscriptions/gitlab_credits'),
  i18n: {
    openBetaAlert: I18N_OPEN_BETA_ALERT,
  },
};
</script>

<template>
  <gl-alert
    class="gl-mt-5"
    variant="warning"
    data-testid="open-beta-billing-alert"
    :dismissible="false"
    :title="$options.i18n.openBetaAlert.title"
  >
    <gl-sprintf :message="$options.i18n.openBetaAlert.description">
      <template #link="{ content }">
        <gl-link class="gl-inline-block" :href="$options.GITLAB_CREDITS_DOCS_LINK" target="_blank">
          {{ content }}
        </gl-link>
      </template>
    </gl-sprintf>
  </gl-alert>
</template>
