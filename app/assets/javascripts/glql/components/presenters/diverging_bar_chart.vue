<script>
import DivergingBarChart from '~/explore/analytics_dashboards/components/visualizations/diverging_bar_chart.vue';
import {
  dimensionValue,
  dimensionLabelFormatter,
  labelWithParameter,
  baseFieldKeyOf,
} from '../../utils/chart_data';
import { axisFormatterFor, formatCountCompact, unitFor } from '../../utils/value_format';
import { pageOf } from './bar_list/fold_tail';
import DimensionRoutedChart from './chart/dimension_routed_chart.vue';

// The two halves are a pair, so the type takes exactly two metrics rather than
// the "one or more" the shared shell validates by default.
const SERIES_COUNT = 2;

// Counts render thousands as a lowercase `k`, matching the bar list on the same
// dashboard. Other units keep their own axis formatter.
const valueFormatterFor = (metric) => {
  const fieldKey = baseFieldKeyOf(metric);

  return unitFor(fieldKey) === 'count'
    ? (value) => formatCountCompact(value, { lowercaseThousands: true })
    : axisFormatterFor(fieldKey);
};

export default {
  name: 'DivergingBarChartPresenter',
  components: {
    DimensionRoutedChart,
    DivergingBarChart,
  },
  inject: {
    getVisualizationTitle: { default: () => () => '' },
  },
  SERIES_COUNT,
  props: {
    data: {
      required: false,
      type: Object,
      default: () => ({ nodes: [] }),
    },
    fields: {
      required: false,
      type: Array,
      default: () => [],
    },
    loading: {
      required: false,
      type: Boolean,
      default: false,
    },
    /**
     * How many rows each page shows, from the block's `limit`. Null shows all.
     */
    pageSize: {
      required: false,
      type: Number,
      default: null,
    },
  },
  emits: { error: null },
  computed: {
    visualizationTitle() {
      return this.getVisualizationTitle();
    },
  },
  methods: {
    // Labels are formatted against every row, so a date bucket reads the same on every page,
    // and only then sliced to the page.
    rowsFor(dimension, metrics, page) {
      const nodes = this.data?.nodes ?? [];
      const formatLabel = dimensionLabelFormatter(nodes, dimension);
      const rows = nodes.map((node) => ({
        name: formatLabel(dimensionValue(node, dimension)),
        values: metrics.map((metric) => node[metric.key] ?? 0),
      }));

      return this.pageSize ? pageOf(rows, page, this.pageSize) : rows;
    },
    seriesNamesFor(metrics) {
      return metrics.map((metric) => labelWithParameter(metric));
    },
    valueFormattersFor(metrics) {
      return metrics.map(valueFormatterFor);
    },
  },
};
</script>

<template>
  <dimension-routed-chart
    display-type="divergingBarChart"
    :data="data"
    :fields="fields"
    :loading="loading"
    :max-dimensions="1"
    :min-metrics="$options.SERIES_COUNT"
    :max-metrics="$options.SERIES_COUNT"
    :page-size="pageSize"
    @error="$emit('error', $event)"
  >
    <template #one-dimension="{ dimension, metrics, page }">
      <diverging-bar-chart
        :data="rowsFor(dimension, metrics, page)"
        :series-names="seriesNamesFor(metrics)"
        :value-formatters="valueFormattersFor(metrics)"
        :accessible-title="visualizationTitle"
      />
    </template>
  </dimension-routed-chart>
</template>
