<script>
import SingleDimensionBarChart from './bar_chart/single_dimension_bar_chart.vue';
import TwoDimensionsBarChart from './bar_chart/two_dimensions_bar_chart.vue';
import DimensionRoutedChart from './chart/dimension_routed_chart.vue';
import {
  CATEGORY_LABELS_VALUE_AND_SHARE,
  COLOR_BY_OPTIONS,
  COLOR_BY_SERIES,
} from './bar_chart/bar_chart_options';

export default {
  name: 'BarChartPresenter',
  components: {
    DimensionRoutedChart,
    SingleDimensionBarChart,
    TwoDimensionsBarChart,
  },
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
     * How many first-dimension values each page shows, from the block's `limit`. Null shows all.
     */
    pageSize: {
      required: false,
      type: Number,
      default: null,
    },
    displayConfig: {
      required: false,
      type: Object,
      default: () => ({}),
    },
  },
  emits: { error: null },
  computed: {
    shareLabels() {
      return this.displayConfig?.categoryLabels === CATEGORY_LABELS_VALUE_AND_SHARE;
    },
    showAxisTitles() {
      return this.displayConfig?.showAxisTitles !== false;
    },
    colorBy() {
      const value = this.displayConfig?.colorBy;
      return COLOR_BY_OPTIONS.includes(value) ? value : COLOR_BY_SERIES;
    },
  },
};
</script>

<template>
  <dimension-routed-chart
    display-type="barChart"
    :data="data"
    :fields="fields"
    :loading="loading"
    :display-config="displayConfig"
    :page-size="pageSize"
    @error="$emit('error', $event)"
  >
    <template #one-dimension="{ dimension, metrics, stacked, pageData }">
      <single-dimension-bar-chart
        :data="pageData"
        :dimension="dimension"
        :metrics="metrics"
        :stacked="stacked"
        :share-labels="shareLabels"
        :show-axis-titles="showAxisTitles"
        :color-by="colorBy"
      />
    </template>
    <template #two-dimensions="{ dimensions, metric, page }">
      <two-dimensions-bar-chart
        :data="data"
        :primary-dimension="dimensions[0]"
        :secondary-dimension="dimensions[1]"
        :metric="metric"
        :show-axis-titles="showAxisTitles"
        :page="page"
        :page-size="pageSize"
      />
    </template>
  </dimension-routed-chart>
</template>
