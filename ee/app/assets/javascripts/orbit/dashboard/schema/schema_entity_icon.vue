<script>
import { defineComponent } from 'vue';
import { GlIcon } from '@gitlab/ui';
import { colorFromBackground } from '@gitlab/ui/src/utils/utils';
import { labelColorOptions } from '@gitlab/ui/src/utils/constants';

const SIZES = {
  sm: { class: 'gl-h-6 gl-w-6', icon: 12 },
  md: { class: 'gl-h-8 gl-w-8', icon: 16 },
  lg: { class: 'gl-h-11 gl-w-11', icon: 24 },
  xl: { class: 'gl-h-13 gl-w-13', icon: 32 },
};

// WCAG 1.4.11 asks for 3:1 contrast on graphics such as icons.
const ICON_CONTRAST_RATIO = 3;

export default defineComponent({
  name: 'SchemaEntityIcon',
  components: { GlIcon },
  props: {
    icon: {
      type: String,
      required: false,
      default: null,
    },
    color: {
      type: String,
      required: true,
    },
    size: {
      type: String,
      required: false,
      default: 'sm',
      validator: (value) => Object.keys(SIZES).includes(value),
    },
  },
  computed: {
    sizing() {
      return SIZES[this.size];
    },
    iconColorClass() {
      return colorFromBackground(this.color, ICON_CONTRAST_RATIO) === labelColorOptions.dark
        ? 'gl-text-neutral-950'
        : 'gl-text-neutral-0';
    },
  },
});
</script>

<template>
  <span
    class="gl-inline-flex gl-shrink-0 gl-items-center gl-justify-center gl-rounded-full"
    :class="[sizing.class, iconColorClass]"
    :style="{ backgroundColor: color }"
    aria-hidden="true"
  >
    <gl-icon v-if="icon" :name="icon" :size="sizing.icon" />
  </span>
</template>
