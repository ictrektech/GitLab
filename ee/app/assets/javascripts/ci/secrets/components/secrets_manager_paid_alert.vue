<script>
import { GlAlert, GlLink } from '@gitlab/ui';
import { SECRETS_MANAGER_PAID_ALERT } from '../constants';

export default {
  name: 'SecretsManagerPaidAlert',
  components: {
    GlAlert,
    GlLink,
  },
  props: {
    enabled: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  computed: {
    description() {
      return this.enabled
        ? SECRETS_MANAGER_PAID_ALERT.description
        : SECRETS_MANAGER_PAID_ALERT.disabledDescription;
    },
  },
  SECRETS_MANAGER_PAID_ALERT,
};
</script>
<template>
  <gl-alert
    class="gl-mt-5"
    variant="info"
    :dismissible="false"
    data-testid="secrets-manager-paid-alert"
  >
    {{ description }}
    <gl-link
      class="gl-inline-block"
      :href="$options.SECRETS_MANAGER_PAID_ALERT.link"
      target="_blank"
    >
      {{ $options.SECRETS_MANAGER_PAID_ALERT.linkText }}
    </gl-link>
  </gl-alert>
</template>
