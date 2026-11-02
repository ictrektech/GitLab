<script>
import SecurityConfigurationApp from '~/security_configuration/components/app.vue';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';

export default {
  name: 'SecurityConfigurationAppEE',
  components: { SecurityConfigurationApp },
  mixins: [glFeatureFlagsMixin()],
  provide() {
    return {
      vulnerabilityArchivesAvailable: Boolean(this.glFeatures.vulnerabilityArchival),
      refTrackingAvailable: Boolean(this.glFeatures.vulnerabilitiesAcrossContexts),
    };
  },
  inheritAttrs: false,
  props: SecurityConfigurationApp.props,
};
</script>

<template>
  <security-configuration-app v-bind="$props" />
</template>
