<script>
import { GlLink } from '@gitlab/ui';
import { parseAgentSessionUrl } from '~/blob/components/source_viewer/utils';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { getChatPanelConfig } from 'ee/ai/utils/chat_panel_config';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { InternalEvents } from '~/tracking';

/**
 * Link to a Duo agent session that opens the Duo side panel on a plain click,
 * so the reader stays on the file. Modifier clicks, sessions on another
 * instance, and pages without the panel fall through to the link.
 */
export default {
  name: 'AgentSessionLink',
  components: {
    GlLink,
  },
  mixins: [glSlotsMixin, InternalEvents.mixin()],
  props: {
    href: {
      type: String,
      required: true,
    },
    trackingProperty: {
      type: String,
      required: true,
    },
  },
  computed: {
    panelSessionId() {
      const id = parseAgentSessionUrl(this.href)?.id;
      return id ? Number(id) : null;
    },
  },
  methods: {
    handleClick(event) {
      // Tracked before the early returns so new-tab opens are counted too.
      this.trackEvent('click_agent_session_link', {
        label: 'blame',
        property: this.trackingProperty,
      });

      if (event.metaKey || event.ctrlKey || event.shiftKey) return;
      if (!this.panelSessionId || !getChatPanelConfig()) return;

      event.preventDefault();
      eventHub.$emit(SHOW_SESSION, { id: this.panelSessionId });
    },
  },
};
</script>

<template>
  <gl-link :href="href" @click="handleClick"
    ><template v-if="glSlots().default" #default><slot></slot></template
  ></gl-link>
</template>
