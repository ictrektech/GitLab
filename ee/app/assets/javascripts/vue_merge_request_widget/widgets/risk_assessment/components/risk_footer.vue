<script>
import ViewSessionButton from 'ee/ai/shared/widgets/view_session_button.vue';
import RiskStaleWarning from './risk_stale_warning.vue';

export default {
  name: 'RiskFooter',
  components: {
    RiskStaleWarning,
    ViewSessionButton,
  },
  props: {
    sessionId: {
      type: Number,
      required: false,
      default: null,
    },
    isStale: {
      type: Boolean,
      required: false,
      default: false,
    },
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
  <div
    class="gl-border-t gl-mt-3 gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3 gl-pt-3 first:gl-mt-0 first:gl-border-t-0 first:gl-pt-0"
    data-testid="risk-footer"
  >
    <risk-stale-warning
      v-if="isStale"
      class="gl-grow"
      :can-refresh="canRefresh"
      :is-submitting="isSubmitting"
      @refresh="$emit('refresh')"
    />
    <view-session-button
      v-if="sessionId"
      class="gl-ml-auto"
      size="small"
      :session-id="sessionId"
      data-testid="risk-duo-session-link"
    />
  </div>
</template>
