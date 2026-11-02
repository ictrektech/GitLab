<script>
import { GlButton, GlTooltip } from '@gitlab/ui';

export default {
  name: 'DeleteButton',
  components: {
    GlButton,
    GlTooltip,
  },
  props: {
    title: {
      type: String,
      required: true,
    },
    tooltipTitle: {
      type: String,
      required: true,
    },
    disabled: {
      type: Boolean,
      default: false,
      required: false,
    },
    tooltipDisabled: {
      type: Boolean,
      default: false,
      required: false,
    },
  },
  emits: ['delete'],
};
</script>

<template>
  <div ref="deleteImageButton">
    <gl-button
      :disabled="disabled"
      :title="title"
      :aria-label="title"
      category="tertiary"
      icon="remove"
      @click="$emit('delete')"
    />
    <gl-tooltip :target="() => $refs.deleteImageButton" :disabled="tooltipDisabled" placement="top">
      {{ tooltipTitle }}
    </gl-tooltip>
  </div>
</template>
