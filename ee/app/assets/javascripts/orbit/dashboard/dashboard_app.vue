<script>
import { computed, defineComponent } from 'vue';
import { GlButton, GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { ERROR_POLICY_ALL, fetchPolicies } from '~/lib/graphql';
import { s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import LocalStorageSync from '~/vue_shared/components/local_storage_sync.vue';
import RouterViewWithSlot from '~/vue_shared/spa/components/router_view_with_slot';
import { ENABLED_MEMBER_NAMESPACES_LIMIT } from 'ee/orbit/utils/namespace_limits';
import { withCache } from 'ee/orbit/utils/orbit_cache';
import {
  groupsIndexingVersion,
  hasPendingProjects,
  isInitialIndexing,
} from 'ee/orbit/utils/orbit_group_state';
import { ACCESS_STATE } from 'ee/orbit/access/constants';
import {
  FEEDBACK_URL,
  GROUPS_POLL_INTERVAL_MS,
  ORBIT_TABS,
  ROUTE_OVERVIEW,
  ROUTE_SCHEMA,
} from './constants';
import dashboardGroupsQuery from './graphql/dashboard_groups.query.graphql';
import itemCountsQuery from './graphql/item_counts.query.graphql';
import ownedTrialsQuery from './graphql/owned_trials.query.graphql';
import OrbitOffPage from './off/orbit_off_page.vue';
import OrbitTopAlerts from './orbit_top_alerts.vue';
import OverviewQuickstart from './overview/overview_quickstart.vue';

export default defineComponent({
  name: 'OrbitDashboardApp',
  components: {
    GlButton,
    GlIcon,
    GlLoadingIcon,
    LocalStorageSync,
    OrbitOffPage,
    OrbitTopAlerts,
    OverviewQuickstart,
    RouterViewWithSlot,
  },
  inject: ['trialAvailable', 'currentUserId'],
  provide() {
    return {
      enabledMemberGroups: computed(() => this.enabledGroups),
      documentHidden: computed(() => this.documentHidden),
      itemCountGroups: computed(() => this.itemCountGroups),
      itemCountsLoading: computed(() => this.itemCountsLoading),
    };
  },
  props: {
    adminConfigurationPath: {
      type: String,
      required: false,
      default: null,
    },
    duoAccessible: {
      type: Boolean,
      required: true,
    },
    orbitSettingsEnabled: {
      type: Boolean,
      required: true,
    },
  },
  apollo: {
    enabledGroups: {
      query: dashboardGroupsQuery,
      variables: { first: ENABLED_MEMBER_NAMESPACES_LIMIT },
      // Keep the group list when Orbit errors on `orbit.indexing` (down or rate
      // limited): the nodes still arrive, only the status is null.
      errorPolicy: ERROR_POLICY_ALL,
      update: (data) => data?.orbit?.memberGroups?.nodes ?? [],
      result({ data, loading, errors }) {
        if (loading) return;

        const groups = data?.orbit?.memberGroups;
        this.enabledGroupsLoaded = true;
        this.enabledGroupsFailed = !groups;
        // Without errors, a null `orbit` comes from an older backend (@gl_introduced), not a failure.
        if (!groups && errors?.length) this.alertGroupsFailure();
      },
      error(error) {
        this.enabledGroupsLoaded = true;
        // With errorPolicy 'all', result() also gets GraphQL errors and alerts for them.
        if (error.graphQLErrors.length || this.hasEnabledGroups) return;

        this.enabledGroupsFailed = true;
        this.alertGroupsFailure(error);
      },
    },
    ownedTrials: {
      query: ownedTrialsQuery,
      skip() {
        return !this.trialAvailable || !this.hasEnabledGroups;
      },
      update: (data) => data.orbit?.groups?.nodes ?? [],
      error(error) {
        // The server already logs GraphQL errors.
        if (!error.graphQLErrors.length) Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      enabledGroups: [],
      enabledGroupsLoaded: false,
      enabledGroupsFailed: false,
      enabledGroupsAlerted: false,
      itemCountGroups: [],
      itemCountsLoading: false,
      ownedTrials: [],
      quickstartClosed: false,
      documentHidden: document.hidden,
    };
  },
  computed: {
    // A refetch after a turn on or off sets `loading` again, and must keep the routed page.
    initialLoading() {
      return !this.enabledGroupsLoaded;
    },
    hasEnabledGroups() {
      return this.enabledGroups.length > 0;
    },
    anyInitialIndexing() {
      return this.enabledGroups.some(isInitialIndexing);
    },
    anyPendingProjects() {
      return this.enabledGroups.some(hasPendingProjects);
    },
    itemCountsVersion() {
      if (this.anyInitialIndexing) return null;

      return groupsIndexingVersion(this.enabledGroups);
    },
    // Only the Overview reads the indexing status, and each poll counts toward the Orbit limit.
    shouldPoll() {
      return (
        (this.anyInitialIndexing || this.anyPendingProjects) &&
        this.isOverviewRoute &&
        !this.documentHidden
      );
    },
    endedTrialNamespaceId() {
      const group = this.ownedTrials.find(
        ({ orbit }) => orbit?.access?.state === ACCESS_STATE.TRIAL_ENDED,
      );

      return group ? getIdFromGraphQLId(group.id) : null;
    },
    isOverviewRoute() {
      return this.$route.name === ROUTE_OVERVIEW;
    },
    isCountsRoute() {
      return [ROUTE_OVERVIEW, ROUTE_SCHEMA].includes(this.$route.name);
    },
    showOffPage() {
      return this.enabledGroupsLoaded && !this.enabledGroupsFailed && !this.hasEnabledGroups;
    },
    showRoutedPage() {
      return !this.isOverviewRoute || this.hasEnabledGroups;
    },
    fillsViewport() {
      if (this.showOffPage) return false;
      if (this.isOverviewRoute) return this.hasEnabledGroups;
      return this.$route.name === ROUTE_SCHEMA;
    },
    showSettings() {
      return Boolean(this.adminConfigurationPath);
    },
    quickstartOpen() {
      return !this.quickstartClosed;
    },
    quickstartStorageKey() {
      return `orbit-quickstart-closed:${this.currentUserId}`;
    },
    tabs() {
      return ORBIT_TABS.map((tab) => {
        const isActive = this.$route.name === tab.route;

        return { ...tab, isActive, trackingEvent: isActive ? null : tab.eventName };
      });
    },
  },
  watch: {
    itemCountsVersion: { handler: 'loadItemCounts', immediate: true },
    isCountsRoute: 'loadItemCounts',
    shouldPoll(poll) {
      if (poll) this.$apollo.queries.enabledGroups.startPolling(GROUPS_POLL_INTERVAL_MS);
      else this.$apollo.queries.enabledGroups.stopPolling();
    },
  },
  mounted() {
    document.addEventListener('visibilitychange', this.onVisibilityChange);
  },
  beforeDestroy() {
    document.removeEventListener('visibilitychange', this.onVisibilityChange);
  },
  methods: {
    onVisibilityChange() {
      this.documentHidden = document.hidden;
    },

    async loadItemCounts() {
      const version = this.itemCountsVersion;
      if (!version || !this.isCountsRoute) return;

      this.itemCountsLoading = true;
      try {
        const groups = await withCache(
          `item-counts:${this.currentUserId}`,
          async () => {
            const { data } = await this.$apollo.query({
              query: itemCountsQuery,
              variables: { first: ENABLED_MEMBER_NAMESPACES_LIMIT },
              fetchPolicy: fetchPolicies.NO_CACHE,
            });
            return data?.orbit?.memberGroups?.nodes ?? [];
          },
          { version },
        );
        if (version === this.itemCountsVersion) this.itemCountGroups = groups;
      } catch (error) {
        if (!error.graphQLErrors?.length) Sentry.captureException(error);
      } finally {
        this.itemCountsLoading = false;
      }
    },

    refetchEnabledGroups() {
      this.$apollo.queries.enabledGroups.refetch();
    },

    setQuickstartOpen(open) {
      this.quickstartClosed = !open;
    },

    alertGroupsFailure(error) {
      if (this.enabledGroupsAlerted) return;

      this.enabledGroupsAlerted = true;
      createAlert({
        message: s__('Orbit|Could not load groups.'),
        error,
        captureError: Boolean(error),
      });
    },
  },
  feedbackUrl: FEEDBACK_URL,
});
</script>

<template>
  <div class="gl-flex gl-flex-col gl-pt-5" :class="{ 'orbit-app-fill-viewport': fillsViewport }">
    <local-storage-sync
      :storage-key="quickstartStorageKey"
      :value="quickstartClosed"
      @input="quickstartClosed = $event"
    />

    <gl-loading-icon
      v-if="initialLoading"
      size="lg"
      class="gl-mt-11"
      :label="s__('Orbit|Loading groups')"
    />

    <orbit-off-page v-else-if="showOffPage" @turned-on="refetchEnabledGroups" />

    <!-- The parts that come and go sit in wrappers that always render. Otherwise Vue 2 moves
         the tabs when they come and go, and the moved tab link loses keyboard focus. -->
    <template v-else>
      <div>
        <orbit-top-alerts
          v-if="isOverviewRoute"
          :enabled-groups="enabledGroups"
          :ended-trial-namespace-id="endedTrialNamespaceId"
        />
      </div>

      <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
        <h1 class="gl-heading-1 gl-mb-0 gl-mt-0">{{ s__('Orbit|GitLab Orbit') }}</h1>
        <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-4">
          <gl-button
            variant="link"
            :href="$options.feedbackUrl"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ s__('Orbit|Leave feedback') }} <gl-icon name="external-link" :size="12" />
          </gl-button>
          <gl-button
            category="tertiary"
            icon="rocket-launch"
            :aria-controls="quickstartOpen ? 'orbit-quickstart' : null"
            :aria-expanded="String(quickstartOpen)"
            data-testid="orbit-quickstart-toggle"
            @click="setQuickstartOpen(!quickstartOpen)"
          >
            {{ s__('Orbit|Quickstart') }}
            <gl-icon :name="quickstartOpen ? 'chevron-up' : 'chevron-down'" />
          </gl-button>
          <gl-button
            v-if="showSettings"
            icon="settings"
            :href="adminConfigurationPath"
            data-testid="orbit-settings-btn"
          >
            {{ s__('Orbit|Settings') }}
          </gl-button>
        </div>
      </div>

      <div>
        <overview-quickstart
          v-if="quickstartOpen"
          class="gl-mt-4"
          :duo-accessible="duoAccessible"
          :orbit-settings-enabled="orbitSettingsEnabled"
          :indexing="anyInitialIndexing"
        />
      </div>

      <div class="gl-border-b gl-mt-3 gl-border-default">
        <ul class="nav gl-tabs-nav">
          <li v-for="tab in tabs" :key="tab.route" class="nav-item">
            <router-link
              :to="{ name: tab.route }"
              exact-path
              class="nav-link gl-tab-nav-item"
              :class="{ 'gl-tab-nav-item-active active': tab.isActive }"
              :data-event-tracking="tab.trackingEvent"
            >
              {{ tab.label }}
            </router-link>
          </li>
        </ul>
      </div>

      <router-view-with-slot v-if="showRoutedPage" #default="{ Component }">
        <component :is="Component" @groups-changed="refetchEnabledGroups" />
      </router-view-with-slot>
    </template>
  </div>
</template>
