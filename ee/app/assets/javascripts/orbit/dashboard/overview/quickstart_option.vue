<script>
import { defineComponent } from 'vue';
import { GlIcon } from '@gitlab/ui';

export default defineComponent({
  name: 'QuickstartOption',
  components: { GlIcon },
  props: {
    icon: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      required: true,
    },
  },
});
</script>

<template>
  <li class="gl-flex gl-min-w-0 gl-gap-3">
    <gl-icon :name="icon" :size="24" variant="subtle" class="gl-shrink-0" />
    <div class="gl-flex gl-min-w-0 gl-flex-col gl-gap-3">
      <h3 class="gl-heading-5 gl-m-0">{{ title }}</h3>
      <span class="gl-text-subtle" data-testid="quickstart-option-description">{{
        description
      }}</span>
      <slot></slot>
    </div>
  </li>
</template>
