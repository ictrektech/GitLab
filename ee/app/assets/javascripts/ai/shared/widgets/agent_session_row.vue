<script>
import { GlAvatar, GlAvatarLink, GlButton, GlLink, GlTooltipDirective } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import {
  formatAgentFlowTitle,
  formatAgentFlowTitleTooltip,
  getNumericId,
} from 'ee/ai/duo_agents_platform/utils';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import duoChatAvailableQuery from '../../graphql/duo_chat_available.query.graphql';

export default {
  name: 'AgentSessionRow',
  components: {
    GlAvatar,
    GlAvatarLink,
    GlButton,
    GlLink,
    TimeAgoTooltip,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    session: {
      type: Object,
      required: true,
    },
    showViewDetails: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      duoChatAvailable: false,
    };
  },
  apollo: {
    duoChatAvailable: {
      query: duoChatAvailableQuery,
      update(data) {
        return data?.currentUser?.duoChatAvailable ?? false;
      },
      error() {
        this.duoChatAvailable = false;
      },
    },
  },
  computed: {
    numericId() {
      return getIdFromGraphQLId(this.session.id);
    },
    sessionUrl() {
      const fullPath = this.session.project?.fullPath;
      return fullPath ? projectAutomateAgentSessionPath(fullPath, this.numericId) : null;
    },
    title() {
      return formatAgentFlowTitle(this.session.title, this.session.workflowDefinition);
    },
    canOpenSession() {
      return Boolean(this.sessionUrl) || this.duoChatAvailable;
    },
    titleComponent() {
      if (this.sessionUrl) return GlLink;
      return this.duoChatAvailable ? GlButton : 'span';
    },
    titleAttributes() {
      if (this.sessionUrl) return { href: this.sessionUrl };
      return this.duoChatAvailable
        ? { variant: 'link', buttonTextClasses: 'gl-truncate' }
        : { tabindex: 0 };
    },
    titleTooltip() {
      return formatAgentFlowTitleTooltip(this.title, this.numericId);
    },
    user() {
      return this.session.user || null;
    },
    userId() {
      return getNumericId(this.user?.id);
    },
  },
  methods: {
    openSession(event) {
      if (!this.duoChatAvailable) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey) return;

      event.preventDefault();
      eventHub.$emit(SHOW_SESSION, { id: this.numericId });
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-px-4 gl-py-3"
    data-testid="agent-session-row"
  >
    <div class="gl-flex gl-min-w-0 gl-items-center">
      <component
        :is="titleComponent"
        v-gl-tooltip
        v-bind="titleAttributes"
        :title="titleTooltip"
        class="gl-truncate"
        :class="{ 'gl-text-subtle': !canOpenSession }"
        data-testid="session-title"
        @click="openSession"
      >
        {{ title }}
      </component>
    </div>
    <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-3 gl-whitespace-nowrap">
      <time-ago-tooltip
        v-if="session.updatedAt"
        :time="session.updatedAt"
        class="gl-text-sm gl-text-subtle"
        data-testid="session-updated-at"
      />
      <gl-button
        v-if="canOpenSession && showViewDetails"
        :href="sessionUrl"
        size="small"
        variant="confirm"
        category="tertiary"
        data-testid="session-view-details-button"
        @click="openSession"
      >
        {{ s__('DuoAgentPlatform|View details') }}
      </gl-button>
      <gl-avatar-link
        v-if="user"
        v-gl-tooltip.bottom
        :href="user.webPath"
        :title="user.name"
        :data-user-id="userId"
        :data-username="user.username"
        class="js-user-link"
        data-testid="session-triggered-user"
      >
        <gl-avatar
          :src="user.avatarUrl"
          :entity-name="user.name"
          :alt="user.name"
          :size="16"
          shape="circle"
        />
      </gl-avatar-link>
    </div>
  </div>
</template>
