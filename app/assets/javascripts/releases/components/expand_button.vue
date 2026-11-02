<script>
import { GlButton } from '@gitlab/ui';

/**
 * Port of detail_behavior expand button.
 *
 * @example
 * <expand-button expand-label="Expand details" collapse-label="Collapse details">
 *   <template #expanded>
 *      Text goes here.
 *    </template>
 * </expand-button>
 */
export default {
  name: 'ExpandButton',
  components: {
    GlButton,
  },
  props: {
    expandLabel: {
      type: String,
      required: true,
    },
    collapseLabel: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      isCollapsed: true,
    };
  },
  destroyed() {
    this.isCollapsed = true;
  },
  methods: {
    onClick() {
      this.isCollapsed = !this.isCollapsed;
    },
  },
};
</script>
<template>
  <span>
    <gl-button
      :aria-label="isCollapsed ? expandLabel : collapseLabel"
      type="button"
      class="js-text-expander-prepend"
      icon="ellipsis_h"
      category="tertiary"
      @click="onClick"
    />
    <span v-if="isCollapsed"> <slot name="short"></slot> </span>
    <span v-if="!isCollapsed"> <slot name="expanded"></slot> </span>
  </span>
</template>
