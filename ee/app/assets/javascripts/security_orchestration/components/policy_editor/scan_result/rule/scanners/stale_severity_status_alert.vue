<script>
import { GlAlert } from '@gitlab/ui';
import { omit } from 'lodash-es';
import { s__ } from '~/locale';

export default {
  i18n: {
    message: s__(
      'SecurityOrchestration|This scanner has severity or status values that are not shown here and override global settings. Remove the values to use global settings instead.',
    ),
    removeButton: s__('SecurityOrchestration|Remove scanner values'),
  },
  name: 'StaleSeverityStatusAlert',
  components: {
    GlAlert,
  },
  props: {
    scanner: {
      type: Object,
      required: true,
    },
  },
  emits: ['changed'],
  computed: {
    hasStaleValues() {
      return 'severity_levels' in this.scanner || 'vulnerability_states' in this.scanner;
    },
  },
  methods: {
    removeStaleValues() {
      this.$emit('changed', omit(this.scanner, ['severity_levels', 'vulnerability_states']));
    },
  },
};
</script>

<template>
  <gl-alert
    v-if="hasStaleValues"
    class="gl-mt-4"
    variant="warning"
    :dismissible="false"
    :primary-button-text="$options.i18n.removeButton"
    data-testid="stale-severity-status-alert"
    @primary-action="removeStaleValues"
  >
    {{ $options.i18n.message }}
  </gl-alert>
</template>
