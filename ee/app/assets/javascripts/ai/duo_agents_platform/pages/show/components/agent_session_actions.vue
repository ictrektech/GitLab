<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  AGENT_PLATFORM_CANCELABLE_STATUSES,
  CANCEL_SESSION_ICON,
  RETRY_SESSION_ICON,
} from 'ee/ai/duo_agents_platform/constants';

export default {
  name: 'AgentSessionActions',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    status: {
      type: String,
      required: false,
      default: null,
    },
    canUpdateWorkflow: {
      type: Boolean,
      required: false,
      default: false,
    },
    canRestartWorkflow: {
      type: Boolean,
      required: false,
      default: false,
    },
    isRetrying: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSidePanel: {
      type: Boolean,
      required: false,
      default: false,
    },
    showDetailsToggle: {
      type: Boolean,
      required: false,
      default: false,
    },
    detailsExpanded: {
      type: Boolean,
      required: false,
      default: true,
    },
    detailsDrawerId: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['cancel-session', 'retry-session', 'toggle-details'],
  computed: {
    canCancelSession() {
      return AGENT_PLATFORM_CANCELABLE_STATUSES.includes(this.status);
    },
    cancelSessionLabel() {
      return s__('DuoAgentsPlatform|Cancel session');
    },
    cancelTooltip() {
      if (!this.canUpdateWorkflow) {
        return s__('DuoAgentsPlatform|You do not have permission to cancel this session.');
      }
      return this.isSidePanel ? this.cancelSessionLabel : '';
    },
    canRetrySession() {
      return Boolean(this.glFeatures.dapSessionRestarts) && this.canRestartWorkflow;
    },
    retrySessionLabel() {
      return s__('DuoAgentPlatform|Retry session');
    },
  },
  CANCEL_SESSION_ICON,
  RETRY_SESSION_ICON,
};
</script>
<template>
  <div class="gl-flex gl-items-center gl-gap-3">
    <template v-if="canCancelSession">
      <gl-button
        v-if="isSidePanel"
        v-gl-tooltip
        :icon="$options.CANCEL_SESSION_ICON"
        size="small"
        :title="cancelTooltip"
        :aria-label="cancelSessionLabel"
        :disabled="!canUpdateWorkflow"
        data-testid="cancel-session-icon-button"
        @click="$emit('cancel-session')"
      />
      <gl-button
        v-else
        v-gl-tooltip
        category="secondary"
        variant="danger"
        :title="cancelTooltip"
        :disabled="!canUpdateWorkflow"
        data-testid="cancel-session-button"
        @click="$emit('cancel-session')"
      >
        {{ cancelSessionLabel }}
      </gl-button>
    </template>
    <template v-if="canRetrySession">
      <gl-button
        v-if="isSidePanel"
        v-gl-tooltip
        :icon="$options.RETRY_SESSION_ICON"
        size="small"
        :title="retrySessionLabel"
        :aria-label="retrySessionLabel"
        :loading="isRetrying"
        data-testid="retry-session-icon-button"
        @click="$emit('retry-session')"
      />
      <gl-button
        v-else
        category="secondary"
        variant="confirm"
        :loading="isRetrying"
        data-testid="retry-session-button"
        @click="$emit('retry-session')"
      >
        {{ retrySessionLabel }}
      </gl-button>
    </template>
    <gl-button
      v-if="showDetailsToggle"
      v-gl-tooltip
      icon="chevron-double-lg-left"
      :title="s__('DuoAgentPlatform|Session details')"
      :aria-label="s__('DuoAgentPlatform|Session details')"
      :aria-expanded="detailsExpanded.toString()"
      :aria-controls="detailsDrawerId"
      data-testid="toggle-session-details-button"
      @click="$emit('toggle-details')"
    />
  </div>
</template>
