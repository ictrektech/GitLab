<script>
export default {
  name: 'ParentWithAsyncCustomVModel',
  components: {
    // Reproduces the @vue/compat bug, see the skipped spec in hybrid_mode_spec.js
    // eslint-disable-next-line local-rules/no-async-component-with-model
    AsyncInputCustom: () => import('./async_input_custom.vue'),
  },
  data() {
    return {
      inputValue: '',
    };
  },
};
</script>
<template>
  <div>
    <async-input-custom v-model="inputValue" data-testid="async-input" />
    <span data-testid="output">{{ inputValue }}</span>
  </div>
</template>
