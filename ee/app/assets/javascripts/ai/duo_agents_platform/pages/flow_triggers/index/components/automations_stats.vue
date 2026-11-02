<script>
import { GlCard, GlSkeletonLoader } from '@gitlab/ui';
import { GlSingleStat, GlSparklineChart } from '@gitlab/ui/src/charts';
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import { fetchPolicies } from '~/lib/graphql';
import getAiFlowTriggerRunStats from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_trigger_run_stats.query.graphql';
import { fillDailyVolume, successRate } from 'ee/ai/duo_agents_platform/utils/run_stats';

export default {
  name: 'AutomationsStats',
  components: {
    GlCard,
    GlSingleStat,
    GlSkeletonLoader,
    GlSparklineChart,
  },
  inject: ['projectPath'],
  data() {
    return {
      runStats: null,
    };
  },
  apollo: {
    runStats: {
      query: getAiFlowTriggerRunStats,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          projectPath: this.projectPath,
        };
      },
      update: (data) => data.project?.aiFlowTriggers?.runStats ?? null,
      error(error) {
        createAlert({
          message: s__('DuoAgentsPlatform|Failed to fetch run statistics.'),
          captureError: true,
          error,
        });
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.runStats.loading;
    },
    successRate() {
      return successRate(this.runStats);
    },
    dailyVolume() {
      return fillDailyVolume(this.runStats.dailyVolume);
    },
  },
  emptyValue: '\u2014',
};
</script>

<template>
  <div
    v-if="isLoading || runStats"
    class="gl-mb-0 gl-mt-5 gl-grid gl-grid-cols-1 gl-gap-4 @md/panel:gl-grid-cols-2 @lg/panel:gl-grid-cols-3"
  >
    <gl-card>
      <gl-skeleton-loader v-if="!runStats" :lines="2" />
      <gl-single-stat
        v-else
        :title="s__('DuoAgentsPlatform|Total runs')"
        :value="runStats.totalRuns"
        :description="s__('DuoAgentsPlatform|Last 30 days')"
        use-delimiters
      />
    </gl-card>
    <gl-card>
      <gl-skeleton-loader v-if="!runStats" :lines="2" />
      <gl-single-stat
        v-else
        :title="s__('DuoAgentsPlatform|Success rate')"
        :value="successRate === null ? $options.emptyValue : successRate"
        :unit="successRate === null ? null : '%'"
        :description="s__('DuoAgentsPlatform|Last 30 days')"
      />
    </gl-card>
    <gl-card class="@md/panel:gl-col-span-2 @lg/panel:gl-col-span-1">
      <gl-skeleton-loader v-if="!runStats" :lines="2" />
      <div v-else class="gl-flex gl-flex-col gl-gap-2 gl-p-2">
        <span class="gl-text-heading">{{ s__('DuoAgentsPlatform|Run volume') }}</span>
        <gl-sparkline-chart
          :data="dailyVolume"
          :height="48"
          :show-last-y-value="false"
          :tooltip-label="s__('DuoAgentsPlatform|Runs')"
        />
        <span class="gl-text-sm gl-text-subtle">{{ s__('DuoAgentsPlatform|Last 30 days') }}</span>
      </div>
    </gl-card>
  </div>
</template>
