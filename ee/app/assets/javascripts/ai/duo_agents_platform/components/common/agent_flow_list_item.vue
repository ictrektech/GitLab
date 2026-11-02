<script>
import { GlLink, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { hideGlTooltip, showGlTooltip } from '~/vue_shared/utils/tooltips';
import { getTimeago } from '~/lib/utils/datetime/timeago_utility';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import {
  formatAgentFlowTitle,
  formatAgentFlowTitleTooltip,
  formatAgentStatus,
} from 'ee/ai/duo_agents_platform/utils';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';

export default {
  name: 'AgentFlowListItem',
  components: { GlLink, AgentStatusIcon },
  directives: { GlTooltip: GlTooltipDirective },
  props: {
    showProjectInfo: {
      required: false,
      type: Boolean,
      default: false,
    },
    item: {
      required: true,
      type: Object,
    },
  },
  data() {
    return { titleId: uniqueId('agent-session-title-') };
  },
  computed: {
    numericId() {
      return getIdFromGraphQLId(this.item.id);
    },
    title() {
      return formatAgentFlowTitle(this.item.title, this.item.workflowDefinition);
    },
    tooltipText() {
      return formatAgentFlowTitleTooltip(this.title, this.numericId);
    },
    linkHoverStyles() {
      return [
        'hover:gl-bg-[--gl-action-neutral-background-color-hover]',
        'hover:gl-no-underline',
        'focus-visible:gl-no-underline',
        'active:gl-no-underline',
        'focus-visible:active:gl-no-underline',
      ];
    },
    sessionRoute() {
      return { name: this.$options.showRoute, params: { id: this.numericId } };
    },
    sessionUrl() {
      const fullPath = this.item.project?.fullPath;
      return fullPath ? projectAutomateAgentSessionPath(fullPath, this.numericId) : null;
    },
    humanStatus() {
      return formatAgentStatus(this.item.humanStatus);
    },
  },
  methods: {
    handleItemSelected(event) {
      if (event.metaKey || event.ctrlKey || event.shiftKey) return;
      event.preventDefault();
      this.$router.push(this.sessionRoute);
    },
    // The tooltip anchors to the title so it sits over the text, but the link is the focus target.
    // Bound to focus/blur rather than focusin/focusout so a focusable child (the timestamp in the
    // inbox row has its own tooltip) does not bubble into this one.
    showTitleTooltip() {
      showGlTooltip(this, this.titleId);
    },
    hideTitleTooltip() {
      hideGlTooltip(this, this.titleId);
    },
    formatTimestamp(timestamp) {
      try {
        return getTimeago().format(timestamp);
      } catch {
        return timestamp || '';
      }
    },
  },
  showRoute: AGENTS_PLATFORM_SHOW_ROUTE,
};
</script>
<template>
  <gl-link
    :href="sessionUrl"
    class="gl-flex gl-gap-3 gl-p-4"
    :class="linkHoverStyles"
    @click="handleItemSelected"
    @focus="showTitleTooltip"
    @blur="hideTitleTooltip"
  >
    <div class="gl-flex gl-h-6 gl-w-6 gl-shrink-0 gl-items-center gl-justify-center">
      <agent-status-icon :status="item.status" />
    </div>
    <div class="gl-flex gl-min-w-0 gl-grow gl-flex-col gl-gap-2">
      <div class="gl-flex gl-min-h-6 gl-min-w-0 gl-items-center gl-gap-2">
        <strong
          :id="titleId"
          v-gl-tooltip
          data-testid="item-title"
          class="gl-min-w-0 gl-truncate gl-text-strong"
          :title="tooltipText"
          >{{ title }}</strong
        >
        <span
          v-if="showProjectInfo && item.project"
          class="gl-shrink-0 gl-text-subtle"
          data-testid="item-project"
        >
          {{ item.project.name }}
        </span>
      </div>
      <div class="gl-flex gl-items-center gl-gap-2 gl-text-subtle">
        <span data-testid="item-status">{{ humanStatus }}</span>
        <span aria-hidden="true">·</span>
        <span data-testid="item-updated-date">{{ formatTimestamp(item.updatedAt) }}</span>
      </div>
    </div>
  </gl-link>
</template>
