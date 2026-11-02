<script>
import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { GlSparklineChart } from '@gitlab/ui/src/charts';
import { fetchPolicies } from '~/lib/graphql';
import { timeIntervalInWords } from '~/lib/utils/datetime/date_format_utility';
import { formatNumber, s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import getAutomationRunStats from 'ee/ai/duo_agents_platform/graphql/queries/get_automation_run_stats.query.graphql';
import { fillDailyVolume, successRate } from 'ee/ai/duo_agents_platform/utils/run_stats';

const EMPTY_VALUE = '\u2014';

export default {
  name: 'AutomationRunStats',
  components: {
    GlAlert,
    GlSkeletonLoader,
    GlSparklineChart,
  },
  inject: ['projectPath'],
  props: {
    automationId: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      runStats: null,
      hasError: false,
    };
  },
  apollo: {
    runStats: {
      query: getAutomationRunStats,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          projectPath: this.projectPath,
          id: this.automationId,
        };
      },
      update: (data) => data.project?.aiFlowTriggers?.nodes[0]?.runStats ?? null,
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    metrics() {
      const { totalRuns, medianDurationSeconds } = this.runStats;
      const rate = successRate(this.runStats);

      return [
        {
          key: 'total-runs',
          label: s__('DuoAgentsPlatform|Total runs'),
          value: formatNumber(totalRuns),
        },
        {
          key: 'success-rate',
          label: s__('DuoAgentsPlatform|Success rate'),
          value: rate === null ? EMPTY_VALUE : `${rate}%`,
        },
        {
          key: 'median-duration',
          label: s__('DuoAgentsPlatform|Median duration'),
          value:
            medianDurationSeconds === null
              ? EMPTY_VALUE
              : timeIntervalInWords(medianDurationSeconds, { abbreviated: true }),
        },
      ];
    },
    dailyVolume() {
      return fillDailyVolume(this.runStats.dailyVolume);
    },
  },
};
</script>

<template>
  <gl-alert v-if="hasError" variant="danger" :dismissible="false" class="gl-mb-5">
    {{ s__('DuoAgentsPlatform|Failed to fetch run statistics.') }}
  </gl-alert>
  <div v-else-if="runStats" class="gl-mb-6">
    <dl class="gl-m-0 gl-grid gl-grid-cols-3 gl-gap-4">
      <div v-for="metric in metrics" :key="metric.key" class="gl-flex gl-flex-col gl-gap-1">
        <dt class="gl-font-normal gl-text-subtle">{{ metric.label }}</dt>
        <dd class="gl-heading-3 gl-m-0" :data-testid="`automation-${metric.key}`">
          {{ metric.value }}
        </dd>
      </div>
    </dl>
    <div v-if="runStats.totalRuns" class="gl-mt-4">
      <span class="gl-text-subtle">{{ s__('DuoAgentsPlatform|Run volume, last 30 days') }}</span>
      <gl-sparkline-chart
        :data="dailyVolume"
        :height="40"
        :show-last-y-value="false"
        :tooltip-label="s__('DuoAgentsPlatform|Runs')"
      />
    </div>
  </div>
  <gl-skeleton-loader v-else-if="$apollo.queries.runStats.loading" :lines="2" class="gl-mb-5" />
</template>
