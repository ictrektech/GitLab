<script>
import { GlLink } from '@gitlab/ui';
import { s__ } from '~/locale';
import { ENABLE_SCANNERS_ROUTE, SECURITY_CONFIGURATION_PATH } from '../constants';

export default {
  name: 'EnableScannersLink',
  components: {
    GlLink,
  },
  props: {
    webPath: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    configurationPath() {
      if (!this.webPath) return null;
      return `${this.webPath}${SECURITY_CONFIGURATION_PATH}`;
    },
    enableScannersPath() {
      if (!this.configurationPath) return null;
      return `${this.configurationPath}${ENABLE_SCANNERS_ROUTE}`;
    },
  },
  i18n: {
    enableScanners: s__('SecurityInventory|Enable scanners'),
  },
};
</script>

<template>
  <gl-link
    v-if="enableScannersPath"
    :href="enableScannersPath"
    class="gl-opacity-0 gl-transition-opacity focus:gl-opacity-10 group-hover:gl-opacity-10"
    data-testid="enable-scanners-link"
    @click.stop
  >
    {{ $options.i18n.enableScanners }}
  </gl-link>
</template>
