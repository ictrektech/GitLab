import { defineStore } from 'pinia';
import { createAlert } from '~/alert';
import { __ } from '~/locale';
import service from '../services/issue_analytics_service';

export const useIssuesAnalytics = defineStore('issuesAnalytics', {
  state() {
    return {
      loading: false,
      filters: {},
      chartData: null,
    };
  },
  getters: {
    hasFilters: (state) => Object.keys(state.filters).length > 0,
    appliedFilters: (state) => state.filters,
  },
  actions: {
    setFilters(value) {
      this.filters = value;
    },
    fetchChartData(endpoint) {
      this.loading = true;

      return service
        .fetchChartData(endpoint, this.appliedFilters)
        .then((res) => res.data)
        .then((data) => {
          this.chartData = data;
        })
        .catch(() =>
          createAlert({
            message: __('An error occurred while loading chart data'),
          }),
        )
        .finally(() => {
          this.loading = false;
        });
    },
  },
});
