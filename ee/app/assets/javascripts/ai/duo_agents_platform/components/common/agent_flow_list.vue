<script>
import { GlEmptyState, GlKeysetPagination } from '@gitlab/ui';
import emptyStateIllustrationPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-agent-sessions-md.svg';
import EmptyResult from '~/vue_shared/components/empty_result.vue';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import AgentFlowListItem from './agent_flow_list_item.vue';
import AgentSessionRetentionNotice from './agent_session_retention_notice.vue';

export default {
  name: 'AgentFlowList',
  components: {
    EmptyResult,
    GlEmptyState,
    GlKeysetPagination,
    AgentFlowListItem,
    AgentSessionRetentionNotice,
  },
  inject: {
    isSidePanelView: { default: false },
  },
  props: {
    showEmptyState: {
      required: true,
      type: Boolean,
    },
    showProjectInfo: {
      required: false,
      type: Boolean,
      default: false,
    },
    showRetentionNotice: {
      required: false,
      type: Boolean,
      default: false,
    },
    workflows: {
      required: true,
      type: Array,
    },
    workflowsPageInfo: {
      required: true,
      type: Object,
    },
  },
  emits: ['next-page', 'prev-page'],
  computed: {
    hasWorkflows() {
      return this.workflows?.length > 0;
    },
    displayPagination() {
      return this.workflowsPageInfo?.hasNextPage || this.workflowsPageInfo?.hasPreviousPage;
    },
    emptyStateSvgHeight() {
      return this.isSidePanelView ? 72 : 144;
    },
  },
  showRoute: AGENTS_PLATFORM_SHOW_ROUTE,
  emptyStateIllustrationPath,
};
</script>
<template>
  <div
    :class="{ 'gl-self-center': !hasWorkflows, 'gl-flex gl-grow gl-flex-col': isSidePanelView }"
    class="gl-w-full"
  >
    <gl-empty-state
      v-if="showEmptyState"
      :title="s__('DuoAgentsPlatform|No agent sessions yet')"
      :description="s__('DuoAgentsPlatform|New agent sessions will appear here.')"
      :svg-path="$options.emptyStateIllustrationPath"
      :svg-height="emptyStateSvgHeight"
      :content-class="{ 'gl-text-balance': isSidePanelView }"
    >
      <template v-if="isSidePanelView" #title>
        <h4 class="gl-heading-4 gl-m-0">
          {{ s__('DuoAgentPlatform|No agent sessions yet') }}
        </h4>
      </template>
    </gl-empty-state>
    <template v-else>
      <ul
        v-if="hasWorkflows"
        class="gl-divide-x-0 gl-divide-y-1 gl-divide-solid gl-divide-subtle gl-px-0"
      >
        <li v-for="item in workflows" :key="item.id" class="gl-list-none">
          <slot name="row" :item="item">
            <agent-flow-list-item :item="item" :show-project-info="showProjectInfo" />
          </slot>
        </li>
      </ul>
      <empty-result v-else type="search" :svg-height="emptyStateSvgHeight" />
      <agent-session-retention-notice v-if="showRetentionNotice && !isSidePanelView" />
      <gl-keyset-pagination
        v-if="displayPagination"
        v-bind="workflowsPageInfo"
        class="gl-mt-5 gl-flex gl-justify-center gl-pb-4"
        @prev="$emit('prev-page')"
        @next="$emit('next-page')"
      />
      <agent-session-retention-notice v-if="showRetentionNotice && isSidePanelView" side-panel />
    </template>
  </div>
</template>
