<script>
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';

export default {
  name: 'DastProfileSummaryCell',
  mixins: [glSlotsMixin],
  props: {
    label: {
      type: String,
      required: true,
    },
    value: {
      type: String,
      required: false,
      default: null,
    },
  },
};
</script>

<template>
  <div v-if="value || glSlots().default" class="row gl-my-2">
    <div class="gl-col-md-5 !gl-pr-0">{{ label }}:</div>
    <div class="gl-col-md-7">
      <strong v-if="value">{{ value }}</strong>
      <slot v-else></slot>
    </div>
  </div>
</template>
