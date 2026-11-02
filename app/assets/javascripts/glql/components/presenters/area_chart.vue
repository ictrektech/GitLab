<script>
import TwoDimensionsAreaChart from './area_chart/two_dimensions_area_chart.vue';
import DimensionRoutedChart from './chart/dimension_routed_chart.vue';
import SingleDimensionSeriesChart from './chart/single_dimension_series_chart.vue';

export default {
  name: 'AreaChartPresenter',
  components: {
    DimensionRoutedChart,
    SingleDimensionSeriesChart,
    TwoDimensionsAreaChart,
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
};
</script>

<template>
  <dimension-routed-chart
    display-type="areaChart"
    :data="data"
    :fields="fields"
    :loading="loading"
    :display-config="displayConfig"
    :page-size="pageSize"
    @error="$emit('error', $event)"
  >
    <template #one-dimension="{ dimension, metrics, stacked, pageData }">
      <single-dimension-series-chart
        variant="area"
        :data="pageData"
        :dimension="dimension"
        :metrics="metrics"
        :stacked="stacked"
      />
    </template>
    <template #two-dimensions="{ dimensions, metric, page }">
      <two-dimensions-area-chart
        :data="data"
        :primary-dimension="dimensions[0]"
        :secondary-dimension="dimensions[1]"
        :metric="metric"
        :page="page"
        :page-size="pageSize"
      />
    </template>
  </dimension-routed-chart>
</template>
