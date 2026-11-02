<script>
import { GlButton, GlLink, GlTooltipDirective } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import { formatAgentFlowTitle, formatAgentFlowTitleTooltip } from 'ee/ai/duo_agents_platform/utils';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';

export default {
  name: 'BoardCardSessionBadgeRow',
  components: {
    AgentStatusIcon,
    GlButton,
    GlLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    session: {
      type: Object,
      required: true,
    },
  },
  emits: ['show-session'],
  computed: {
    sessionNumericId() {
      return getIdFromGraphQLId(this.session.id);
    },
    sessionUrl() {
      const fullPath = this.session.project?.fullPath;
      return fullPath ? projectAutomateAgentSessionPath(fullPath, this.sessionNumericId) : null;
    },
    sessionTitle() {
      return formatAgentFlowTitle(this.session.title, this.session.workflowDefinition);
    },
    sessionTooltip() {
      return formatAgentFlowTitleTooltip(this.sessionTitle, this.sessionNumericId);
    },
  },
  methods: {
    onSessionClick(event) {
      if (event.metaKey || event.ctrlKey || event.shiftKey) return;

      event.preventDefault();
      this.$emit('show-session', this.session);
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-items-center gl-gap-2 gl-py-2 first-of-type:gl-pt-0"
    data-testid="popover-session-row"
  >
    <agent-status-icon :status="session.status" class="gl-mx-1 gl-shrink-0" />
    <gl-link
      v-if="sessionUrl"
      v-gl-tooltip
      :href="sessionUrl"
      :title="sessionTooltip"
      class="gl-text-sm gl-font-bold"
      data-testid="popover-session-link"
      @click="onSessionClick"
    >
      {{ sessionNumericId }}
    </gl-link>
    <gl-button
      v-else
      v-gl-tooltip
      variant="link"
      :title="sessionTooltip"
      class="gl-text-sm gl-font-bold"
      data-testid="popover-session-link"
      @click="onSessionClick"
    >
      {{ sessionNumericId }}
    </gl-button>
    <span class="gl-truncate gl-text-sm gl-text-subtle" data-testid="popover-session-definition">
      {{ sessionTitle }}
    </span>
    <span class="gl-text-sm" data-testid="popover-session-status">
      {{ session.humanStatus }}
    </span>
  </div>
</template>
