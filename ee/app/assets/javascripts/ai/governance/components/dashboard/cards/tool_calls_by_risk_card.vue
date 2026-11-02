<script>
import { GlAlert, GlCard, GlLink } from '@gitlab/ui';
import {
  GL_COLOR_BLUE_400,
  GL_COLOR_BLUE_500,
  GL_COLOR_NEUTRAL_400,
  GL_COLOR_PURPLE_400,
  GL_COLOR_PURPLE_500,
  GL_COLOR_RED_400,
  GL_COLOR_RED_500,
} from '@gitlab/ui/src/tokens/build/js/tokens';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import { formatNumber, n__, s__, __ } from '~/locale';
import getToolCallsByRiskQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_tool_calls_by_risk.query.graphql';
import { AGENT_CLASS_ALL, TIMEFRAME_LAST_SEVEN_DAYS } from 'ee/ai/governance/constants';
import DonutChart from '../charts/donut_chart.vue';

const RISK_COLORS = {
  READ: GL_COLOR_BLUE_500,
  WRITE: GL_COLOR_PURPLE_500,
  DESTROY: GL_COLOR_RED_500,
  UNCLASSIFIED: GL_COLOR_NEUTRAL_400,
};

// Lighter shades on a dark surface, as the chart theme does for its palettes.
const RISK_COLORS_DARK = {
  READ: GL_COLOR_BLUE_400,
  WRITE: GL_COLOR_PURPLE_400,
  DESTROY: GL_COLOR_RED_400,
  UNCLASSIFIED: GL_COLOR_NEUTRAL_400,
};

export default {
  name: 'ToolCallsByRiskCard',
  components: {
    DonutChart,
    GlAlert,
    GlCard,
    GlLink,
  },
  inject: {
    projectId: { default: null },
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  props: {
    agentClass: {
      type: String,
      required: false,
      default: AGENT_CLASS_ALL,
    },
    timeframe: {
      type: String,
      required: false,
      default: TIMEFRAME_LAST_SEVEN_DAYS,
    },
  },
  apollo: {
    byRisk: {
      query: getToolCallsByRiskQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          timeframe: this.timeframe,
          agentClass: this.agentClass,
        };
      },
      // The field is null when ClickHouse or the backend flag is off.
      update(data) {
        this.hasError = false;
        const namespace = this.isProjectMode ? data.project : data.group;
        return namespace?.aiGovernanceToolCalls?.byRisk ?? null;
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      byRisk: null,
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectId);
    },
    loading() {
      return this.$apollo.queries.byRisk.loading;
    },
    riskLabels() {
      return {
        READ: s__('AiGovernance|Read'),
        WRITE: s__('AiGovernance|Write'),
        DESTROY: s__('AiGovernance|Destructive'),
        UNCLASSIFIED: s__('AiGovernance|Unclassified'),
      };
    },
    // The donut drops zero slices, so Unclassified only shows when it has calls.
    slices() {
      return (this.byRisk?.slices || []).map(({ risk, count }) => ({
        name: risk,
        label: this.riskLabels[risk] || risk,
        value: count,
      }));
    },
    sliceColors() {
      return darkModeEnabled() ? RISK_COLORS_DARK : RISK_COLORS;
    },
    total() {
      return this.byRisk?.total || 0;
    },
    centerValue() {
      return formatNumber(this.total, { notation: 'compact', maximumFractionDigits: 1 });
    },
    centerCaption() {
      return n__('AiGovernance|tool call', 'AiGovernance|tool calls', this.total);
    },
  },
  i18n: {
    title: s__('AiGovernance|Tool calls by action'),
    viewAll: s__('AiGovernance|View all tools in the tool registry'),
    viewAllShort: __('View all'),
    description: s__('AiGovernance|Tool calls by action'),
    empty: s__('AiGovernance|No tool calls in this period.'),
    error: s__('AiGovernance|Failed to load tool calls by action.'),
  },
  viewAllHref: '?tab=tool-management',
};
</script>

<template>
  <gl-card class="gl-h-full" body-class="gl-flex gl-flex-col gl-items-center gl-justify-center">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
        <h2 class="gl-m-0 gl-text-base gl-font-bold">{{ $options.i18n.title }}</h2>
        <gl-link
          :href="$options.viewAllHref"
          :aria-label="$options.i18n.viewAll"
          class="gl-shrink-0"
          data-testid="view-all-link"
          data-event-tracking="click_card_link_on_ai_governance_dashboard"
          data-event-label="tool_calls_by_risk"
          data-event-property="view_all"
        >
          {{ $options.i18n.viewAllShort }}
        </gl-link>
      </div>
    </template>

    <gl-alert v-if="hasError" variant="danger" :dismissible="false">
      {{ $options.i18n.error }}
    </gl-alert>
    <donut-chart
      v-else
      :slices="slices"
      :center-value="centerValue"
      :center-caption="centerCaption"
      :description="$options.i18n.description"
      :slice-colors="sliceColors"
      legend-position="bottom"
      show-legend-percentages
      preserve-order
      :loading="loading"
      :empty-text="$options.i18n.empty"
    />
  </gl-card>
</template>
