<script>
import { defineComponent } from 'vue';
import { GlAlert, GlButton } from '@gitlab/ui';
import { s__ } from '~/locale';
import { InternalEvents } from '~/tracking';
import { buildGroupStatusRow } from 'ee/orbit/access/group_status';
import { INSTANCE_TEXT, instanceTrialText } from 'ee/orbit/access/instance_text';
import { TURN_ON_ACTION, deniedOnInstance, trialEnded } from 'ee/orbit/access/turn_on_action';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import TrialUnavailableAlert from 'ee/orbit/components/trial/trial_unavailable_alert.vue';
import { mutateGroup } from 'ee/orbit/shared/groups/action_mutations';
import BulkResultAlert from 'ee/orbit/shared/groups/bulk_result_alert.vue';
import GroupsConfirmModal from 'ee/orbit/shared/groups/groups_confirm_modal.vue';
import GroupsTable from 'ee/orbit/shared/groups/groups_table.vue';
import GroupsWarnings from 'ee/orbit/shared/groups/groups_warnings.vue';
import TurnOnConfirmModal from 'ee/orbit/shared/groups/turn_on_confirm_modal.vue';
import {
  ACTION_TURN_OFF,
  ACTION_TURN_ON,
  BULK_ACTION_CONCURRENCY,
  CONFIRM_TURN_OFF,
  GROUP_FILTER_ALL,
  GROUP_FILTER_ON,
} from 'ee/orbit/shared/groups/constants';
import {
  actionItemsFor,
  completeBulkProgress,
  groupsForAction,
  indexStatusWarningFor,
  isIndexingActive,
  mapWithConcurrency,
  reportFirstRequestError,
  reportRequestError,
  startBulkProgress,
  summarizeBulkAction,
  turnOnTrackingLabel,
} from 'ee/orbit/shared/groups/utils';
import { GROUPS_POLL_INTERVAL_MS } from '../constants';
import { GROUP_STATUS_FILTER_OPTIONS, GROUP_STATUS_PAGE_SIZE } from './constants';
import groupStatusGroupsQuery from './graphql/group_status_groups.query.graphql';
import groupStatusIndexingQuery from './graphql/group_status_indexing.query.graphql';

const EMPTY_CONNECTION = { nodes: [], pageInfo: {} };
const groupsOf = (data) => data?.orbit?.allGroups ?? data?.orbit?.memberGroups;
const NO_ACCESS_MESSAGE = s__(
  'Orbit|To change GitLab Orbit for this group, you need the Owner role for the group.',
);
const GROUPS_NOT_KNOWN_MESSAGE = s__(
  'Orbit|GitLab Orbit is not available right now. Try again later.',
);

const LOAD_ERROR_OPTIONS = {
  noAccessMessage: s__(
    'Orbit|You do not have access to the group list. Sign in again, then reload the page.',
  ),
};

export default defineComponent({
  name: 'OrbitGroupStatusPage',
  components: {
    BulkResultAlert,
    ContactSalesButton,
    GlAlert,
    GlButton,
    GroupsConfirmModal,
    GroupsTable,
    GroupsWarnings,
    TrialUnavailableAlert,
    TurnOnConfirmModal,
  },
  mixins: [InternalEvents.mixin()],
  inject: ['documentHidden', 'listAllGroups', 'orbitPlatform'],
  emits: ['groups-changed'],
  apollo: {
    groupsConnection: {
      query: groupStatusGroupsQuery,
      errorPolicy: 'all',
      variables() {
        return {
          listAllGroups: this.listAllGroups,
          search: this.search || null,
          enabled: this.filter === GROUP_FILTER_ON,
          ...this.pageCursor,
        };
      },
      update: (data) => groupsOf(data) ?? EMPTY_CONNECTION,
      result({ data, errors, error }) {
        // After a network error vue-apollo calls error(), then result() with the cached data.
        if (error) return;

        const firstErrorMessage = errors?.[0]?.message ?? null;

        if (!groupsOf(data)) {
          // Without errors, a null `orbit` comes from an older backend (@gl_introduced).
          this.groupsError = firstErrorMessage ?? GROUPS_NOT_KNOWN_MESSAGE;
          return;
        }

        this.groupsError = null;
        this.indexStatusError = firstErrorMessage;
        if (this.rows.some((row) => row.allowedActions.length > 0)) this.canChangeAnyGroup = true;
      },
      error(error) {
        if (!error.graphQLErrors.length) {
          this.groupsError = reportRequestError(error, LOAD_ERROR_OPTIONS).message;
        }
      },
    },
    // Apollo writes each poll result to the normalized cache, which updates the groups query rows.
    // eslint-disable-next-line @gitlab/vue-no-undef-apollo-properties -- manual query, it keeps no data
    indexingGroups: {
      query: groupStatusIndexingQuery,
      manual: true,
      errorPolicy: 'all',
      // The groups query already returned the status. Apollo sends each poll as network-only.
      fetchPolicy: 'cache-only',
      pollInterval: GROUPS_POLL_INTERVAL_MS,
      variables() {
        return { ids: this.indexingGroupIds, first: this.indexingGroupIds.length };
      },
      skip() {
        // Each poll counts toward the Orbit rate limit, so a hidden browser tab does not poll.
        return !this.indexingGroupIds.length || this.documentHidden;
      },
      result({ errors, error }) {
        if (!error) this.pollStatusError = errors?.[0]?.message ?? null;
        this.now = Date.now();
      },
      error(error) {
        if (!error.graphQLErrors.length) {
          this.pollStatusError = reportRequestError(error, LOAD_ERROR_OPTIONS).message;
        }
      },
    },
  },
  data() {
    return {
      groupsConnection: EMPTY_CONNECTION,
      groupsError: null,
      indexStatusError: null,
      pollStatusError: null,
      search: '',
      filter: GROUP_FILTER_ALL,
      pageCursor: { first: GROUP_STATUS_PAGE_SIZE },
      selectedPaths: [],
      failures: {},
      bulkProgress: null,
      bulkResult: null,
      turnOnTargets: [],
      turnOnVisible: false,
      canChangeAnyGroup: false,
      turnOffTargets: [],
      now: Date.now(),
    };
  },
  computed: {
    saas() {
      return this.orbitPlatform.saas;
    },
    rows() {
      return this.groupsConnection.nodes.map((group) =>
        buildGroupStatusRow(group, {
          failure: this.failures[group.fullPath] ?? null,
          now: this.now,
          saas: this.saas,
          isSelfManagedAdmin: this.listAllGroups,
        }),
      );
    },
    managedRows() {
      return this.rows.filter((row) => row.turnOnAction);
    },
    unavailableRow() {
      return (
        this.managedRows.find((row) => row.turnOnAction === TURN_ON_ACTION.UNAVAILABLE) ?? null
      );
    },
    instanceTrialEndsOn() {
      if (this.saas) return null;

      return this.managedRows.find((row) => row.trialEndsOn)?.trialEndsOn ?? null;
    },
    instanceAlert() {
      if (this.saas || !this.managedRows.length) return null;
      if (this.instanceTrialEndsOn) {
        return {
          variant: 'info',
          title: INSTANCE_TEXT.TRIAL_TITLE,
          message: instanceTrialText(this.instanceTrialEndsOn),
        };
      }
      if (this.managedRows.every((row) => trialEnded(row.turnOnAction))) {
        return {
          variant: 'warning',
          title: INSTANCE_TEXT.TRIAL_ENDED_TITLE,
          message: INSTANCE_TEXT.QUERIES_PAUSED,
          sales: true,
        };
      }
      // A group that is on keeps indexing on an instance that is not eligible for a trial.
      if (this.managedRows.every((row) => !row.isOn && deniedOnInstance(row.turnOnAction))) {
        return {
          variant: 'info',
          title: INSTANCE_TEXT.NOT_AVAILABLE_TITLE,
          message: INSTANCE_TEXT.NOT_AVAILABLE,
          sales: true,
        };
      }

      return null;
    },
    indexingGroupIds() {
      return this.rows.filter(isIndexingActive).map((row) => row.id);
    },
    hasRowActions() {
      return this.rows.some((row) => row.creditsDashboardPath || row.showsSales);
    },
    description() {
      if (this.listAllGroups) {
        return s__(
          'Orbit|See the GitLab Orbit status of every top-level group and turn GitLab Orbit on or off.',
        );
      }

      return this.canChangeAnyGroup
        ? s__('Orbit|See the GitLab Orbit status of your groups and turn GitLab Orbit on or off.')
        : s__(
            'Orbit|See the GitLab Orbit status of your groups. To turn GitLab Orbit on or off, ask an Owner of the top-level group.',
          );
    },
    selectedRows() {
      return this.rows.filter((row) => this.selectedPaths.includes(row.fullPath));
    },
    actionItems() {
      return actionItemsFor(this.selectedRows);
    },
    isGroupsLoading() {
      return this.$apollo.queries.groupsConnection.loading && !this.bulkProgress;
    },
    indexStatusWarning() {
      const pollStatusError = this.indexingGroupIds.length ? this.pollStatusError : null;
      return indexStatusWarningFor(this.rows, pollStatusError ?? this.indexStatusError);
    },
    confirmTurnOnGroups() {
      return this.turnOnTargets.map(({ fullPath, name, startsTrial, offer }) => ({
        fullPath,
        name,
        startsTrial,
        offer,
      }));
    },
    turningOn() {
      return this.bulkProgress?.action === ACTION_TURN_ON;
    },
    turnOffConfirmKind() {
      return this.turnOffTargets.length ? CONFIRM_TURN_OFF : null;
    },
    retryTargets() {
      if (!this.bulkResult) return [];

      const failedPaths = this.bulkResult.failed.map(({ fullPath }) => fullPath);
      const failedRows = this.rows.filter((row) => failedPaths.includes(row.fullPath));
      return groupsForAction(failedRows, this.bulkResult.action);
    },
  },
  methods: {
    showPage({
      search = this.search,
      filter = this.filter,
      cursor = { first: GROUP_STATUS_PAGE_SIZE },
    }) {
      this.search = search;
      this.filter = filter;
      this.pageCursor = cursor;
      this.selectedPaths = [];
      this.failures = {};
      this.bulkResult = null;
    },
    showPreviousPage(startCursor) {
      this.showPage({ cursor: { last: GROUP_STATUS_PAGE_SIZE, before: startCursor } });
    },
    showNextPage(endCursor) {
      this.showPage({ cursor: { first: GROUP_STATUS_PAGE_SIZE, after: endCursor } });
    },
    onAction(action) {
      const targets = groupsForAction(this.selectedRows, action);

      if (action === ACTION_TURN_ON) {
        this.turnOnTargets = targets;
        this.turnOnVisible = true;
      } else if (action === ACTION_TURN_OFF) {
        this.trackEvent('click_orbit_turn_off_indexing');
        this.turnOffTargets = targets;
      }
    },
    async onConfirmTurnOn() {
      this.trackEvent('click_orbit_turn_on_from_group_status', {
        label: turnOnTrackingLabel(this.turnOnTargets),
        value: this.turnOnTargets.length,
      });
      await this.runBulkAction(ACTION_TURN_ON, this.turnOnTargets);
      this.turnOnVisible = false;
    },
    onConfirmTurnOff() {
      this.runBulkAction(ACTION_TURN_OFF, this.turnOffTargets);
    },
    // The error hook of the groups query shows a failed refetch.
    refetchGroups() {
      return this.$apollo.queries.groupsConnection.refetch().catch(() => {});
    },
    onRetry() {
      this.runBulkAction(this.bulkResult.action, this.retryTargets);
    },
    async runBulkAction(action, targets) {
      if (this.bulkProgress || !targets.length) return;

      this.bulkResult = null;
      this.failures = {};
      this.bulkProgress = startBulkProgress(action, targets);

      const results = await mapWithConcurrency(targets, BULK_ACTION_CONCURRENCY, async (group) => {
        const outcome = await mutateGroup(this.$apollo, {
          action,
          group,
          noAccessMessage: NO_ACCESS_MESSAGE,
        });
        this.bulkProgress = completeBulkProgress(this.bulkProgress, group.fullPath);
        return { group, ...outcome };
      });
      reportFirstRequestError(results);
      const { failures, failedPaths, result } = summarizeBulkAction(action, results);

      this.failures = failures;
      this.selectedPaths = failedPaths;
      this.bulkResult = result;
      if (failedPaths.length < targets.length) this.$emit('groups-changed');

      await this.refetchGroups();
      this.selectedPaths = this.selectedRows
        .filter((row) => row.allowedActions.length > 0)
        .map((row) => row.fullPath);
      this.bulkProgress = null;
    },
  },
  filterOptions: GROUP_STATUS_FILTER_OPTIONS,
});
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5 gl-pb-11 gl-pt-5" data-testid="orbit-group-status-page">
    <bulk-result-alert
      v-if="bulkResult"
      :result="bulkResult"
      :can-retry="retryTargets.length > 0"
      @dismiss="bulkResult = null"
      @retry="onRetry"
    />

    <gl-alert
      v-if="instanceAlert"
      :variant="instanceAlert.variant"
      :title="instanceAlert.title"
      :dismissible="false"
      data-testid="orbit-group-status-instance-alert"
    >
      {{ instanceAlert.message }}
      <template v-if="instanceAlert.sales" #actions>
        <contact-sales-button glm-content="orbit-group-status" />
      </template>
    </gl-alert>

    <trial-unavailable-alert
      v-if="unavailableRow"
      glm-content="orbit-group-status"
      :namespace-id="unavailableRow.namespaceId"
      :reloading="isGroupsLoading"
      @retry="refetchGroups"
    />

    <groups-warnings
      :index-status-error="indexStatusWarning"
      :can-change-groups="canChangeAnyGroup"
    />

    <groups-table
      :title="s__('Orbit|Groups')"
      :description="description"
      :groups="rows"
      :selectable="canChangeAnyGroup"
      :actions-column="hasRowActions"
      :selected-paths="selectedPaths"
      :action-items="actionItems"
      :search="search"
      server-search
      :filter="filter"
      :filter-options="$options.filterOptions"
      :page-info="groupsConnection.pageInfo"
      :is-loading="isGroupsLoading"
      :load-error="groupsError"
      :bulk-progress="bulkProgress"
      @search="showPage({ search: $event })"
      @filter="showPage({ filter: $event })"
      @select="selectedPaths = $event"
      @action="onAction"
      @prev="showPreviousPage"
      @next="showNextPage"
      @retry="refetchGroups"
    >
      <template #actions="{ group }">
        <contact-sales-button
          v-if="group.showsSales"
          glm-content="orbit-group-status"
          :namespace-id="group.namespaceId"
          size="small"
          data-testid="group-contact-sales"
        />
        <gl-button
          v-else-if="group.creditsDashboardPath"
          size="small"
          :href="group.creditsDashboardPath"
          data-testid="group-view-billing"
        >
          {{ s__('Orbit|View billing') }}
        </gl-button>
      </template>
    </groups-table>

    <turn-on-confirm-modal
      :visible="turnOnVisible"
      :groups="confirmTurnOnGroups"
      :loading="turningOn"
      :instance-trial-ends-on="instanceTrialEndsOn"
      @confirm="onConfirmTurnOn"
      @hide="turnOnVisible = false"
    />

    <groups-confirm-modal
      :kind="turnOffConfirmKind"
      :groups="turnOffTargets"
      :auto-index-enabled="false"
      @confirm="onConfirmTurnOff"
      @cancel="turnOffTargets = []"
    />
  </div>
</template>
