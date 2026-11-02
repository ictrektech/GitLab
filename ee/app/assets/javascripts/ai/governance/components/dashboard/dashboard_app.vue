<script>
import { GlSegmentedControl } from '@gitlab/ui';
import { s__, formatNumber, sprintf } from '~/locale';
import { formatDate } from '~/lib/utils/datetime_utility';
import { InternalEvents } from '~/tracking';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import getAiGovernanceMetricsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_metrics.query.graphql';
import {
  AGENT_CLASS_ALL,
  AGENT_CLASS_INTERNAL_DAP,
  AGENT_CLASS_EXTERNAL,
  TIMEFRAME_LAST_SEVEN_DAYS,
  TIMEFRAME_LAST_THIRTY_DAYS,
} from 'ee/ai/governance/constants';
import AuditTrailCard from './cards/audit_trail_card.vue';
import AgentInventoryCard from './cards/agent_inventory_card.vue';
import DeveloperActivityCard from './cards/developer_activity_card.vue';
import McpServerActivityCard from './cards/mcp_server_activity_card.vue';
import ProjectExposureCard from './cards/project_exposure_card.vue';
import SessionDistributionCard from './cards/session_distribution_card.vue';
import SkillguardCard from './cards/skillguard_card.vue';
import ToolCallsCard from './cards/tool_calls_card.vue';
import ToolCallsByRiskCard from './cards/tool_calls_by_risk_card.vue';
import SummaryMetricTile from './summary_metric_tile.vue';

const DEFAULT_TIMEFRAME = TIMEFRAME_LAST_SEVEN_DAYS;
// Tiles whose change badge is a share of the previous period, as in the GA design;
// the agents tile keeps the count.
const PERCENT_DELTA_KEYS = ['sessions', 'tool-calls'];

// Fallback trend used only when there is no series yet (feature flag off or no
// data). Keeps the sparklines from collapsing before real data arrives.
const FALLBACK_TREND = [
  [1, 0],
  [2, 0],
];

// What each summary tile counts, in the words of the API field descriptions.
const HELP_TEXT = {
  agents: s__(
    'AiGovernance|Distinct AI agents with at least one session in the time range. Agentic Chat conversations are not counted.',
  ),
  sessions: s__(
    'AiGovernance|AI sessions started in the time range, including Agentic Chat conversations.',
  ),
  'tool-calls': s__('AiGovernance|Every tool call made by AI agents in the time range.'),
};

export default {
  name: 'AiGovernanceDashboardApp',
  i18n: {
    show: s__('AiGovernance|Show'),
    dateRange: s__('AiGovernance|Date range'),
  },
  components: {
    GlSegmentedControl,
    AuditTrailCard,
    AgentInventoryCard,
    DeveloperActivityCard,
    McpServerActivityCard,
    ProjectExposureCard,
    SessionDistributionCard,
    SkillguardCard,
    ToolCallsCard,
    ToolCallsByRiskCard,
    SummaryMetricTile,
  },
  mixins: [glFeatureFlagsMixin(), InternalEvents.mixin()],
  inject: {
    projectId: { default: null },
    groupFullPath: { default: null },
    projectFullPath: { default: null },
  },
  apollo: {
    metrics: {
      query: getAiGovernanceMetricsQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          timeframe: this.timeframe,
          agentClass: this.agentClass,
          includeToolCalls: this.toolCallsEnabled,
        };
      },
      update(data) {
        const namespace = this.isProjectMode ? data.project : data.group;
        return namespace?.aiGovernanceMetrics || null;
      },
    },
  },
  data() {
    return {
      metrics: null,
      // Bound to the date-range control. Read by the metrics query, the delta
      // label and the cards that accept a timeframe.
      timeframe: DEFAULT_TIMEFRAME,
      // Null until the user picks one, so the default can follow the feature
      // flag. `data()` runs before computed properties, so glFeatures is not
      // readable here.
      selectedAgentClass: null,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectId);
    },
    loading() {
      return this.$apollo.queries.metrics.loading;
    },
    // Gates the extra aggregate on the backend too: the resolver only queries
    // tool calls when the field is in the selection set.
    toolCallsEnabled() {
      return Boolean(this.glFeatures.aiGovernanceToolCalls);
    },
    connectedAgentsFilterEnabled() {
      return Boolean(this.glFeatures.aiGovernanceConnectedAgentsFilter);
    },
    // DAP-only until connected agent ingestion ships (19.5). Showing the
    // control with a single option keeps the segmentation visible and makes
    // the scope of the beta explicit.
    agentClassOptions() {
      const dap = { value: AGENT_CLASS_INTERNAL_DAP, text: s__('AiGovernance|DAP') };

      if (!this.connectedAgentsFilterEnabled) {
        return [dap];
      }

      return [
        { value: AGENT_CLASS_ALL, text: s__('AiGovernance|All agents') },
        dap,
        { value: AGENT_CLASS_EXTERNAL, text: s__('AiGovernance|Connected') },
      ];
    },
    timeframeOptions() {
      return [
        { value: TIMEFRAME_LAST_SEVEN_DAYS, text: s__('AiGovernance|Last 7 days') },
        { value: TIMEFRAME_LAST_THIRTY_DAYS, text: s__('AiGovernance|Last 30 days') },
      ];
    },
    defaultAgentClass() {
      return this.connectedAgentsFilterEnabled ? AGENT_CLASS_ALL : AGENT_CLASS_INTERNAL_DAP;
    },
    // Getter/setter so the unselected default tracks the feature flag.
    agentClass: {
      get() {
        return this.selectedAgentClass ?? this.defaultAgentClass;
      },
      set(value) {
        this.selectedAgentClass = value;
      },
    },
    summaryMetrics() {
      const tiles = [
        this.buildKpiTile(
          'agents',
          s__('AiGovernance|Total number of agents'),
          this.metrics?.agents,
        ),
        this.buildKpiTile(
          'sessions',
          s__('AiGovernance|Total number of agent sessions'),
          this.metrics?.sessions,
        ),
      ];

      if (this.toolCallsEnabled) {
        tiles.push(
          this.buildKpiTile(
            'tool-calls',
            s__('AiGovernance|Total number of tool calls'),
            this.metrics?.toolCalls,
          ),
        );
      }

      return tiles;
    },
    summaryGridClass() {
      return this.toolCallsEnabled
        ? '@sm/panel:gl-grid-cols-2 @lg/panel:gl-grid-cols-3'
        : '@sm/panel:gl-grid-cols-2';
    },
  },
  mounted() {
    this.trackEvent('view_ai_governance_dashboard');
  },
  methods: {
    // Called only from the controls, so the default on load is never counted.
    selectAgentClass(value) {
      if (value === this.agentClass) return;

      this.agentClass = value;
      this.trackFilterChange('agent_class', value);
    },
    selectTimeframe(value) {
      if (value === this.timeframe) return;

      this.timeframe = value;
      this.trackFilterChange('timeframe', value);
    },
    trackFilterChange(filter, value) {
      this.trackEvent('apply_filter_on_ai_governance_dashboard', {
        label: filter,
        property: value.toLowerCase(),
      });
    },
    // Signed change, as a percentage of the previous period for the tiles in
    // PERCENT_DELTA_KEYS. With no previous count, or when the share rounds to
    // zero, the count is shown instead, since the percentage would mislead.
    changeText(key, diff, previousCount) {
      if (PERCENT_DELTA_KEYS.includes(key) && previousCount > 0) {
        const percent = Math.round((diff / previousCount) * 100);
        if (percent !== 0) return `${percent > 0 ? '+' : ''}${formatNumber(percent)}%`;
      }
      return `${diff > 0 ? '+' : ''}${formatNumber(diff)}`;
    },
    // Change plus a period phrase for the selected timeframe, e.g. "+9 this week".
    deltaLabel(change) {
      const templates = {
        LAST_7_DAYS: s__('AiGovernance|%{change} this week'),
        LAST_30_DAYS: s__('AiGovernance|%{change} this month'),
      };
      return sprintf(templates[this.timeframe] || templates.LAST_7_DAYS, { change });
    },
    buildKpiTile(key, label, kpi) {
      const helpText = HELP_TEXT[key];
      if (!kpi) {
        return { key, label, helpText, value: '—', chartData: FALLBACK_TREND };
      }

      const diff = kpi.count - kpi.previousCount;
      let deltaDirection = 'neutral';
      if (diff > 0) deltaDirection = 'up';
      else if (diff < 0) deltaDirection = 'down';

      // Prefer the running total: a monotonic curve reads as growth, where the
      // per-bucket `trend` dips to zero on quiet days and looks like an outage.
      // Falls back to `trend` so the tile still renders if the field is absent.
      const series = kpi.cumulativeTrend?.length ? kpi.cumulativeTrend : kpi.trend || [];
      const chartData = series.map((point) => [
        formatDate(point.bucketStart, 'mmm d', false),
        point.count,
      ]);

      return {
        key,
        label,
        helpText,
        value: formatNumber(kpi.count),
        delta: diff === 0 ? '' : this.deltaLabel(this.changeText(key, diff, kpi.previousCount)),
        deltaDirection,
        chartData: chartData.length ? chartData : FALLBACK_TREND,
      };
    },
  },
};
</script>

<template>
  <div class="gl-mt-5">
    <div class="gl-mb-5 gl-flex gl-flex-wrap gl-items-center gl-gap-x-5 gl-gap-y-3">
      <div class="gl-flex gl-items-center gl-gap-3">
        <span id="ai-gov-agent-class-label" class="gl-text-subtle">{{ $options.i18n.show }}</span>
        <gl-segmented-control
          :value="agentClass"
          :options="agentClassOptions"
          aria-labelledby="ai-gov-agent-class-label"
          data-testid="agent-class-filter"
          @input="selectAgentClass"
        />
      </div>

      <div class="gl-flex gl-items-center">
        <span id="ai-gov-timeframe-label" class="gl-sr-only">{{ $options.i18n.dateRange }}</span>
        <gl-segmented-control
          :value="timeframe"
          :options="timeframeOptions"
          aria-labelledby="ai-gov-timeframe-label"
          data-testid="timeframe-filter"
          @input="selectTimeframe"
        />
      </div>
    </div>

    <div class="gl-mb-5 gl-grid gl-grid-cols-1 gl-gap-5" :class="summaryGridClass">
      <summary-metric-tile
        v-for="metric in summaryMetrics"
        :key="metric.key"
        :data-testid="`summary-metric-${metric.key}`"
        :label="metric.label"
        :value="metric.value"
        :delta="metric.delta"
        :delta-direction="metric.deltaDirection"
        :chart-data="metric.chartData"
        :help-text="metric.helpText"
        :loading="loading"
      />
    </div>

    <div class="gl-grid gl-grid-cols-1 gl-gap-5 @md/panel:gl-grid-cols-2 @lg/panel:gl-grid-cols-3">
      <agent-inventory-card
        :agent-class="agentClass"
        data-testid="dashboard-card-agent-inventory"
      />
      <session-distribution-card
        v-if="glFeatures.aiGovernanceDashboardCharts"
        :agent-class="agentClass"
        :timeframe="timeframe"
        data-testid="dashboard-card-session-distribution"
      />
      <audit-trail-card :agent-class="agentClass" data-testid="dashboard-card-audit-trail" />
      <developer-activity-card
        :agent-class="agentClass"
        :timeframe="timeframe"
        data-testid="dashboard-card-developer-activity"
      />
      <project-exposure-card
        :agent-class="agentClass"
        :timeframe="timeframe"
        data-testid="dashboard-card-project-exposure"
      />
      <skillguard-card
        v-if="glFeatures.aiGovernanceSkillguardWidget"
        data-testid="dashboard-card-skillguard"
      />
      <tool-calls-card
        v-if="toolCallsEnabled"
        :agent-class="agentClass"
        :timeframe="timeframe"
        data-testid="dashboard-card-tool-calls"
      />
      <tool-calls-by-risk-card
        v-if="toolCallsEnabled"
        :agent-class="agentClass"
        :timeframe="timeframe"
        data-testid="dashboard-card-tool-calls-by-risk"
      />
      <mcp-server-activity-card
        v-if="glFeatures.aiGovernanceMcpServerActivity"
        data-testid="dashboard-card-mcp-server-activity"
      />
    </div>
  </div>
</template>
