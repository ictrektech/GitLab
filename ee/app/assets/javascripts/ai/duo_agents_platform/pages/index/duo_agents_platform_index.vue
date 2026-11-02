<script>
import { GlIcon, GlLink, GlSkeletonLoader, GlSprintf, GlTruncate } from '@gitlab/ui';
import { projectPath } from '~/lib/utils/path_helpers/project';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import AgentFlowList from 'ee/ai/duo_agents_platform/components/common/agent_flow_list.vue';
import AgentFlowFilteredSearch from 'ee/ai/duo_agents_platform/components/common/agent_flow_filtered_search.vue';
import {
  AGENT_PLATFORM_INDEX_COMPONENT_NAME,
  DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES,
} from 'ee/ai/duo_agents_platform/constants';
import NoCreditsBanner from '../../components/common/no_credits_banner.vue';
import UsageBillingForbiddenBanner from '../../components/common/usage_billing_forbidden_banner.vue';

export default {
  name: AGENT_PLATFORM_INDEX_COMPONENT_NAME,
  components: {
    AgentFlowFilteredSearch,
    AgentFlowList,
    GlIcon,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
    GlTruncate,
    PageHeading,
    NoCreditsBanner,
    UsageBillingForbiddenBanner,
  },
  inject: {
    isSidePanelView: { default: false },
    creditsAvailable: { default: true },
    billingForbidden: { default: false },
  },
  props: {
    hasInitialWorkflows: {
      required: true,
      type: Boolean,
    },
    initialSort: {
      required: true,
      type: String,
    },
    initialFilters: {
      required: false,
      type: Object,
      default: () => ({}),
    },
    isLoadingWorkflows: {
      required: true,
      type: Boolean,
    },
    workflows: {
      required: true,
      type: Array,
    },
    workflowsPageInfo: {
      required: true,
      type: Object,
    },
    showProjectFilter: {
      required: false,
      type: Boolean,
      default: false,
    },
    scopedProjectPath: {
      required: false,
      type: String,
      default: '',
    },
  },
  emits: ['query-variables-updated'],
  data() {
    const { updatedAfter = null, ...filters } = this.initialFilters;
    return {
      searchVariables: { sort: this.initialSort, filters, updatedAfter },
    };
  },
  computed: {
    showEmptyState() {
      return !this.hasInitialWorkflows;
    },
    showScopedProjectTagline() {
      return Boolean(this.scopedProjectPath) && this.hasInitialWorkflows && !this.isSidePanelView;
    },
    scopedProjectLabel() {
      return this.scopedProjectPath.split('/').join(' / ');
    },
    scopedProjectWebPath() {
      return projectPath(this.scopedProjectPath);
    },
  },
  methods: {
    handleSearchVariablesUpdated(searchVariables) {
      this.searchVariables = searchVariables;
      this.handlePagination(DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES);
    },
    handleNextPage() {
      const paginationVars = {
        before: null,
        after: this.workflowsPageInfo.endCursor,
        first: 20,
        last: null,
      };
      this.handlePagination(paginationVars);
    },
    handlePrevPage() {
      const paginationVars = {
        after: null,
        before: this.workflowsPageInfo.startCursor,
        first: null,
        last: 20,
      };
      this.handlePagination(paginationVars);
    },
    handlePagination(pagination) {
      this.$emit('query-variables-updated', { ...this.searchVariables, pagination });
    },
  },
};
</script>
<template>
  <div
    :class="{ 'gl-flex gl-flex-col': isSidePanelView }"
    class="gl-min-h-full gl-flex-wrap gl-justify-center"
    data-testid="agent-sessions"
  >
    <page-heading v-if="!isSidePanelView" :heading="s__('DuoAgentsPlatform|Sessions')" />
    <usage-billing-forbidden-banner v-if="!creditsAvailable && billingForbidden" />
    <no-credits-banner v-else-if="!creditsAvailable" />
    <agent-flow-filtered-search
      :has-initial-workflows="hasInitialWorkflows"
      :initial-sort="initialSort"
      :initial-filters="initialFilters"
      :show-project-filter="showProjectFilter"
      @search-variables-updated="handleSearchVariablesUpdated"
    />
    <p
      v-if="showScopedProjectTagline"
      class="gl-mb-1 gl-flex gl-min-w-0 gl-px-4 gl-text-sm gl-text-subtle"
      data-testid="scoped-project-tagline"
    >
      <gl-sprintf :message="s__('DuoAgentPlatform|Showing sessions in %{project}')">
        <template #project>
          <span class="gl-ml-2 gl-flex gl-min-w-0 gl-items-center gl-gap-2">
            <gl-icon name="project" variant="subtle" :size="14" class="gl-shrink-0" />
            <gl-link :href="scopedProjectWebPath" class="gl-min-w-0 gl-text-inherit">
              <gl-truncate
                :text="scopedProjectLabel"
                position="middle"
                with-tooltip
                class="hover:gl-underline"
              />
            </gl-link>
          </span>
        </template>
      </gl-sprintf>
    </p>
    <div
      v-if="isLoadingWorkflows"
      class="gl-flex gl-w-full gl-flex-col gl-gap-5 gl-p-5"
      data-testid="loading-container"
    >
      <gl-skeleton-loader :lines="2" :width="300" />
      <gl-skeleton-loader :lines="2" :width="300" />
      <gl-skeleton-loader :lines="2" :width="300" />
    </div>
    <agent-flow-list
      v-else
      :show-project-info="isSidePanelView"
      :show-empty-state="showEmptyState"
      show-retention-notice
      :workflows="workflows"
      :workflows-page-info="workflowsPageInfo"
      @next-page="handleNextPage"
      @prev-page="handlePrevPage"
    />
  </div>
</template>
