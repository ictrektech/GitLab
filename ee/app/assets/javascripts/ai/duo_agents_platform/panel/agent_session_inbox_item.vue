<script>
import { formatAgentStatus, getAgentStatusTextClass } from 'ee/ai/duo_agents_platform/utils';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import { AGENT_SESSION_INBOX_STATUS_LABELS } from './constants';
import InboxRow from './inbox_row.vue';

export default {
  name: 'AgentSessionInboxItem',
  components: { AgentStatusIcon, InboxRow },
  props: {
    item: {
      required: true,
      type: Object,
    },
  },
  computed: {
    statusLabel() {
      return (
        AGENT_SESSION_INBOX_STATUS_LABELS[this.item.status] ??
        formatAgentStatus(this.item.humanStatus)
      );
    },
    statusTextClass() {
      return getAgentStatusTextClass(this.item.status);
    },
  },
};
</script>
<template>
  <inbox-row :item="item">
    <template #icon>
      <agent-status-icon :status="item.status" />
    </template>
    <template #status>
      <span
        class="gl-shrink-0 gl-font-semibold"
        :class="statusTextClass"
        data-testid="item-status-label"
        >{{ statusLabel }}</span
      >
    </template>
  </inbox-row>
</template>
