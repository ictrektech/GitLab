<script>
// An SFC, not a `template` string: Vue 2 traps property reads on the render proxy only for
// precompiled render functions, so only an SFC reproduces the warnings Jest's probes cause.
export default {
  name: 'VueRenderWarningsComponent',
  props: {
    readUndefinedProperty: {
      type: Boolean,
      required: false,
      default: false,
    },
    readRunWithContext: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return { definedProperty: 'defined' };
  },
};
</script>
<template>
  <div>
    <!-- eslint-disable-next-line vue/no-undef-properties -->
    <span v-if="readUndefinedProperty">{{ notDefinedAnywhere }}</span>
    <!-- eslint-disable-next-line vue/no-undef-properties -->
    <span v-else-if="readRunWithContext">{{ runWithContext }}</span>
    <span v-else>{{ definedProperty }}</span>
  </div>
</template>
