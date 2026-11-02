<script>
import { GlIcon } from '@gitlab/ui';
import InboxRow from './inbox_row.vue';

// A CLI session parked in INPUT_REQUIRED: nothing to decide on the web, so the row
// shows where it lives instead of a status that reads like a call to action.
export default {
  name: 'AgentSessionCliInboxItem',
  components: { GlIcon, InboxRow },
  props: {
    item: {
      required: true,
      type: Object,
    },
  },
};
</script>
<template>
  <inbox-row :item="item">
    <template #icon>
      <gl-icon
        name="terminal"
        class="gl-text-subtle"
        aria-hidden="true"
        data-testid="item-cli-icon"
      />
    </template>
    <template #status>
      <span class="gl-shrink-0 gl-font-semibold gl-text-subtle" data-testid="item-cli-label">{{
        s__('DuoAgentPlatform|CLI')
      }}</span>
    </template>
    <div class="gl-min-w-0 gl-truncate gl-text-subtle" data-testid="item-cli-readonly-note">
      {{ s__('DuoAgentPlatform|Read-only on the web') }}
    </div>
  </inbox-row>
</template>
