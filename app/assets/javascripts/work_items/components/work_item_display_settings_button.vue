<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'WorkItemDisplaySettingsButton',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    selected: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['click'],
};
</script>

<template>
  <div>
    <gl-button
      v-gl-tooltip
      icon="preferences"
      :title="__('Display')"
      :aria-label="__('Display')"
      :selected="selected"
      data-testid="display-settings-icon-button"
      @click="$emit('click')"
    />
  </div>
</template>
