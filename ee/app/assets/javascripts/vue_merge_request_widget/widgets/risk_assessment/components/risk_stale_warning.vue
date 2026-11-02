<script>
import { GlButton } from '@gitlab/ui';

export default {
  name: 'RiskStaleWarning',
  components: {
    GlButton,
  },
  props: {
    canRefresh: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSubmitting: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['refresh'],
};
</script>

<template>
  <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
    <p class="gl-mb-0 gl-text-warning" data-testid="risk-stale-warning">
      {{
        s__(
          'RiskAssessment|New commits were pushed after this assessment and it reflects an earlier version of the changes.',
        )
      }}
    </p>

    <gl-button
      v-if="canRefresh"
      category="tertiary"
      :icon="isSubmitting ? '' : 'retry'"
      size="small"
      :loading="isSubmitting"
      data-testid="risk-refresh-button"
      @click="$emit('refresh')"
    >
      {{ s__('RiskAssessment|Refresh') }}
    </gl-button>
  </div>
</template>
