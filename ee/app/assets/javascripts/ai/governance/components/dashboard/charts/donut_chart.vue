<script>
import { GlLoadingIcon } from '@gitlab/ui';
import { GlChart } from '@gitlab/ui/src/charts';
import { defaultFontFamily } from '@gitlab/ui/src/utils/charts/theme';
import { __, formatNumber, s__, sprintf } from '~/locale';
import {
  DONUT_MAX_SLICES,
  DONUT_OTHER_COLOR,
  DONUT_OTHER_NAME,
  DONUT_SLICE_LIMIT,
  LEGEND_POSITION_BOTTOM,
  LEGEND_POSITION_RIGHT,
  LEGEND_POSITIONS,
} from './constants';
import { foldSlices, integerPercentages, sliceColorMap } from './utils';

const CHART_SIZE = 160;
const CENTER_VALUE_FONT_SIZE = 24;
const CENTER_CAPTION_FONT_SIZE = 12;

export default {
  name: 'DonutChart',
  components: {
    GlChart,
    GlLoadingIcon,
  },
  props: {
    /**
     * Slices to plot. `name` is the stable identity used to pick a colour,
     * `label` is what the reader sees and defaults to `name`.
     */
    slices: {
      type: Array,
      required: true,
      validator: (slices) =>
        slices.every(
          ({ name, label, value }) =>
            typeof name === 'string' &&
            Number.isFinite(value) &&
            (label === undefined || typeof label === 'string'),
        ),
    },
    /** Pre-formatted headline number shown in the centre, for example "190.1K". */
    centerValue: {
      type: String,
      required: true,
    },
    /** What the centre number counts, for example "tool calls". */
    centerCaption: {
      type: String,
      required: true,
    },
    /** Names the chart for screen readers and captions its text alternative. */
    description: {
      type: String,
      required: true,
    },
    legendPosition: {
      type: String,
      required: false,
      default: LEGEND_POSITION_RIGHT,
      validator: (position) => LEGEND_POSITIONS.includes(position),
    },
    showLegendPercentages: {
      type: Boolean,
      required: false,
      default: false,
    },
    /**
     * Individually coloured slices to keep; the remainder folds into "Other".
     * Defaults low for readability, but any value the palette can colour is allowed.
     */
    maxSlices: {
      type: Number,
      required: false,
      default: DONUT_MAX_SLICES,
      validator: (max) => Number.isInteger(max) && max >= 1 && max <= DONUT_SLICE_LIMIT,
    },
    /**
     * Slice name to colour map. Pass it for any dimension with a known value
     * set: it is the only way a slice keeps its hue across a filter change.
     */
    sliceColors: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    /** Keeps the slices in the order given instead of ordering them by value. */
    preserveOrder: {
      type: Boolean,
      required: false,
      default: false,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    emptyText: {
      type: String,
      required: false,
      default: '',
    },
    /**
     * Denominator for slice percentages, defaulting to the sum of the slices. Pass the real
     * total when slices overlap, for example developers who use several agents.
     */
    percentageTotal: {
      type: Number,
      required: false,
      default: null,
    },
  },
  computed: {
    foldedSlices() {
      return foldSlices(this.slices, this.maxSlices, { preserveOrder: this.preserveOrder });
    },
    isEmpty() {
      return this.foldedSlices.length === 0;
    },
    colors() {
      return sliceColorMap(
        this.foldedSlices.map(({ name }) => name),
        { ...this.sliceColors, [DONUT_OTHER_NAME]: DONUT_OTHER_COLOR },
      );
    },
    percentages() {
      const values = this.foldedSlices.map(({ value }) => value);

      if (this.percentageTotal === null) {
        return integerPercentages(values);
      }

      return values.map((value) =>
        this.percentageTotal > 0 ? Math.round((value / this.percentageTotal) * 100) : 0,
      );
    },
    legendItems() {
      return this.foldedSlices.map((slice, index) => ({
        ...slice,
        color: this.colors[slice.name],
        percentage: this.percentages[index],
        formattedValue: formatNumber(slice.value),
      }));
    },
    isLegendBelow() {
      return this.legendPosition === LEGEND_POSITION_BOTTOM;
    },
    layoutClasses() {
      return this.isLegendBelow
        ? 'gl-flex gl-flex-col gl-items-center gl-gap-4'
        : 'gl-flex gl-items-center gl-gap-5';
    },
    legendClasses() {
      return this.isLegendBelow
        ? 'gl-flex gl-flex-wrap gl-justify-center gl-gap-x-4 gl-gap-y-2'
        : 'gl-flex gl-min-w-0 gl-flex-1 gl-flex-col gl-gap-2';
    },
    emptyMessage() {
      return this.emptyText || this.$options.i18n.noData;
    },
    chartData() {
      if (this.isEmpty) {
        return [{ value: 1, itemStyle: { color: DONUT_OTHER_COLOR } }];
      }

      return this.legendItems.map(({ label, value, color }) => ({
        name: label,
        value,
        itemStyle: { color },
      }));
    },
    chartOptions() {
      return {
        tooltip: this.isEmpty
          ? { show: false }
          : { trigger: 'item', confine: true, formatter: this.tooltip },
        // `setOption` merges, so the centre text has to be emitted on every
        // update under a stable id. Omitting it leaves the previous text
        // painted on the chart.
        graphic: [
          {
            id: 'donut-center-value',
            type: 'text',
            left: 'center',
            top: '40%',
            silent: true,
            style: {
              text: this.centerValue,
              fontSize: CENTER_VALUE_FONT_SIZE,
              // Graphics do not inherit the chart theme's textStyle.
              fontFamily: defaultFontFamily,
              fontWeight: 'bold',
              fill: 'var(--gl-text-color-heading)',
              textAlign: 'center',
            },
          },
          {
            id: 'donut-center-caption',
            type: 'text',
            left: 'center',
            top: '56%',
            silent: true,
            style: {
              text: this.centerCaption,
              fontSize: CENTER_CAPTION_FONT_SIZE,
              fontFamily: defaultFontFamily,
              fill: 'var(--gl-text-color-subtle)',
              textAlign: 'center',
            },
          },
        ],
        series: [
          {
            type: 'pie',
            radius: ['62%', '92%'],
            // 2px of surface between slices, per the design system. A lone slice
            // would show the gap as a notch in a closed ring.
            padAngle: this.chartData.length > 1 ? 2 : 0,
            label: { show: false },
            labelLine: { show: false },
            silent: this.isEmpty,
            data: this.chartData,
          },
        ],
      };
    },
  },
  methods: {
    // Shared by the tooltip and the screen-reader list so the two cannot drift. ECharts renders
    // the tooltip as HTML, so it needs escaping; Vue already escapes the list text.
    sliceText(item, { escape = true } = {}) {
      return sprintf(
        this.$options.i18n.tooltip,
        {
          label: item.label,
          value: item.formattedValue,
          percentage: `${item.percentage}%`,
        },
        escape,
      );
    },
    tooltip({ dataIndex }) {
      const item = this.legendItems[dataIndex];

      return item ? this.sliceText(item) : '';
    },
  },
  i18n: {
    noData: __('No data available'),
    tooltip: s__('AiGovernance|%{label}: %{value} (%{percentage})'),
  },
  chartSize: CHART_SIZE,
};
</script>

<template>
  <div>
    <gl-loading-icon v-if="loading" size="md" class="gl-my-6" data-testid="donut-loading" />
    <div v-else :class="layoutClasses">
      <div
        role="img"
        :aria-label="description"
        class="gl-shrink-0"
        :style="{ width: `${$options.chartSize}px` }"
        data-testid="donut-chart"
      >
        <gl-chart :options="chartOptions" :height="$options.chartSize" width="auto" />
      </div>

      <p v-if="isEmpty" class="gl-m-0 gl-text-subtle" data-testid="donut-empty-state">
        {{ emptyMessage }}
      </p>

      <ul
        v-else
        :class="legendClasses"
        class="gl-m-0 gl-list-none gl-p-0"
        data-testid="donut-legend"
      >
        <li
          v-for="item in legendItems"
          :key="item.name"
          class="gl-flex gl-min-w-0 gl-items-center gl-gap-2 gl-text-sm"
          data-testid="donut-legend-item"
        >
          <span
            aria-hidden="true"
            class="gl-h-3 gl-w-3 gl-shrink-0 gl-rounded-sm"
            :style="{ backgroundColor: item.color }"
            data-testid="donut-legend-swatch"
          ></span>
          <span class="gl-truncate" :title="item.label">{{ item.label }}</span>
          <span v-if="showLegendPercentages" class="gl-shrink-0 gl-text-subtle">
            {{ item.percentage }}%
          </span>
        </li>
      </ul>
    </div>

    <ul v-if="!loading && !isEmpty" class="gl-sr-only" data-testid="donut-table">
      <li>{{ description }}</li>
      <li data-testid="donut-table-center">{{ centerValue }} {{ centerCaption }}</li>
      <li v-for="item in legendItems" :key="item.name">
        {{ sliceText(item, { escape: false }) }}
      </li>
    </ul>
  </div>
</template>
