<script>
import { GlBadge } from '@gitlab/ui';
import { s__, n__, sprintf, formatNumber } from '~/locale';
import getAiGovernanceToolCallsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_tool_calls.query.graphql';
import {
  ACTION_TYPE_BADGE_VARIANTS,
  AGENT_CLASS_ALL,
  TIMEFRAME_LAST_SEVEN_DAYS,
} from 'ee/ai/governance/constants';
import DashboardListCard from './dashboard_list_card.vue';

export default {
  name: 'ToolCallsCard',
  components: {
    DashboardListCard,
    GlBadge,
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
    toolCalls: {
      query: getAiGovernanceToolCallsQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          timeframe: this.timeframe,
          agentClass: this.agentClass,
        };
      },
      update(data) {
        this.hasError = false;
        const namespace = this.isProjectMode ? data.project : data.group;
        return namespace?.aiGovernanceToolCalls || { nodes: [], approximate: false };
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      toolCalls: { nodes: [], approximate: false },
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectId);
    },
    loading() {
      return this.$apollo.queries.toolCalls.loading;
    },
    tools() {
      return (this.toolCalls?.nodes || []).map((tool) => ({
        key: tool.toolName,
        name: tool.title || tool.toolName,
        actionType: tool.actionType,
        badgeVariant: ACTION_TYPE_BADGE_VARIANTS[tool.actionType],
        callsLabel: sprintf(
          n__('AiGovernance|%{count} call', 'AiGovernance|%{count} calls', tool.count),
          { count: formatNumber(tool.count) },
        ),
      }));
    },
    isApproximate() {
      return Boolean(this.toolCalls?.approximate);
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.tools.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load tool calls.') : '';
    },
  },
  i18n: {
    title: s__('AiGovernance|Top tools by calls'),
    viewAll: s__('AiGovernance|View all tools in tool management'),
    empty: s__('AiGovernance|No tool calls in this period.'),
    approximate: s__('AiGovernance|Counts are approximate on this instance.'),
  },
  viewAllHref: '?tab=tool-management',
};
</script>

<template>
  <dashboard-list-card
    :title="$options.i18n.title"
    :view-all-text="$options.i18n.viewAll"
    :view-all-href="$options.viewAllHref"
    :loading="loading"
    :error-text="errorText"
    :is-empty="isEmpty"
    :empty-text="$options.i18n.empty"
    tracking-label="top_tools"
  >
    <li
      v-for="tool in tools"
      :key="tool.key"
      class="gl-border-b gl-flex gl-items-center gl-justify-between gl-gap-3 gl-border-section gl-p-4 last:gl-border-b-0"
      data-testid="tool-call-row"
    >
      <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-2">
        <span class="gl-truncate gl-font-bold" data-testid="tool-name">{{ tool.name }}</span>
        <gl-badge
          v-if="tool.badgeVariant"
          :variant="tool.badgeVariant"
          class="gl-shrink-0"
          data-testid="tool-action-type"
        >
          {{ tool.actionType }}
        </gl-badge>
      </span>
      <span class="gl-shrink-0 gl-text-sm gl-text-subtle" data-testid="tool-count">{{
        tool.callsLabel
      }}</span>
    </li>
    <li
      v-if="isApproximate"
      class="gl-p-4 gl-text-sm gl-text-subtle"
      data-testid="approximate-note"
    >
      {{ $options.i18n.approximate }}
    </li>
  </dashboard-list-card>
</template>
