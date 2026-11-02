<script>
import { GlIcon, GlLink, GlTooltipDirective } from '@gitlab/ui';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { getChatPanelConfig } from 'ee/ai/utils/chat_panel_config';
import { isSameOriginUrl, parseUrlPathname } from '~/lib/utils/url_utility';
import { InternalEvents } from '~/tracking';

const TRAILER_REGEX = /^Duo-Session: (\S+)\s*$/m;
const SESSION_PATH_REGEX = /\/-\/automate\/agent-sessions\/(\d+)\/?$/;

export default {
  name: 'AgentSessionBadge',
  components: {
    GlIcon,
    GlLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    description: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    // The trailer is untrusted, so only a session on this instance is linked to.
    session() {
      const value = this.description?.match(TRAILER_REGEX)?.[1];
      if (!isSameOriginUrl(value)) return null;

      const path = parseUrlPathname(value);
      const id = path.match(SESSION_PATH_REGEX)?.[1];
      return id ? { path, id: Number(id) } : null;
    },
  },
  methods: {
    openSession(event) {
      if (!this.session) return;

      // Tracked before the early returns so new-tab opens are counted too.
      this.trackEvent('click_agent_session_link', {
        label: 'repository_commits',
        property: 'badge',
      });

      const { metaKey, ctrlKey, shiftKey, altKey } = event;
      if (metaKey || ctrlKey || shiftKey || altKey) return;
      // Pages without the Duo panel follow the link.
      if (!getChatPanelConfig()) return;

      event.preventDefault();
      eventHub.$emit(SHOW_SESSION, { id: this.session.id });
    },
  },
};
</script>

<template>
  <component
    :is="session ? 'gl-link' : 'span'"
    v-gl-tooltip
    :href="session?.path"
    :title="s__('DuoAgentPlatform|Commit authored in a GitLab Duo Agent session')"
    class="gl-inline-flex gl-items-center !gl-text-subtle"
    :class="{ 'hover:!gl-text-default focus-visible:gl-focus-inset': session }"
    data-testid="commit-agent-session-badge"
    @click="openSession"
  >
    <gl-icon name="session-ai" :aria-label="s__('DuoAgentPlatform|GitLab Duo Agent session')" />
  </component>
</template>
