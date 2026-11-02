<script>
import { GlFormGroup, GlSegmentedControl } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  ENFORCEMENT_ENFORCED,
  ENFORCEMENT_WARN,
  ENFORCEMENT_MODE_DESCRIPTIONS,
} from '../constants';

export default {
  name: 'EnforcementModeControl',
  components: { GlFormGroup, GlSegmentedControl },
  i18n: {
    label: s__('SecurityOrchestration|How should it act?'),
  },
  staticOptions: [
    { value: ENFORCEMENT_WARN, text: s__('SecurityOrchestration|Warn') },
    { value: ENFORCEMENT_ENFORCED, text: s__('SecurityOrchestration|Enforce') },
  ],
  props: {
    enforcementType: {
      type: String,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  computed: {
    description() {
      return ENFORCEMENT_MODE_DESCRIPTIONS[this.enforcementType];
    },
    // GlSegmentedControl has no top-level `disabled` prop; only individual options can be
    // disabled, so the control-wide `disabled` prop is applied to every option here.
    options() {
      return this.$options.staticOptions.map((option) => ({ ...option, disabled: this.disabled }));
    },
  },
};
</script>

<template>
  <gl-form-group :label="$options.i18n.label" :disabled="disabled" class="gl-mb-0">
    <gl-segmented-control
      :value="enforcementType"
      :options="options"
      @input="$emit('change', $event)"
    />
    <p class="gl-mb-0 gl-mt-3 gl-text-subtle">{{ description }}</p>
  </gl-form-group>
</template>
