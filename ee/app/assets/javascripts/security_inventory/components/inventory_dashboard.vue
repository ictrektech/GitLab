<script>
import { defineAsyncComponent } from 'vue';
import { GlButton, GlSprintf, GlIcon, GlTooltipDirective, GlKeysetPagination } from '@gitlab/ui';
import { debounce, isEmpty, isEqual, snakeCase } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, n__, sprintf } from '~/locale';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { createAlert } from '~/alert';
import {
  getLocationHash,
  queryToObject,
  setUrlParams,
  updateHistory,
} from '~/lib/utils/url_utility';
import { smoothScrollTop } from '~/lib/utils/scroll_utils';
import LocalStorageSync from '~/vue_shared/components/local_storage_sync.vue';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_GROUP } from '~/graphql_shared/constants';
import SequentialCursorPaginator from '~/vue_shared/utils/sequential_cursor_pagination';
import { filterQueryVariables, visibleToggleableColumns } from 'ee/security_inventory/utils';
import {
  SIDEBAR_VISIBLE_STORAGE_KEY,
  HIDDEN_COLUMNS_STORAGE_KEY,
  MAX_SELECTED_COUNT,
  STATUS_FILTER_KEYS,
  STATUS_KEY,
  PROJECTS_CARD_STATUSES,
  ALL_SCANNERS_KEY,
} from '../constants';
import SubgroupsSecurityDetailsQuery from '../graphql/subgroups_security_details.query.graphql';
import ProjectsSecurityDetailsQuery from '../graphql/projects_security_details.query.graphql';
import ActiveGroupIdQuery from '../graphql/active_group_id.query.graphql';
import { getData } from '../graphql/helper';
import { withReadableParams } from '../filter_url_sync';
import { cardSelectionFromParams, paramsFromCardSelection } from '../tool_coverage_selection';
import SubgroupSidebar from './sidebar/subgroup_sidebar.vue';
import EmptyState from './empty_state.vue';
import SecurityInventoryTable from './security_inventory_table.vue';
import InventoryDashboardFilteredSearchBar from './inventory_dashboard_filtered_search_bar.vue';
import BulkEditActionsDropdown from './bulk_edit_actions_dropdown.vue';
import ToolCoverageCard from './tool_coverage_card.vue';
import ProjectsCard from './projects_card.vue';
import DisplayOptions from './display_options.vue';

const PAGE_SIZE = 20;
const FILTERS_READY_TIMEOUT_MS = 10000;
const FILTERS_READY_TIMEOUT_ERROR = 'Timed out waiting for the search bar to report its filters';
const STATUS_PARAM = snakeCase(STATUS_KEY);

export default {
  name: 'InventoryDashboard',
  components: {
    SubgroupSidebar,
    LocalStorageSync,
    RecursiveBreadcrumbs: defineAsyncComponent(() => import('./recursive_breadcrumbs.vue')),
    GlButton,
    GlSprintf,
    GlIcon,
    GlKeysetPagination,
    EmptyState,
    SecurityInventoryTable,
    InventoryDashboardFilteredSearchBar,
    BulkEditActionsDropdown,
    ToolCoverageCard,
    ProjectsCard,
    DisplayOptions,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagMixin()],
  inject: [
    'groupFullPath',
    'groupId',
    'canReadAttributes',
    'canManageAttributes',
    'canApplyProfiles',
    'canReadScanProfiles',
  ],
  i18n: {
    errorFetchingChildren: s__(
      'SecurityInventory|An error occurred while fetching subgroups and projects. Please try again.',
    ),
  },
  data() {
    return {
      activeFullPath: this.groupFullPath,
      activeGroupId: this.groupId,
      sidebarVisible: true,
      filters: {},
      queryParams: queryToObject(window.location.search),
      cardScanner: ALL_SCANNERS_KEY,
      hasInitializedFilters: false,
      hasLoadedInitialPage: false,
      isLoading: false,
      selectedCount: 0,
      currentPage: [],
      hiddenColumns: [],
    };
  },
  computed: {
    hasSearch() {
      return Boolean(
        this.filters.search?.length ||
        this.filters.securityAnalyzerFilters?.length ||
        this.filters.vulnerabilityCountFilters?.length ||
        this.filters.attributeFilters?.length ||
        STATUS_FILTER_KEYS.some((key) => this.filters[key] != null),
      );
    },
    hasChildren() {
      return this.currentPage?.length > 0;
    },
    showEmptyState() {
      return !this.isLoading && !this.hasChildren;
    },
    toggleableColumns() {
      return visibleToggleableColumns(
        this.canReadAttributes,
        Boolean(this.glFeatures.triageAndRemediationProfilesUi) && this.canReadScanProfiles,
      );
    },
    selectedCountMessage() {
      return sprintf(
        n__(
          '%{strongStart}%{selectedCount}%{strongEnd} item selected',
          '%{strongStart}%{selectedCount}%{strongEnd} items selected',
          this.selectedCount,
        ),
        { selectedCount: this.selectedCount },
      );
    },
    variables() {
      return {
        fullPath: this.activeFullPath,
        namespaceId: convertToGraphQLId(TYPENAME_GROUP, this.activeGroupId),
        ...this.filterVariables,
        canReadAttributes: this.canReadAttributes,
      };
    },
    filterVariables() {
      return filterQueryVariables({
        filters: this.filters,
        hasSearch: this.hasSearch,
      });
    },
    cardSelection() {
      const selectionFromFilters = cardSelectionFromParams(this.queryParams);

      return selectionFromFilters.status
        ? selectionFromFilters
        : { scanner: this.cardScanner, status: null };
    },
    projectsSelectedStatus() {
      const status = String(this.queryParams[STATUS_PARAM] ?? '').toUpperCase();

      return PROJECTS_CARD_STATUSES.includes(status) ? status : null;
    },
  },
  created() {
    this.paginator = new SequentialCursorPaginator(
      this.$apollo,
      [
        {
          query: SubgroupsSecurityDetailsQuery,
          skip: () => this.hasSearch,
          first: 'subgroupsFirst',
          last: 'subgroupsLast',
          after: 'subgroupsAfter',
          before: 'subgroupsBefore',
          getNodes: (result) => result.data.group.descendantGroups.nodes,
          getPageInfo: (result) => result.data.group.descendantGroups.pageInfo,
          timeout: 5000,
        },
        {
          query: ProjectsSecurityDetailsQuery,
          first: 'projectsFirst',
          last: 'projectsLast',
          after: 'projectsAfter',
          before: 'projectsBefore',
          getNodes: (result) =>
            result.data.namespaceSecurityProjects.edges.map((edge) => edge.node),
          getPageInfo: (result) => result.data.namespaceSecurityProjects.pageInfo,
          timeout: 5000,
        },
      ],
      PAGE_SIZE,
    );

    this.debouncedFilter = debounce(this.performFilter, 50);
    this.activeFullPath = getLocationHash() || this.groupFullPath;
    window.addEventListener('hashchange', this.handleLocationHashChange);
    window.addEventListener('popstate', this.readQueryParamsFromUrl);
  },
  async mounted() {
    await this.withPaginationErrorHandling(async () => {
      try {
        if (!isEmpty(this.queryParams)) await this.waitForInitializedFilters();
      } finally {
        this.hasLoadedInitialPage = true;
      }

      if (!(await this.fetchActiveGroupId())) return this.currentPage;
      return this.paginator.getNextCombinedPage(this.variables);
    });
  },
  beforeDestroy() {
    clearTimeout(this.filtersReadyTimeout);
    window.removeEventListener('hashchange', this.handleLocationHashChange);
    window.removeEventListener('popstate', this.readQueryParamsFromUrl);
  },
  methods: {
    handleError(error) {
      createAlert({
        message: this.$options.i18n.errorFetchingChildren,
        error,
        captureError: true,
      });
      Sentry.captureException(error);
    },
    async withPaginationErrorHandling(paginationFn) {
      this.isLoading = true;
      try {
        smoothScrollTop();
        this.currentPage = await paginationFn();
      } catch (error) {
        this.handleError(error);
      } finally {
        this.isLoading = false;
      }
    },
    async handleLocationHashChange() {
      let hash = getLocationHash();
      if (!hash) {
        hash = this.groupFullPath;
      }
      if (this.activeFullPath !== hash) {
        this.activeFullPath = hash;
        this.$refs.inventoryTable?.clearSelection();

        await this.withPaginationErrorHandling(async () => {
          if (!(await this.fetchActiveGroupId())) return this.currentPage;
          return this.paginator.reset(this.variables);
        });
      }
    },
    // namespaceSecurityProjects takes an ID, not a path, so the ID has to be refreshed before
    // paginating a newly opened group, otherwise its projects come from the previous group
    async fetchActiveGroupId() {
      const { activeFullPath } = this;

      if (activeFullPath === this.groupFullPath) {
        this.activeGroupId = this.groupId;
        return true;
      }

      const { data } = await this.$apollo.query({
        query: ActiveGroupIdQuery,
        variables: { fullPath: activeFullPath },
      });

      if (this.activeFullPath !== activeFullPath) return false;

      const id = getData(data, 'group.id');
      if (!id) {
        throw new Error(`Group not found: ${activeFullPath}`);
      }
      this.activeGroupId = id;

      return true;
    },
    async refetchData() {
      await this.withPaginationErrorHandling(() => this.paginator.refetch(this.variables));
    },
    toggleSidebar(value = !this.sidebarVisible) {
      this.sidebarVisible = value;
    },
    filterSubgroupsAndProjects(filters) {
      this.filters = filters;
      this.debouncedFilter();
      this.$refs.inventoryTable?.clearSelection();
    },
    readQueryParamsFromUrl() {
      this.queryParams = queryToObject(window.location.search);
    },
    waitForInitializedFilters() {
      if (this.hasInitializedFilters) return Promise.resolve();
      clearTimeout(this.filtersReadyTimeout);

      return new Promise((resolve, reject) => {
        this.resolveFiltersReady = resolve;
        this.filtersReadyTimeout = setTimeout(
          () => reject(new Error(FILTERS_READY_TIMEOUT_ERROR)),
          FILTERS_READY_TIMEOUT_MS,
        );
      });
    },
    onFiltersInitialized(filters) {
      this.hasInitializedFilters = true;
      clearTimeout(this.filtersReadyTimeout);
      const filtersChanged = !isEqual(filters, this.filters);
      this.filters = filters;
      this.resolveFiltersReady?.();
      if (this.hasLoadedInitialPage && filtersChanged) this.debouncedFilter();
    },
    onUrlParamsChanged(params) {
      this.queryParams = params;

      const url = withReadableParams(setUrlParams(params, { url: window.location.href }));

      if (url !== window.location.href) {
        updateHistory({ url });
      }
    },
    selectToolCoverage(selection) {
      if (isEqual(selection, this.cardSelection)) return;

      const leavesTheFiltersUnchanged = !selection.status && !this.cardSelection.status;
      this.cardScanner = selection.scanner;
      if (leavesTheFiltersUnchanged) return;

      this.onUrlParamsChanged({ ...this.queryParams, ...paramsFromCardSelection(selection) });
      this.$refs.inventoryTable?.clearSelection();
    },
    selectProjectsStatus(status) {
      if (status === this.projectsSelectedStatus) return;

      this.onUrlParamsChanged({
        ...this.queryParams,
        [STATUS_PARAM]: status ? status.toLowerCase() : null,
      });
      this.$refs.inventoryTable?.clearSelection();
    },
    async performFilter() {
      await this.withPaginationErrorHandling(() => this.paginator.reset(this.variables));
    },
    bulkEdit(type) {
      this.$nextTick(() => {
        this.$refs.inventoryTable.bulkEdit(type);
      });
    },
    handleSelectedCount(count) {
      this.selectedCount = count;
    },
    async handleNextPage() {
      await this.withPaginationErrorHandling(() =>
        this.paginator.getNextCombinedPage(this.variables),
      );
    },
    async handlePreviousPage() {
      await this.withPaginationErrorHandling(() =>
        this.paginator.getPreviousCombinedPage(this.variables),
      );
    },
  },
  SIDEBAR_VISIBLE_STORAGE_KEY,
  HIDDEN_COLUMNS_STORAGE_KEY,
  MAX_SELECTED_COUNT,
};
</script>

<template>
  <div class="-gl-mb-10 gl-mt-5">
    <div class="gl-flex gl-flex-wrap gl-gap-5">
      <projects-card
        v-if="glFeatures.securityInventoryProjectsWidget"
        :full-path="activeFullPath"
        :selected-status="projectsSelectedStatus"
        @update:selected-status="selectProjectsStatus"
      />
      <tool-coverage-card
        :full-path="activeFullPath"
        :selection="cardSelection"
        @update:selection="selectToolCoverage"
      />
    </div>
    <div
      class="gl-flex gl-w-full gl-border-b-1 gl-border-t-1 gl-border-default gl-bg-subtle gl-border-b-solid gl-border-t-solid"
    >
      <gl-button
        icon="sidebar"
        icon-only
        class="gl-m-3"
        :aria-label="sidebarVisible ? __('Collapse sidebar') : __('Expand sidebar')"
        data-testid="sidebar-toggle"
        @click="toggleSidebar()"
      />
      <inventory-dashboard-filtered-search-bar
        class="gl-flex-auto gl-items-center"
        :namespace="activeFullPath"
        :url-query="queryParams"
        show-status-filter
        @filter-subgroups-and-projects="filterSubgroupsAndProjects"
        @filters-initialized="onFiltersInitialized"
        @url-params-changed="onUrlParamsChanged"
      />
      <display-options
        v-model="hiddenColumns"
        :columns="toggleableColumns"
        class="gl-my-3 gl-mr-3 gl-self-center"
      />
    </div>
    <local-storage-sync
      v-model="sidebarVisible"
      :storage-key="$options.SIDEBAR_VISIBLE_STORAGE_KEY"
      @input="toggleSidebar"
    />
    <local-storage-sync
      v-model="hiddenColumns"
      :storage-key="$options.HIDDEN_COLUMNS_STORAGE_KEY"
    />
    <div class="gl-flex">
      <subgroup-sidebar v-if="sidebarVisible" :active-full-path="activeFullPath" />
      <div class="gl-w-auto gl-grow" :class="{ 'gl-pl-5': sidebarVisible }">
        <div
          v-if="selectedCount"
          class="gl-border-b gl-sticky gl-top-0 gl-z-2 gl-flex gl-min-h-11 gl-flex-row gl-items-center gl-justify-between gl-bg-default gl-px-3 gl-py-4"
        >
          <span>
            <gl-sprintf :message="selectedCountMessage">
              <template #strong="{ content }">
                <strong>{{ content }}</strong>
              </template>
            </gl-sprintf>
            <gl-icon
              v-if="selectedCount >= $options.MAX_SELECTED_COUNT"
              v-gl-tooltip="
                sprintf(__('You can edit up to %{maximumCount} items at once'), {
                  maximumCount: $options.MAX_SELECTED_COUNT,
                })
              "
              name="warning"
              variant="warning"
            />
          </span>
          <bulk-edit-actions-dropdown
            v-if="canApplyProfiles"
            :selected-count="selectedCount"
            @bulk-edit="bulkEdit"
          />
          <gl-button
            v-else-if="canManageAttributes"
            data-testid="edit-attributes-button"
            @click="bulkEdit"
            >{{ s__('SecurityAttributes|Edit security attributes') }}</gl-button
          >
        </div>
        <recursive-breadcrumbs
          v-else
          :group-full-path="groupFullPath"
          :current-path="activeFullPath"
        />
        <empty-state v-if="showEmptyState" />
        <security-inventory-table
          v-else
          ref="inventoryTable"
          :items="currentPage"
          :is-loading="isLoading"
          :has-search="hasSearch"
          :current-path="activeFullPath"
          :hidden-columns="hiddenColumns"
          @refetch="refetchData"
          @selected-count="handleSelectedCount"
        />
        <gl-keyset-pagination
          :has-next-page="paginator.hasNextPage()"
          :has-previous-page="paginator.hasPreviousPage()"
          class="gl-my-2 gl-text-center"
          @prev="handlePreviousPage"
          @next="handleNextPage"
        />
      </div>
    </div>
  </div>
</template>
