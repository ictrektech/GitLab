<script>
import { GlBadge, GlButton, GlPopover, GlSkeletonLoader } from '@gitlab/ui';
import { GlSparklineChart } from '@gitlab/ui/src/charts';
import { GL_COLOR_DATA_GREEN_600 } from '@gitlab/ui/src/tokens/build/js/tokens';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';

// Maps the delta direction to a Pajamas badge variant and a trend arrow.
const DELTA_VARIANT = { up: 'success', down: 'danger', neutral: 'muted' };
const DELTA_ICON = { up: 'arrow-up', down: 'arrow-down' };

export default {
  name: 'SummaryMetricTile',
  components: {
    GlBadge,
    GlButton,
    GlPopover,
    GlSkeletonLoader,
    GlSparklineChart,
  },
  props: {
    label: {
      type: String,
      required: true,
    },
    value: {
      type: String,
      required: false,
      default: '—',
    },
    delta: {
      type: String,
      required: false,
      default: '',
    },
    deltaDirection: {
      type: String,
      required: false,
      default: 'neutral',
      validator: (value) => ['up', 'down', 'neutral'].includes(value),
    },
    chartData: {
      type: Array,
      required: false,
      default: () => [],
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    helpText: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return { helpTargetId: uniqueId('summary-metric-help-') };
  },
  computed: {
    helpLabel() {
      return sprintf(s__('AiGovernance|About %{label}'), { label: this.label });
    },
    deltaVariant() {
      return DELTA_VARIANT[this.deltaDirection];
    },
    deltaIcon() {
      return DELTA_ICON[this.deltaDirection];
    },
  },
  chartGradient: [GL_COLOR_DATA_GREEN_600, GL_COLOR_DATA_GREEN_600],
};
</script>

<template>
  <div class="gl-border gl-rounded-base gl-border-section gl-bg-section gl-p-5">
    <div class="gl-flex gl-items-center gl-gap-2 gl-text-subtle">
      <span>{{ label }}</span>
      <template v-if="helpText">
        <gl-button
          :id="helpTargetId"
          category="tertiary"
          size="small"
          icon="information-o"
          :aria-label="helpLabel"
          data-testid="summary-metric-help-icon"
        />
        <gl-popover :target="helpTargetId" :title="label" data-testid="summary-metric-help-popover">
          {{ helpText }}
        </gl-popover>
      </template>
    </div>
    <gl-skeleton-loader v-if="loading" :height="70" data-testid="summary-metric-skeleton">
      <rect width="72" height="28" rx="4" y="6" />
      <rect width="120" height="14" rx="4" y="48" />
    </gl-skeleton-loader>
    <template v-else>
      <div class="gl-mt-3 gl-text-size-h1 gl-font-bold">{{ value }}</div>
      <gl-badge
        v-if="delta"
        :variant="deltaVariant"
        :icon="deltaIcon"
        class="gl-mt-3"
        data-testid="summary-metric-delta"
      >
        {{ delta }}
      </gl-badge>
      <gl-sparkline-chart
        v-if="chartData.length"
        :height="48"
        :data="chartData"
        :show-last-y-value="false"
        :gradient="$options.chartGradient"
        :smooth="0.2"
        class="gl-mt-4 gl-w-full"
        data-testid="summary-metric-chart"
      />
    </template>
  </div>
</template>
