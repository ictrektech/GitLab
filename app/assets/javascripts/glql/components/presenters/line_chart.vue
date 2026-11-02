<script>
import DimensionRoutedChart from './chart/dimension_routed_chart.vue';
import SingleDimensionSeriesChart from './chart/single_dimension_series_chart.vue';

export default {
  name: 'LineChartPresenter',
  components: {
    DimensionRoutedChart,
    SingleDimensionSeriesChart,
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
  },
  emits: { error: null },
};
</script>

<template>
  <dimension-routed-chart
    display-type="lineChart"
    :data="data"
    :fields="fields"
    :loading="loading"
    :max-dimensions="1"
    :page-size="pageSize"
    @error="$emit('error', $event)"
  >
    <template #one-dimension="{ dimension, metrics, pageData }">
      <single-dimension-series-chart
        variant="line"
        :data="pageData"
        :dimension="dimension"
        :metrics="metrics"
      />
    </template>
  </dimension-routed-chart>
</template>
