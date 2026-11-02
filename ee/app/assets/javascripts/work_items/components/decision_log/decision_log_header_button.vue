<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { n__, s__ } from '~/locale';

export default {
  name: 'DecisionLogHeaderButton',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    count: {
      type: Number,
      required: false,
      default: 0,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['open', 'close'],
  computed: {
    hasCount() {
      return this.count > 0;
    },
    ariaLabel() {
      if (!this.hasCount) return s__('WorkItemDecisionLog|Decision log');

      return n__(
        'WorkItemDecisionLog|Decision log, %d decision',
        'WorkItemDecisionLog|Decision log, %d decisions',
        this.count,
      );
    },
  },
  methods: {
    onClick() {
      this.$emit(this.isPanelOpen ? 'close' : 'open');
    },
  },
};
</script>

<template>
  <gl-button
    v-gl-tooltip.bottom="s__('WorkItemDecisionLog|Decision log')"
    category="tertiary"
    size="small"
    icon="log"
    :selected="isPanelOpen"
    :aria-label="ariaLabel"
    :aria-pressed="String(isPanelOpen)"
    data-testid="decision-log-header-button"
    :class="{ '!gl-px-2': hasCount }"
    @click="onClick"
  >
    <!-- #default lets GlButton's cached hasIconOnly track hasCount, so the count shows once it goes above 0. -->
    <!-- Without it, only a remount updates the button, which detaches the onboarding popover. -->
    <template #default>
      <span v-if="hasCount" class="gl-text-sm gl-font-semibold" data-testid="decision-log-count">
        {{ count }}
      </span>
    </template>
  </gl-button>
</template>
