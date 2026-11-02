<script>
import { GlBadge, GlButton, GlEmptyState, GlTab, GlTabs } from '@gitlab/ui';
import emptyStateIllustrationPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-session-inbox-md.svg';
import { s__ } from '~/locale';
import { InternalEvents } from '~/tracking';
import { createAlert } from '~/alert';
import { setupQueryPollingByVisibility } from '~/graphql_shared/utils';
import getUserAgentFlowInboxQuery from '../graphql/queries/get_user_agent_flow_inbox.query.graphql';
import AgentFlowFilteredSearch from '../components/common/agent_flow_filtered_search.vue';
import {
  DUO_AGENT_PLATFORM_POLLING_INTERVAL,
  INTERACTIVE_CLI_SOURCE_TYPES,
  DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES,
  INBOX_TAB_ALL,
} from '../constants';
import { getSessionRetentionCutoff } from '../utils';
import AgentSessionInboxTab from './agent_session_inbox_tab.vue';

const { first: PAGE_SIZE } = DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES;

// The connection has no count field, so a full page reads as "20+" rather than a total.
const TAB_COUNT_OVERFLOW = `${PAGE_SIZE}+`;

const nextPageVars = ({ endCursor }) => ({
  after: endCursor,
  before: null,
  first: PAGE_SIZE,
  last: null,
});

const prevPageVars = ({ startCursor }) => ({
  after: null,
  before: startCursor,
  first: null,
  last: PAGE_SIZE,
});

export default {
  name: 'AgentSessionInbox',
  components: {
    AgentFlowFilteredSearch,
    AgentSessionInboxTab,
    GlBadge,
    GlButton,
    GlEmptyState,
    GlTab,
    GlTabs,
  },
  mixins: [InternalEvents.mixin()],
  data() {
    return {
      inbox: null,
      activeTab: INBOX_TAB_ALL,
      allPaginationVars: { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES },
      needsDecisionPaginationVars: { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES },
      currentSort: 'UPDATED_DESC',
      filterVariables: { updatedAfter: getSessionRetentionCutoff() },
      hasInitialWorkflows: false,
    };
  },
  apollo: {
    inbox: {
      query: getUserAgentFlowInboxQuery,
      context: { featureCategory: 'duo_agent_platform' },
      pollInterval: DUO_AGENT_PLATFORM_POLLING_INTERVAL,
      variables() {
        return {
          type: 'non_foundational_chat_agents',
          sort: this.currentSort,
          ...this.filterVariables,
          ...this.allQueryVars,
          ...this.needsDecisionQueryVars,
          needsDecisionExcludeSourceTypes: INTERACTIVE_CLI_SOURCE_TYPES,
        };
      },
      // vue-apollo would fall back to `data.inbox`, which this query never selects:
      // it aliases two connections. Without the hook it errors and assigns nothing.
      update(data) {
        return data;
      },
      result({ data }) {
        // A latch rather than a derived value: the All tab's empty state has to
        // distinguish "never had rows" from "filtered down to none".
        const ndEdges = data?.needsDecision?.edges ?? [];
        const allEdges = data?.all?.edges ?? [];
        if (ndEdges.length > 0 || allEdges.length > 0) this.hasInitialWorkflows = true;
      },
      error(err) {
        createAlert({
          message: err.message || s__('DuoAgentsPlatform|Failed to fetch workflows'),
          captureError: true,
        });
      },
    },
  },
  computed: {
    needsDecisionHasMorePages() {
      return Boolean(
        this.needsDecisionPageInfo.hasNextPage || this.needsDecisionPageInfo.hasPreviousPage,
      );
    },
    needsDecisionWorkflows() {
      return this.inbox?.needsDecision?.edges?.map((e) => e.node) ?? [];
    },
    allWorkflows() {
      return this.inbox?.all?.edges?.map((e) => e.node) ?? [];
    },
    needsDecisionPageInfo() {
      return this.inbox?.needsDecision?.pageInfo ?? {};
    },
    allPageInfo() {
      return this.inbox?.all?.pageInfo ?? {};
    },
    allQueryVars() {
      const { first, after, last, before } = this.allPaginationVars;
      return {
        allFirst: first,
        allAfter: after,
        allLast: last,
        allBefore: before,
      };
    },
    needsDecisionQueryVars() {
      const { first, after, last, before } = this.needsDecisionPaginationVars;
      return {
        needsDecisionFirst: first,
        needsDecisionAfter: after,
        needsDecisionLast: last,
        needsDecisionBefore: before,
      };
    },
    isInboxLoading() {
      return this.$apollo.queries.inbox.loading && !this.inbox;
    },
    needsDecisionBadge() {
      return this.needsDecisionHasMorePages
        ? TAB_COUNT_OVERFLOW
        : String(this.needsDecisionWorkflows.length);
    },
    hasActiveFilters() {
      const { updatedAfter, ...filters } = this.filterVariables;
      return Object.keys(filters).length > 0;
    },
    showDecisionEmptyState() {
      return this.needsDecisionWorkflows.length === 0 && !this.hasActiveFilters;
    },
    showAllEmptyState() {
      return !this.hasInitialWorkflows;
    },
  },
  mounted() {
    this.pollingVisibilityCleanup = setupQueryPollingByVisibility(
      this.$apollo.queries.inbox,
      DUO_AGENT_PLATFORM_POLLING_INTERVAL,
    );
  },
  beforeDestroy() {
    this.pollingVisibilityCleanup?.();
  },
  methods: {
    handleSearchVariablesUpdated({ sort, filters }) {
      this.currentSort = sort;
      this.filterVariables = {
        ...filters,
        updatedAfter: getSessionRetentionCutoff(),
      };
      this.resetPagination();
    },
    handleNextPage() {
      this.allPaginationVars = nextPageVars(this.allPageInfo);
    },
    handlePrevPage() {
      this.allPaginationVars = prevPageVars(this.allPageInfo);
    },
    handleDecisionNextPage() {
      this.needsDecisionPaginationVars = nextPageVars(this.needsDecisionPageInfo);
    },
    handleDecisionPrevPage() {
      this.needsDecisionPaginationVars = prevPageVars(this.needsDecisionPageInfo);
    },
    showAllTab() {
      this.trackEvent('click_view_all_sessions_in_agent_session_inbox');
      this.handleTabChange(INBOX_TAB_ALL);
    },
    handleTabChange(tab) {
      this.activeTab = tab;
      this.resetPagination();
    },
    resetPagination() {
      this.allPaginationVars = { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES };
      this.needsDecisionPaginationVars = { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES };
    },
  },
  emptyStateIllustrationPath,
};
</script>
<template>
  <div class="gl-flex gl-flex-col" data-testid="agent-session-inbox">
    <agent-flow-filtered-search
      :has-initial-workflows="hasInitialWorkflows"
      :initial-sort="currentSort"
      :show-time-range-filter="false"
      show-project-filter
      @search-variables-updated="handleSearchVariablesUpdated"
    />
    <gl-tabs
      :value="activeTab"
      class="gl-flex gl-grow gl-flex-col"
      content-class="gl-flex gl-grow gl-flex-col"
      active-tab-class="!gl-flex gl-grow gl-flex-col"
      @input="handleTabChange"
    >
      <gl-tab>
        <template #title>
          {{ s__('DuoAgentsPlatform|Needs a decision') }}
          <gl-badge
            v-if="!isInboxLoading"
            class="gl-tab-counter-badge"
            data-testid="needs-decision-tab-badge"
          >
            {{ needsDecisionBadge }}
          </gl-badge>
        </template>
        <agent-session-inbox-tab
          data-testid="needs-decision-tab"
          testid-prefix="needs-decision"
          :loading="isInboxLoading"
          :workflows="needsDecisionWorkflows"
          :page-info="needsDecisionPageInfo"
          :show-empty-state="showDecisionEmptyState"
          @next-page="handleDecisionNextPage"
          @prev-page="handleDecisionPrevPage"
        >
          <template #empty-state>
            <gl-empty-state
              :description="
                s__('DuoAgentPlatform|When an agent needs a decision from you, it shows up here.')
              "
              :svg-path="$options.emptyStateIllustrationPath"
              :svg-height="72"
              content-class="gl-text-balance"
            >
              <template #title>
                <h4 class="gl-heading-4 gl-m-0">
                  {{ s__('DuoAgentPlatform|Nothing needs you right now') }}
                </h4>
              </template>
              <template #actions>
                <gl-button @click="showAllTab">
                  {{ s__('DuoAgentPlatform|View all sessions') }}
                </gl-button>
              </template>
            </gl-empty-state>
          </template>
        </agent-session-inbox-tab>
      </gl-tab>
      <gl-tab>
        <template #title>
          {{ s__('DuoAgentsPlatform|All') }}
        </template>
        <agent-session-inbox-tab
          data-testid="all-tab"
          testid-prefix="all"
          :loading="isInboxLoading"
          :workflows="allWorkflows"
          :page-info="allPageInfo"
          :show-empty-state="showAllEmptyState"
          @next-page="handleNextPage"
          @prev-page="handlePrevPage"
        />
      </gl-tab>
    </gl-tabs>
  </div>
</template>
