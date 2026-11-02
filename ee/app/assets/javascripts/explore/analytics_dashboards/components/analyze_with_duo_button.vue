<script>
import { safeDump, safeLoad } from 'js-yaml';
import { s__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import {
  dateRangeVariables,
  interpolate,
  previousDateRange,
} from '~/explore/analytics_dashboards/data_sources/glql';
import {
  dateRangeDayCount,
  dateRangeGranularity,
  resolveDateRangeFilter,
} from '~/explore/analytics_dashboards/components/utils';
import { DATE_RANGE_OPTION_LAST_30_DAYS } from '~/explore/analytics_dashboards/components/constants';
import {
  DASHBOARD_CONTEXT_CATEGORY,
  registerExternalContextProvider,
} from 'ee/ai/duo_agentic_chat/context/external_context_store';
import OpenAgenticChatButton from 'ee/ai/shared/widgets/open_agentic_chat_button.vue';

// eslint-disable-next-line @gitlab/require-i18n-strings
const DATA_ANALYST_AGENT = { name: 'Data Analyst' };

const BUTTON_OPTIONS = { variant: 'confirm' };

const TRACKING_EVENT_CLICK = 'click_analyze_with_duo_on_analytics_dashboard';

/* eslint-disable @gitlab/require-i18n-strings */
// Same union and subgroup semantics as the bindings the dashboard scopes its panels with.
// A lone path takes `=`, which standard mode accepts as well. Mixed fields keep `in`, since
// `group = "a" and project in (...)` narrows to the group's projects instead of a union.
const scopeClause = ({ groups, projects }) => {
  const fields = Object.entries({ group: groups, project: projects }).filter(
    ([, paths]) => paths.length,
  );
  const allPaths = fields.flatMap(([, paths]) => paths);

  if (allPaths.length === 1) return `${fields[0][0]} = ${JSON.stringify(allPaths[0])}`;

  return fields
    .map(
      ([field, paths]) => `${field} in (${paths.map((path) => JSON.stringify(path)).join(', ')})`,
    )
    .join(' and ');
};

// A panel with `dateField` gets the date range as a binding, not in its query text. The agent
// reruns the query text, so the range is written in, as the panel runs it.
const dateRangeClause = (field, { startDate, endDate }) =>
  `${field} >= ${JSON.stringify(startDate)} and ${field} <= ${JSON.stringify(endDate)}`;

// GLQL joins filters only with `and`, so the date range and scope can follow the panel's own filters.
const withFilters = (glql, clauses) => {
  const block = safeLoad(glql);
  if (typeof block?.query !== 'string') throw new Error('GLQL panel has no query to filter');

  const query = [block.query.trimEnd(), ...clauses].join(' and ');
  return safeDump({ ...block, query }, { lineWidth: -1 });
};

const CONTEXT_INSTRUCTIONS =
  'You are helping the user analyse the current dashboard. ' +
  'Use the panel queries above as your primary data source when answering questions if possible. ' +
  "When drilling into a number a panel shows, reuse that panel's filters verbatim, change only the aggregation, and mention which panel query you used. " +
  "Each panel's description, when present, defines what that panel counts. " +
  'If the question is not answerable by any of the queries, build your own query and communicate it to the user. ' +
  "Keep the panel queries' group and project filter in any query you build, so the results match the dashboard. " +
  'If none of your tools can return the data the question needs, say that it is not available. Do not estimate it, derive it from unrelated data, or present a number for it. ' +
  'To compare a total with the previous period, run the same panel query again with the dates in `date_range.previous`. ' +
  'Metrics such as `previousPeriodUsersCount` and `returningUsersCount` compare each date bucket with the one before it, so they need a date dimension. To compare whole periods, use buckets as long as the date range, with `origin` set to the start of the previous period. ' +
  'If a query returns an error, fix it and run it again, or say that the number is not available. Only report numbers that a query in this conversation returned, or that you calculated from them, and do not reuse a number from a different metric, filter, or date range. ' +
  'If a result is cut off by a row limit, say that the list is incomplete. ' +
  'To count items such as projects or users, use a count metric such as `projectsCount` or `usersCount`. Do not count the rows of a breakdown, which can repeat an item or include rows with no value for it. ' +
  'When ranking by a field, leave out rows with no value for it unless the user asks for them, such as sessions started outside a project. Still return as many entries as the user asked for. ' +
  'If the question states something about the data, check it against the data first, and correct it if the data shows otherwise. ' +
  'Sort ranked results the way the question asks, and do not describe a list as sorted unless it is.';
/* eslint-enable @gitlab/require-i18n-strings */

export default {
  name: 'AnalyzeWithDuoButton',
  components: {
    OpenAgenticChatButton,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    filters: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    panels: {
      type: Array,
      required: false,
      default: () => [],
    },
    configPrompts: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    resourceId() {
      const { current_user_id: userId } = window.gon ?? {};

      return userId ? convertToGraphQLId(TYPENAME_USER, userId) : null;
    },
    dateRange() {
      return resolveDateRangeFilter(this.filters, DATE_RANGE_OPTION_LAST_30_DAYS);
    },
    dateVariables() {
      return dateRangeVariables(this.dateRange);
    },
    previousDateVariables() {
      return dateRangeVariables(previousDateRange(this.dateRange));
    },
    // The same placeholders the GLQL data source fills before a panel runs
    panelVariables() {
      return {
        ...this.dateVariables,
        dynamicGranularity: dateRangeGranularity(this.dateRange),
        rangeDays: dateRangeDayCount(this.dateRange),
        previousStartDate: this.previousDateVariables.startDate,
      };
    },
    scopePaths() {
      const { groups = [], projects = [] } = this.filters;

      return { groups, projects };
    },
    hasScope() {
      return Boolean(this.scopePaths.groups.length || this.scopePaths.projects.length);
    },
    scopeFilter() {
      return this.hasScope ? scopeClause(this.scopePaths) : null;
    },
    scopeType() {
      const { groups, projects } = this.scopePaths;

      if (groups.length && projects.length) return 'mixed';

      return projects.length ? 'project' : 'group';
    },
    // A panel that can't be scoped is left out rather than reach the agent unscoped
    resolvedPanels() {
      return this.panels
        .map(({ title, tooltip, visualization }) => ({
          title,
          description: tooltip?.description,
          glql: visualization?.data?.query?.glql,
          dateField: visualization?.data?.query?.dateField,
        }))
        .filter(({ glql }) => Boolean(glql))
        .flatMap(({ glql, dateField, ...panel }) => {
          const interpolated = interpolate(glql, this.panelVariables);
          const clauses = [
            dateField && dateRangeClause(dateField, this.dateVariables),
            this.scopeFilter,
          ].filter(Boolean);

          if (!clauses.length) return [{ ...panel, glql: interpolated }];

          try {
            return [{ ...panel, glql: withFilters(interpolated, clauses) }];
          } catch (error) {
            captureException(error, { extra: { panel: panel.title } });
            return [];
          }
        });
    },
    hasContext() {
      return Boolean(
        this.resourceId && this.hasScope && this.resolvedPanels.length && this.configPrompts.length,
      );
    },
    predefinedPrompts() {
      const namespace = [...this.scopePaths.groups, ...this.scopePaths.projects].join(', ');

      return this.configPrompts.map((prompt) => sprintf(prompt, { namespace }, false));
    },
    dashboardContext() {
      if (!this.hasContext) return null;

      return {
        dashboard_scope: this.scopePaths,
        date_range: {
          option: this.filters?.dateRangeOption ?? null,
          start_date: this.dateVariables.startDate,
          end_date: this.dateVariables.endDate,
          previous: {
            start_date: this.previousDateVariables.startDate,
            end_date: this.previousDateVariables.endDate,
          },
        },
        panels: this.resolvedPanels,
        additional_instructions: CONTEXT_INSTRUCTIONS,
      };
    },
  },
  mounted() {
    this.disposeContextProvider = registerExternalContextProvider(
      DASHBOARD_CONTEXT_CATEGORY,
      () => this.dashboardContext,
    );
  },
  beforeDestroy() {
    this.disposeContextProvider?.();
  },
  methods: {
    trackClick() {
      this.trackEvent(TRACKING_EVENT_CLICK, {
        label: this.scopeType,
        value: this.resolvedPanels.length,
      });
    },
  },
  i18n: {
    buttonLabel: s__('AnalyticsDashboards|Analyze with Duo'),
    welcomeMessage: s__('AnalyticsDashboards|Ask me about the data on this dashboard.'),
  },
  DATA_ANALYST_AGENT,
  BUTTON_OPTIONS,
};
</script>
<template>
  <open-agentic-chat-button
    v-if="hasContext"
    :button-text="$options.i18n.buttonLabel"
    :resource-id="resourceId"
    :agent="$options.DATA_ANALYST_AGENT"
    :welcome-message="$options.i18n.welcomeMessage"
    :predefined-prompts="predefinedPrompts"
    :predefined-prompt-tracking-labels="configPrompts"
    :button-options="$options.BUTTON_OPTIONS"
    icon="tanuki-ai"
    @click="trackClick"
  />
</template>
