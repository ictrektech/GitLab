<script>
import { GlBadge } from '@gitlab/ui';
import { getAgentStatusIconVariant } from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AgentStatusBadge',
  components: {
    GlBadge,
  },
  props: {
    status: {
      required: true,
      type: String,
    },
    humanStatus: {
      required: true,
      type: String,
    },
  },
  computed: {
    badge() {
      return getAgentStatusIconVariant(this.status);
    },
    variant() {
      return this.badge.variant === 'subtle' ? 'neutral' : this.badge.variant;
    },
  },
};
</script>

<template>
  <gl-badge :icon="badge.icon" icon-size="sm" :variant="variant">
    {{ humanStatus }}
  </gl-badge>
</template>
