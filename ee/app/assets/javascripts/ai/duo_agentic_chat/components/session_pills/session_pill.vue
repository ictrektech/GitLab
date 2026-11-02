<script>
import { capitalize } from 'lodash-es';
import { GlButton, GlIcon, GlTooltipDirective } from '@gitlab/ui';
import { CANCEL_SESSION_ICON } from 'ee/ai/duo_agents_platform/constants';
import { EventsTracker } from '../../observability/events_tracker';
import { getStatusDotClass } from './utils';

export default {
  name: 'SessionPill',
  components: {
    GlButton,
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    workflowId: {
      type: Number,
      required: true,
    },
    label: {
      type: String,
      required: true,
    },
    tooltip: {
      type: String,
      required: true,
    },
    status: {
      type: String,
      required: true,
    },
  },
  emits: ['click', 'cancel'],
  computed: {
    humanStatus() {
      return capitalize(this.status);
    },
    statusDotClass() {
      return getStatusDotClass(this.status);
    },
  },
  methods: {
    handleClick() {
      EventsTracker.trackClickThroughSessionPill({ workflowId: this.workflowId });
      this.$emit('click', this.workflowId);
    },
    handleCancel() {
      EventsTracker.trackCancelSessionFromSessionPill({ workflowId: this.workflowId });
      this.$emit('cancel', this.workflowId);
    },
  },
  CANCEL_SESSION_ICON,
};
</script>

<template>
  <div
    class="gl-group gl-border gl-relative gl-inline-flex gl-max-w-1/2 gl-items-center gl-rounded-full gl-border-default gl-bg-default hover:gl-bg-strong"
  >
    <!-- A percentage max-width doesn't count toward the pill's width, so on hover the title
         shrinks to fit the absolutely positioned cancel button and the pill keeps its width. -->
    <!-- eslint-disable tailwindcss/no-arbitrary-value -->
    <button
      v-gl-tooltip
      type="button"
      data-testid="session-pill"
      class="gl-flex gl-h-6 gl-min-w-0 gl-items-center gl-gap-2 gl-rounded-full gl-border-0 gl-bg-transparent gl-py-2 gl-pl-2 gl-pr-3 gl-text-sm gl-text-default focus-visible:gl-focus group-focus-within:gl-max-w-[calc(100%-1.5rem)] group-hover:gl-max-w-[calc(100%-1.5rem)]"
      :aria-label="`${label} ${humanStatus}`"
      :title="tooltip"
      @click="handleClick"
    >
      <gl-icon
        name="status_created_borderless"
        class="gl-shrink-0"
        :class="statusDotClass"
        data-testid="session-pill-status-dot"
      />
      <span class="gl-truncate">{{ label }}</span>
    </button>
    <!-- eslint-enable tailwindcss/no-arbitrary-value -->
    <gl-button
      v-gl-tooltip
      :title="s__('DuoAgentsPlatform|Cancel session')"
      :aria-label="s__('DuoAgentsPlatform|Cancel session')"
      :icon="$options.CANCEL_SESSION_ICON"
      size="small"
      category="tertiary"
      class="gl-absolute gl-right-0 gl-top-0 gl-hidden !gl-rounded-full group-focus-within:gl-inline-flex group-hover:gl-inline-flex"
      data-testid="session-pill-cancel-button"
      @click="handleCancel"
    />
  </div>
</template>
