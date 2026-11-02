<script>
import { defineComponent } from 'vue';
import { GlButton } from '@gitlab/ui';
import axios from '~/lib/utils/axios_utils';
import { InternalEvents } from '~/tracking';
import { mutateGroup } from '../../shared/groups/action_mutations';
import BulkResultAlert from '../../shared/groups/bulk_result_alert.vue';
import GroupsConfirmModal from '../../shared/groups/groups_confirm_modal.vue';
import GroupsTable from '../../shared/groups/groups_table.vue';
import GroupsWarnings from '../../shared/groups/groups_warnings.vue';
import {
  ACTION_TURN_OFF,
  ALL_GROUP_ACTIONS,
  BULK_ACTION_CONCURRENCY,
  CONFIRM_AUTO_INDEX,
  CONFIRMED_ACTIONS,
  GROUP_FILTER_ALL,
  GROUP_FILTER_EXCLUDED,
  GROUP_FILTER_ON,
  GROUP_FILTER_OPTIONS,
} from '../../shared/groups/constants';
import {
  actionItemsFor,
  completeBulkProgress,
  confirmKindFor,
  groupsForAction,
  hasActiveIndexing,
  indexStatusWarningFor,
  mapWithConcurrency,
  reportFirstRequestError,
  reportRequestError,
  requestErrorFor,
  startBulkProgress,
  summarizeBulkAction,
} from '../../shared/groups/utils';
import adminGroupsQuery from './graphql/admin_groups.query.graphql';
import adminExcludedGroupsQuery from './graphql/admin_excluded_groups.query.graphql';
import adminServiceStatusQuery from './graphql/admin_service_status.query.graphql';
import AdminHealthCard from './admin_health_card.vue';
import AdminInstanceAccess from './admin_instance_access.vue';
import AdminInstanceSettings from './admin_instance_settings.vue';
import {
  EXCLUDED_GROUPS_PAGE_SIZE,
  GROUPS_PAGE_SIZE,
  INDEXING_POLL_INTERVAL_MS,
  SETTING_AUTO_INDEX,
  SETTING_DUO_DEFAULT,
} from './constants';
import { buildGroupRows, filterGroupsBySearch, statusFromServiceStatus } from './utils';

const EMPTY_CONNECTION = { nodes: [], pageInfo: {} };

export default defineComponent({
  name: 'AdminSettingsPage',
  components: {
    AdminHealthCard,
    AdminInstanceAccess,
    AdminInstanceSettings,
    BulkResultAlert,
    GlButton,
    GroupsConfirmModal,
    GroupsTable,
    GroupsWarnings,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    settingsPath: { type: String, required: true },
    overviewPath: { type: String, required: true },
    schemaPath: { type: String, required: true },
    newGroupPath: { type: String, required: true },
    autoIndexEnabled: { type: Boolean, required: true },
    duoDefaultEnabled: { type: Boolean, required: true },
  },
  apollo: {
    groupsConnection: {
      query: adminGroupsQuery,
      errorPolicy: 'all',
      variables() {
        return {
          search: this.search || null,
          enabled: this.filter === GROUP_FILTER_ON,
          ...this.pageCursor,
        };
      },
      skip() {
        return this.filter === GROUP_FILTER_EXCLUDED;
      },
      update(data) {
        return data.orbit?.groups ?? EMPTY_CONNECTION;
      },
      result({ data, errors }) {
        const firstErrorMessage = errors?.[0]?.message ?? null;

        if (!data?.orbit?.groups) {
          if (firstErrorMessage) this.groupsError = firstErrorMessage;
          return;
        }

        this.groupsError = null;
        this.indexStatusError = firstErrorMessage;
        this.updatePolling();
      },
      error(error) {
        if (!error.graphQLErrors.length) this.groupsError = reportRequestError(error).message;
      },
    },
    excludedGroupsConnection: {
      query: adminExcludedGroupsQuery,
      errorPolicy: 'all',
      variables: { first: EXCLUDED_GROUPS_PAGE_SIZE },
      update(data) {
        return data.orbit?.excludedGroups ?? EMPTY_CONNECTION;
      },
      result({ data, errors }) {
        if (!data?.orbit?.excludedGroups) {
          if (errors?.length) {
            this.excludedGroupsError = requestErrorFor({ graphQLErrors: errors }).message;
          }
          return;
        }

        const { pageInfo } = this.excludedGroupsConnection;
        if (pageInfo.hasNextPage) this.fetchNextExcludedGroups(pageInfo.endCursor);
      },
      error(error) {
        if (!error.graphQLErrors.length) {
          this.excludedGroupsError = reportRequestError(error).message;
        }
      },
    },
    status: {
      query: adminServiceStatusQuery,
      update(data) {
        return statusFromServiceStatus(data.orbit?.serviceStatus);
      },
      error(error) {
        this.statusError = reportRequestError(error).message;
      },
    },
  },
  data() {
    return {
      groupsConnection: EMPTY_CONNECTION,
      excludedGroupsConnection: EMPTY_CONNECTION,
      groupsError: null,
      indexStatusError: null,
      excludedGroupsError: null,
      search: '',
      filter: GROUP_FILTER_ALL,
      pageCursor: { first: GROUPS_PAGE_SIZE },
      selectedPaths: [],
      failures: {},
      bulkProgress: null,
      bulkResult: null,
      confirmKind: null,
      confirmTargets: [],
      status: statusFromServiceStatus(null),
      statusError: null,
      settings: {
        [SETTING_AUTO_INDEX]: this.autoIndexEnabled,
        [SETTING_DUO_DEFAULT]: this.duoDefaultEnabled,
      },
      savingSetting: null,
      settingsError: null,
    };
  },
  computed: {
    isExcludedFilter() {
      return this.filter === GROUP_FILTER_EXCLUDED;
    },
    hasAllExcludedGroups() {
      return (
        !this.$apollo.queries.excludedGroupsConnection.loading &&
        !this.excludedGroupsConnection.pageInfo.hasNextPage &&
        !this.excludedGroupsError
      );
    },
    excludedPaths() {
      return new Set(this.excludedGroupsConnection.nodes.map((group) => group.fullPath));
    },
    visibleGroups() {
      return this.isExcludedFilter
        ? filterGroupsBySearch(this.excludedGroupsConnection.nodes, this.search)
        : this.groupsConnection.nodes;
    },
    rows() {
      return buildGroupRows({
        groups: this.visibleGroups,
        excludedPaths: this.excludedPaths,
        failures: this.failures,
        allowedActions: ALL_GROUP_ACTIONS,
      });
    },
    selectedRows() {
      return this.rows.filter((row) => this.selectedPaths.includes(row.fullPath));
    },
    actionItems() {
      return this.hasAllExcludedGroups ? actionItemsFor(this.selectedRows) : [];
    },
    pageInfo() {
      return this.isExcludedFilter ? {} : this.groupsConnection.pageInfo;
    },
    isGroupsLoading() {
      const query = this.isExcludedFilter ? 'excludedGroupsConnection' : 'groupsConnection';
      return this.$apollo.queries[query].loading && !this.bulkProgress;
    },
    tableLoadError() {
      return this.isExcludedFilter ? this.excludedGroupsError : this.groupsError;
    },
    indexStatusWarning() {
      return indexStatusWarningFor(this.rows, this.indexStatusError);
    },
  },
  methods: {
    async fetchNextExcludedGroups(after) {
      try {
        const { data, errors } = await this.$apollo.queries.excludedGroupsConnection.fetchMore({
          variables: { after },
        });
        if (!data?.orbit?.excludedGroups) {
          this.excludedGroupsError = requestErrorFor({ graphQLErrors: errors ?? [] }).message;
        }
      } catch (error) {
        this.excludedGroupsError = reportRequestError(error).message;
      }
    },
    updatePolling() {
      const query = this.$apollo.queries.groupsConnection;
      if (hasActiveIndexing(this.rows)) query.startPolling(INDEXING_POLL_INTERVAL_MS);
      else query.stopPolling();
    },
    showPage({ search = this.search, filter = this.filter, cursor = { first: GROUPS_PAGE_SIZE } }) {
      this.search = search;
      this.filter = filter;
      this.pageCursor = cursor;
      this.selectedPaths = [];
      this.failures = {};
      this.bulkResult = null;
    },
    showPreviousPage(startCursor) {
      this.showPage({ cursor: { last: GROUPS_PAGE_SIZE, before: startCursor } });
    },
    showNextPage(endCursor) {
      this.showPage({ cursor: { first: GROUPS_PAGE_SIZE, after: endCursor } });
    },
    onRetryLoad() {
      if (this.isExcludedFilter) this.refetchExcludedGroups();
      else this.$apollo.queries.groupsConnection.refetch();
    },
    onAction(action) {
      const targets = groupsForAction(this.selectedRows, action);
      const confirmKind = confirmKindFor(action, targets);
      if (action === ACTION_TURN_OFF) this.trackEvent('click_orbit_turn_off_indexing');

      if (confirmKind) {
        this.confirmTargets = targets;
        this.confirmKind = confirmKind;
        return;
      }

      this.runBulkAction(action, targets);
    },
    onSettingChange({ setting, value }) {
      if (setting === SETTING_AUTO_INDEX && value) {
        this.confirmKind = CONFIRM_AUTO_INDEX;
        return;
      }

      this.saveSetting(setting, value);
    },
    onConfirm(kind) {
      if (kind === CONFIRM_AUTO_INDEX) this.saveSetting(SETTING_AUTO_INDEX, true);
      else this.runBulkAction(CONFIRMED_ACTIONS[kind], this.confirmTargets);
    },
    onConfirmClosed() {
      this.confirmKind = null;
      this.confirmTargets = [];
    },
    async runBulkAction(action, targets) {
      if (this.bulkProgress || !targets.length) return;

      this.bulkResult = null;
      this.failures = {};
      this.bulkProgress = startBulkProgress(action, targets);

      const results = await mapWithConcurrency(targets, BULK_ACTION_CONCURRENCY, async (group) => {
        const outcome = await mutateGroup(this.$apollo, { action, group });
        this.bulkProgress = completeBulkProgress(this.bulkProgress, group.fullPath);
        return { group, ...outcome };
      });
      reportFirstRequestError(results);
      const { failures, failedPaths, result } = summarizeBulkAction(action, results);

      this.failures = failures;
      this.selectedPaths = failedPaths;
      this.bulkResult = result;

      await this.refetchGroups();
      this.bulkProgress = null;
    },
    async refetchGroups() {
      const refetches = [this.refetchExcludedGroups()];
      if (!this.isExcludedFilter) refetches.push(this.$apollo.queries.groupsConnection.refetch());

      await Promise.allSettled(refetches);
    },
    // vue-apollo runs `result()` with the cached list after a failed refetch,
    // so only a refetch that returns data clears the error.
    async refetchExcludedGroups() {
      const query = this.$apollo.queries.excludedGroupsConnection;
      const { data } = await query.refetch().catch(() => ({}));
      if (data?.orbit?.excludedGroups) this.excludedGroupsError = null;
    },
    async saveSetting(setting, value) {
      if (this.savingSetting) return;

      this.savingSetting = setting;
      this.settingsError = null;

      try {
        await axios.patch(this.settingsPath, { application_setting: { [setting]: value } });
        this.settings = { ...this.settings, [setting]: value };
      } catch (error) {
        this.settingsError = reportRequestError(error).message;
      } finally {
        this.savingSetting = null;
      }
    },
  },
  SETTING_AUTO_INDEX,
  SETTING_DUO_DEFAULT,
  filterOptions: GROUP_FILTER_OPTIONS,
});
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-6 gl-pb-11 gl-pt-5" data-testid="orbit-admin-page">
    <bulk-result-alert
      v-if="bulkResult"
      :result="bulkResult"
      @dismiss="bulkResult = null"
      @retry="runBulkAction(bulkResult.action, bulkResult.failed)"
    />

    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
      <h1 class="gl-heading-1 gl-my-0 gl-mr-auto">{{ s__('Orbit|GitLab Orbit') }}</h1>
      <gl-button :href="overviewPath">{{ s__('Orbit|Overview') }}</gl-button>
      <gl-button :href="schemaPath">{{ s__('Orbit|Schema') }}</gl-button>
    </div>

    <admin-instance-access />

    <admin-health-card
      :status="status"
      :is-loading="$apollo.queries.status.loading"
      :load-error="statusError"
    />

    <admin-instance-settings
      :auto-index-enabled="settings[$options.SETTING_AUTO_INDEX]"
      :duo-default-enabled="settings[$options.SETTING_DUO_DEFAULT]"
      :saving-setting="savingSetting"
      :save-error="settingsError"
      @change="onSettingChange"
      @dismiss-error="settingsError = null"
    />

    <groups-warnings
      :index-status-error="indexStatusWarning"
      :excluded-groups-error="isExcludedFilter ? null : excludedGroupsError"
    />

    <groups-table
      :title="s__('Orbit|Top-level groups')"
      :description="
        s__(
          'Orbit|Select groups to turn GitLab Orbit on or off, or to exclude them from automatic indexing.',
        )
      "
      :groups="rows"
      :filter-options="$options.filterOptions"
      :selected-paths="selectedPaths"
      :action-items="actionItems"
      :search="search"
      :server-search="!isExcludedFilter"
      :filter="filter"
      :page-info="pageInfo"
      :is-loading="isGroupsLoading"
      :load-error="tableLoadError"
      :bulk-progress="bulkProgress"
      :new-group-path="newGroupPath"
      @search="showPage({ search: $event })"
      @filter="showPage({ filter: $event })"
      @select="selectedPaths = $event"
      @action="onAction"
      @prev="showPreviousPage"
      @next="showNextPage"
      @retry="onRetryLoad"
    />

    <groups-confirm-modal
      :kind="confirmKind"
      :groups="confirmTargets"
      :auto-index-enabled="settings[$options.SETTING_AUTO_INDEX]"
      @confirm="onConfirm"
      @cancel="onConfirmClosed"
    />
  </div>
</template>
