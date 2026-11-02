<script>
import { GlFilteredSearchToken, GlCollapsibleListbox } from '@gitlab/ui';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import {
  FILTERED_SEARCH_TERM,
  OPERATORS_IS,
} from '~/vue_shared/components/filtered_search_bar/constants';
import {
  prepareTokens,
  processFilters,
} from '~/vue_shared/components/filtered_search_bar/filtered_search_utils';
import { __, s__ } from '~/locale';
import { createAlert } from '~/alert';
import { getSessionRetentionCutoff } from 'ee/ai/duo_agents_platform/utils';
import getFlowTypesQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_flow_types.query.graphql';
import getSessionProjectsQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_session_projects.query.graphql';

const filtersToTokens = (filters) =>
  prepareTokens({
    'flow-name': filters.type && { value: filters.type, operator: '=' },
    'flow-project': filters.projectId && { value: filters.projectId, operator: '=' },
    'flow-status-group': filters.statusGroup && { value: filters.statusGroup, operator: '=' },
    [FILTERED_SEARCH_TERM]: filters.search && { value: filters.search },
  });

const tokensToFilters = (tokens) => {
  const {
    'flow-name': [type] = [],
    'flow-project': [project] = [],
    'flow-status-group': [statusGroup] = [],
    [FILTERED_SEARCH_TERM]: searchTerms = [],
  } = processFilters(tokens);

  const search = searchTerms
    .map(({ value }) => value)
    .join(' ')
    .trim();

  return {
    ...(type?.value && { type: type.value }),
    ...(project?.value && { projectId: project.value }),
    ...(statusGroup?.value && { statusGroup: statusGroup.value }),
    ...(search && { search }),
  };
};

export default {
  name: 'AgentFlowFilteredSearch',
  components: {
    FilteredSearchBar,
    GlCollapsibleListbox,
  },
  inject: {
    currentProjectId: { default: '' },
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
    showTimeRangeFilter: {
      required: false,
      type: Boolean,
      default: true,
    },
    showProjectFilter: {
      required: false,
      type: Boolean,
      default: false,
    },
  },
  emits: ['search-variables-updated'],
  data() {
    const initialTokens = filtersToTokens(this.initialFilters);

    return {
      initialFilterValue: initialTokens,
      currentFilters: initialTokens,
      currentSort: this.initialSort,
      timeRangeFilter: this.initialFilters.updatedAfter ? 'available' : 'all',
      flowTypes: [],
      sessionProjects: [],
    };
  },
  apollo: {
    sessionProjects: {
      query: getSessionProjectsQuery,
      skip() {
        return !this.showProjectFilter;
      },
      update(data) {
        return data.duoWorkflowRecentSessionProjects || [];
      },
      error() {
        createAlert({
          message: __('There was a problem fetching projects.'),
          captureError: true,
        });
      },
    },
    flowTypes: {
      query: getFlowTypesQuery,
      update(data) {
        return (
          data.aiCatalogItems?.nodes
            ?.filter((item) => item.foundationalFlowReference)
            .map((item) => ({
              value: item.foundationalFlowReference,
              title: item.name,
            })) || []
        );
      },
      error(error) {
        createAlert({
          message: error.message || s__('DuoAgentsPlatform|Failed to fetch flow types'),
          captureError: true,
        });
      },
    },
  },
  computed: {
    processedFiltersForGraphQL() {
      return tokensToFilters(this.currentFilters);
    },
    selectedTimeRangeText() {
      return this.$options.timeRangeOptions.find((opt) => opt.value === this.timeRangeFilter)?.text;
    },
    flowNameToken() {
      return {
        type: 'flow-name',
        title: s__('DuoAgentsPlatform|Flow'),
        icon: 'flow-ai',
        token: GlFilteredSearchToken,
        operators: OPERATORS_IS,
        unique: true,
        options: this.flowTypes,
      };
    },
    projectOptions() {
      const options = this.sessionProjects.map(({ id, nameWithNamespace }) => ({
        value: id,
        title: nameWithNamespace,
      }));
      const current = options.find(({ value }) => value === this.currentProjectId);

      return current ? [current, ...options.filter((option) => option !== current)] : options;
    },
    projectToken() {
      return {
        type: 'flow-project',
        title: __('Project'),
        icon: 'project',
        token: GlFilteredSearchToken,
        operators: OPERATORS_IS,
        unique: true,
        options: this.projectOptions,
      };
    },
    flowStatusGroupToken() {
      return {
        type: 'flow-status-group',
        title: __('Status'),
        icon: 'status',
        token: GlFilteredSearchToken,
        operators: OPERATORS_IS,
        unique: true,
        options: [
          { value: 'ACTIVE', title: __('Active') },
          { value: 'PAUSED', title: __('Paused') },
          { value: 'AWAITING_INPUT', title: __('Awaiting input') },
          { value: 'COMPLETED', title: __('Completed') },
          { value: 'FAILED', title: __('Failed') },
          { value: 'CANCELED', title: __('Canceled') },
        ],
      };
    },
    computedTokens() {
      return [
        ...(this.flowTypes.length > 0 ? [this.flowNameToken] : []),
        ...(this.projectOptions.length > 0 ? [this.projectToken] : []),
        this.flowStatusGroupToken,
      ];
    },
  },
  methods: {
    getUpdatedAfter() {
      if (this.timeRangeFilter !== 'available') return null;

      return getSessionRetentionCutoff();
    },
    emitSearchVariables() {
      this.$emit('search-variables-updated', {
        sort: this.currentSort,
        filters: this.processedFiltersForGraphQL,
        updatedAfter: this.getUpdatedAfter(),
      });
    },
    handleSort(sortBy) {
      this.currentSort = sortBy;
      this.emitSearchVariables();
    },
    handleFilter(filters) {
      this.currentFilters = filters;
      this.emitSearchVariables();
    },
    handleTimeRangeChange(value) {
      this.timeRangeFilter = value;
      this.emitSearchVariables();
    },
  },
  availableSortOptions: [
    {
      id: 1,
      title: __('Created date'),
      sortDirection: {
        descending: 'CREATED_DESC',
        ascending: 'CREATED_ASC',
      },
    },
    {
      id: 2,
      title: __('Updated date'),
      sortDirection: {
        descending: 'UPDATED_DESC',
        ascending: 'UPDATED_ASC',
      },
    },
  ],
  timeRangeOptions: [
    { value: 'all', text: __('All') },
    { value: 'available', text: s__('DuoAgentsPlatform|Available') },
  ],
};
</script>

<template>
  <filtered-search-bar
    v-if="hasInitialWorkflows"
    namespace="duo-agents-platform"
    :tokens="computedTokens"
    :search-input-placeholder="s__('DuoAgentsPlatform|Search for a session')"
    :sort-options="$options.availableSortOptions"
    :initial-sort-by="initialSort"
    :initial-filter-value="initialFilterValue"
    recent-searches-storage-key="agent-sessions"
    sync-filter-and-sort
    terms-as-tokens
    class="gl-border-t-0 gl-p-4"
    data-testid="agent-sessions-search-container"
    @on-filter="handleFilter"
    @on-sort="handleSort"
  >
    <template v-if="showTimeRangeFilter" #time-range-filter>
      <gl-collapsible-listbox
        data-testid="time-range-filter"
        :items="$options.timeRangeOptions"
        :selected="timeRangeFilter"
        :toggle-text="selectedTimeRangeText"
        @select="handleTimeRangeChange"
      />
    </template>
  </filtered-search-bar>
</template>
