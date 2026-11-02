<script>
import { GlButton, GlTooltip } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { hideGlTooltip } from '~/vue_shared/utils/tooltips';

export default {
  name: 'ActionButton',
  components: {
    GlButton,
    GlTooltip,
  },
  props: {
    actionType: {
      type: String,
      required: true,
    },
    label: {
      type: String,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['click'],
  data() {
    return {
      buttonId: uniqueId(this.actionType),
    };
  },
  methods: {
    onClick() {
      hideGlTooltip(this, this.buttonId);
      this.$emit('click');
    },
  },
};
</script>

<template>
  <span>
    <gl-button
      v-bind="$attrs"
      :id="buttonId"
      :aria-label="label"
      :loading="isLoading"
      :icon="actionType"
      size="small"
      @click="onClick"
    />
    <gl-tooltip ref="tooltip" :target="buttonId" placement="top" triggers="hover">
      {{ label }}
    </gl-tooltip>
  </span>
</template>
