<script>
import { GlFormCheckbox } from '@gitlab/ui';

export default {
  name: 'DuoTokenUsageTrackingForm',
  components: {
    GlFormCheckbox,
  },
  inject: ['duoTokenUsageTrackingEnabled'],
  props: {
    disabledCheckbox: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  data() {
    return {
      trackingEnabled: this.duoTokenUsageTrackingEnabled,
    };
  },
  methods: {
    checkboxChanged() {
      this.$emit('change', this.trackingEnabled);
    },
  },
};
</script>

<template>
  <div>
    <h5>{{ s__('AiPowered|Record GitLab Duo Non-Agentic Chat token usage') }}</h5>
    <gl-form-checkbox
      v-model="trackingEnabled"
      data-testid="duo-token-usage-tracking-checkbox"
      :disabled="disabledCheckbox"
      @change="checkboxChanged"
    >
      <span>{{
        s__(
          'AiPowered|Record the input and output tokens that each GitLab Duo Non-Agentic Chat request uses, by user and model. Turning off this setting stops new records. Existing records are kept.',
        )
      }}</span>
    </gl-form-checkbox>
  </div>
</template>
