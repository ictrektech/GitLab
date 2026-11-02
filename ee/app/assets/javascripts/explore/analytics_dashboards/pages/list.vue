<script>
import { GlSkeletonLoader, GlAlert } from '@gitlab/ui';
import { s__ } from '~/locale';
import { joinPaths } from '~/lib/utils/url_utility';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DashboardsList from '~/explore/analytics_dashboards/components/dashboards_list/dashboards_list.vue';
import EmptyState from '~/explore/analytics_dashboards/components/dashboards_list/empty_state.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import { getDashboardIdFromGraphQLId } from '~/explore/analytics_dashboards/utils';
import getDashboardsQuery from '~/explore/analytics_dashboards/graphql/get_dashboards.query.graphql';
import getDuoAgentPlatformTopLevelGroupsQuery from 'ee/explore/analytics_dashboards/graphql/get_duo_agent_platform_top_level_groups.query.graphql';
import IntroBanner from '../components/intro_banner.vue';

export default {
  name: 'ExploreAnalyticsDashboardsListEE',
  components: {
    PageHeading,
    IntroBanner,
    DashboardsList,
    EmptyState,
    GlSkeletonLoader,
    GlAlert,
  },
  inject: ['exploreAnalyticsDashboardsPath'],
  data() {
    return {
      dashboards: [],
      duoAgentPlatformGroups: null,
      errorText: '',
    };
  },
  computed: {
    isLoading() {
      return Boolean(
        this.$apollo.queries.dashboards?.loading ||
        this.$apollo.queries.duoAgentPlatformGroups?.loading,
      );
    },
    // A dashboard whose scope picker would have no group to offer is left out. Only a first page
    // that is the whole list can prove that; anything less keeps it, for its page to explain.
    visibleDashboards() {
      const { nodes, pageInfo } = this.duoAgentPlatformGroups ?? {};
      if (!nodes || pageInfo?.hasNextPage) return this.dashboards;

      return this.dashboards.filter((dashboard) => {
        if (!this.requiresDuoAgentPlatform(dashboard)) return true;

        const permissions = dashboard.config.filters.scope.requirePermissions ?? [];
        return nodes.some((group) =>
          permissions.every((permission) => group.userPermissions?.[permission] !== false),
        );
      });
    },
    hasError() {
      return this.errorText !== '';
    },
    hasDashboards() {
      return Boolean(this.visibleDashboards.length);
    },
    enrichedDashboards() {
      // Enriches the raw results with any FE computed fields we need
      return this.visibleDashboards.map((data) => ({
        ...data,
        dashboardUrl: data.system
          ? joinPaths(this.exploreAnalyticsDashboardsPath, data.slug)
          : joinPaths(
              this.exploreAnalyticsDashboardsPath,
              String(getDashboardIdFromGraphQLId(data.id)),
            ),
      }));
    },
  },
  apollo: {
    dashboards: {
      query: getDashboardsQuery,
      update({ customDashboards }) {
        // `customDashboards` is null when the query is unauthorized fall back to an
        // empty list so the empty state renders instead of erroring.
        return customDashboards?.nodes ?? [];
      },
      error(err) {
        this.errorText = s__(
          'AnalyticsDashboards|Failed to load dashboards list. Please try again.',
        );
        Sentry.captureException(err);
      },
    },
    duoAgentPlatformGroups: {
      query: getDuoAgentPlatformTopLevelGroupsQuery,
      update: ({ groups }) => groups,
      skip() {
        return !this.dashboards.some(this.requiresDuoAgentPlatform);
      },
      error(err) {
        Sentry.captureException(err);
      },
    },
  },
  methods: {
    requiresDuoAgentPlatform(dashboard) {
      return dashboard.config?.filters?.scope?.requireDuoAgentPlatform === true;
    },
  },
};
</script>
<template>
  <div>
    <page-heading :heading="s__('Analytics|GitLab Intelligence')" class="gl-border-b gl-pb-5">
      <template #description>
        {{ s__('AnalyticsDashboards|Keep your teams aligned around the metrics that matter most') }}
      </template>
    </page-heading>

    <intro-banner class="gl-my-5" />

    <gl-skeleton-loader v-if="isLoading" />
    <gl-alert v-else-if="hasError" variant="danger" :dismissible="false">{{ errorText }}</gl-alert>
    <dashboards-list v-else-if="hasDashboards" :dashboards="enrichedDashboards" />
    <empty-state v-else />
  </div>
</template>
