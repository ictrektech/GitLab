<script>
import { GlLink, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { hideGlTooltip, showGlTooltip } from '~/vue_shared/utils/tooltips';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { projectAutomateAgentSessionPath } from 'ee/lib/utils/path_helpers/project';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import {
  formatAgentDefinition,
  formatAgentFlowTitle,
  formatAgentFlowTitleTooltip,
} from 'ee/ai/duo_agents_platform/utils';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';

export default {
  name: 'InboxRow',
  components: { GlLink, TimeAgoTooltip },
  directives: { GlTooltip: GlTooltipDirective },
  mixins: [glSlotsMixin],
  props: {
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
    flowName() {
      return this.item.aiCatalogItem?.name || formatAgentDefinition(this.item.workflowDefinition);
    },
    sessionRoute() {
      return { name: AGENTS_PLATFORM_SHOW_ROUTE, params: { id: this.numericId } };
    },
    sessionUrl() {
      const fullPath = this.item.project?.fullPath;
      return fullPath ? projectAutomateAgentSessionPath(fullPath, this.numericId) : null;
    },
    linkHoverStyles() {
      return [
        'hover:gl-bg-subtle',
        'hover:gl-no-underline',
        'focus-visible:gl-no-underline',
        'active:gl-no-underline',
        'focus-visible:active:gl-no-underline',
      ];
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
  },
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
    <div
      v-if="glSlots().icon"
      class="gl-flex gl-h-6 gl-w-6 gl-shrink-0 gl-items-center gl-justify-center"
      data-testid="item-icon"
    >
      <slot name="icon"></slot>
    </div>
    <div class="gl-flex gl-min-w-0 gl-grow gl-flex-col gl-gap-2">
      <div class="gl-flex gl-min-h-6 gl-items-center gl-justify-between">
        <div
          v-if="glSlots().status"
          class="gl-flex gl-min-w-0 gl-items-center gl-gap-2"
          data-testid="item-status"
        >
          <slot name="status"></slot>
        </div>
        <slot name="trailing">
          <time-ago-tooltip
            :time="item.updatedAt"
            class="gl-shrink-0 gl-pl-3 gl-text-subtle"
            data-testid="item-updated-date"
          />
        </slot>
      </div>
      <slot name="title">
        <strong
          :id="titleId"
          v-gl-tooltip
          class="gl-min-w-0 gl-max-w-full gl-self-start gl-truncate gl-text-strong"
          :title="tooltipText"
          data-testid="item-title"
          >{{ title }}</strong
        >
      </slot>
      <slot></slot>
      <slot name="metadata">
        <div class="gl-min-w-0 gl-truncate gl-text-subtle" data-testid="item-metadata">
          <span class="gl-sr-only" data-testid="item-session-label">{{
            s__('DuoAgentsPlatform|Session')
          }}</span>
          {{ numericId }}
          <span aria-hidden="true"> · </span>{{ flowName
          }}<template v-if="item.project">
            <span aria-hidden="true"> · </span>{{ item.project.name }}</template
          >
        </div>
      </slot>
    </div>
  </gl-link>
</template>
