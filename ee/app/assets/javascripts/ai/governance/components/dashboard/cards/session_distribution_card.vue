<script>
import { GlAlert, GlCard, GlLink } from '@gitlab/ui';
import { colorFromDarkPalette, colorFromDefaultPalette } from '@gitlab/ui/src/utils/charts/theme';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import { formatNumber, n__, s__, __ } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import { joinPaths } from '~/lib/utils/url_utility';
import getSessionDistributionQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_session_distribution.query.graphql';
import {
  AGENT_CLASS_ALL,
  AGENT_TYPE_LABELS,
  TIMEFRAME_LAST_SEVEN_DAYS,
} from 'ee/ai/governance/constants';
import DonutChart from '../charts/donut_chart.vue';

// The slice field the chart plots; the query also fetches `sessions`.
const SLICE_METRIC = 'developers';
// Known agents keep one palette colour whichever filter is active; other names follow them.
const STABLE_COLOR_ORDER = ['claude-code', 'gitlab_duo', 'opencode'];
// Matches the API's slice limit, so nothing folds into an "Other" that would double count developers.
const MAX_SLICES = 10;

export default {
  name: 'SessionDistributionCard',
  components: {
    DonutChart,
    GlAlert,
    GlCard,
    GlLink,
  },
  inject: {
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
    sessionDistribution: {
      query: getSessionDistributionQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          agentClass: this.agentClass,
          timeframe: this.timeframe,
        };
      },
      // The field is null when the backend flag is off.
      update(data) {
        this.hasError = false;
        return (data.project ?? data.group)?.aiGovernanceMetrics?.sessionDistribution ?? null;
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      sessionDistribution: null,
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    loading() {
      return this.$apollo.queries.sessionDistribution.loading;
    },
    // `name` is a flow or agent type identifier, so it stays the colour key and
    // only the label changes.
    slices() {
      return (this.sessionDistribution?.slices || []).map((slice) => ({
        name: slice.name,
        label: AGENT_TYPE_LABELS[slice.name] || humanize(slice.name),
        value: slice[SLICE_METRIC],
      }));
    },
    sliceColors() {
      const color = darkModeEnabled() ? colorFromDarkPalette : colorFromDefaultPalette;
      const others = this.slices
        .map(({ name }) => name)
        .filter((name) => !STABLE_COLOR_ORDER.includes(name))
        .sort((a, b) => a.localeCompare(b));

      return Object.fromEntries(
        [...STABLE_COLOR_ORDER, ...others].map((name, index) => [name, color(index)]),
      );
    },
    // A developer can use several agents, so slices can sum to more than this.
    totalDevelopers() {
      return this.sessionDistribution?.totalDevelopers || 0;
    },
    centerValue() {
      return formatNumber(this.totalDevelopers);
    },
    centerCaption() {
      return n__('AiGovernance|developer', 'AiGovernance|developers', this.totalDevelopers);
    },
    viewAllHref() {
      const namespacePath = this.isProjectMode
        ? this.projectFullPath
        : joinPaths('groups', this.groupFullPath);

      return joinPaths('/', namespacePath, '-', 'automate', 'agents');
    },
  },
  i18n: {
    title: s__('AiGovernance|Which AI agents developers are using'),
    viewAll: s__('AiGovernance|View all agents'),
    viewAllShort: __('View all'),
    description: s__('AiGovernance|Developers by AI agent'),
    empty: s__('AiGovernance|No sessions in this period.'),
    error: s__('AiGovernance|Failed to load session distribution.'),
  },
  maxSlices: MAX_SLICES,
};
</script>

<template>
  <gl-card class="gl-h-full" body-class="gl-flex gl-flex-col gl-items-center gl-justify-center">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
        <h2 class="gl-m-0 gl-text-base gl-font-bold">{{ $options.i18n.title }}</h2>
        <gl-link
          :href="viewAllHref"
          :aria-label="$options.i18n.viewAll"
          class="gl-shrink-0"
          data-testid="view-all-link"
          data-event-tracking="click_card_link_on_ai_governance_dashboard"
          data-event-label="session_distribution"
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
      :max-slices="$options.maxSlices"
      :slice-colors="sliceColors"
      :loading="loading"
      :empty-text="$options.i18n.empty"
      :percentage-total="totalDevelopers"
    />
  </gl-card>
</template>
