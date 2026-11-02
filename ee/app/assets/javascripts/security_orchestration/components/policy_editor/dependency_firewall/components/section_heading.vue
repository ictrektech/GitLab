<script>
export default {
  name: 'SectionHeading',
  props: {
    title: {
      type: String,
      required: true,
    },
    subtitle: {
      type: String,
      required: false,
      default: '',
    },
  },
};
</script>

<template>
  <div class="gl-mb-3 gl-mt-7">
    <h4 class="gl-heading-4 gl-mb-1">{{ title }}</h4>
    <p v-if="subtitle" class="gl-mb-0 gl-text-subtle">{{ subtitle }}</p>
  </div>
</template>
