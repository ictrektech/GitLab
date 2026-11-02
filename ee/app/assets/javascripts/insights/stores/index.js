import { defineStore } from 'pinia';
import { pick } from 'lodash-es';
import { INSIGHTS_DATA_SOURCE_DORA } from 'ee/insights/constants';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { __ } from '~/locale';
import { transformChartDataForGlCharts } from './helpers';

export const useInsightsStore = defineStore('insights', {
  state() {
    return {
      configData: null,
      configLoading: true,
      activeTab: null,
      activePage: null,
      chartData: {},
    };
  },
  actions: {
    fetchConfigData(endpoint) {
      this.configData = null;
      this.configLoading = true;

      const receiveConfigError = (errorMessage) => {
        const error = errorMessage || __('Unknown Error');
        const message = `${__('There was an error fetching configuration for charts')}: ${error}`;
        createAlert({
          message,
        });
        this.configData = null;
        this.configLoading = false;
      };

      return axios
        .get(endpoint)
        .then(({ data }) => {
          if (data) {
            this.configData = pick(
              data,
              Object.keys(data).filter((key) => data[key].title && data[key].charts),
            );
            this.configLoading = false;
          } else {
            receiveConfigError();
          }
        })
        .catch((error) => {
          receiveConfigError(error.response.data.message);
        });
    },
    fetchChartData({ endpoint, chart }) {
      return axios
        .post(endpoint, chart)
        .then(({ data }) => {
          const { type, description, query } = chart;

          const { data_source: dataSource } = query;

          const {
            issuable_type: issuableType,
            metric,
            filter_labels: filterLabels = [],
            collection_labels: collectionLabels = [],
            group_by: groupBy,
          } = query.params || {};

          this.chartData[chart.title] = {
            type,
            description,
            data: transformChartDataForGlCharts(chart, data),
            dataSourceType: dataSource === INSIGHTS_DATA_SOURCE_DORA ? metric : issuableType,
            loaded: true,
            filterLabels,
            collectionLabels,
            groupBy,
          };
        })
        .catch((error) => {
          let message = `${__('There was an error gathering the chart data')}`;

          if (error.response.data && error.response.data.message) {
            message += `: ${error.response.data.message}`;
          }
          createAlert({
            message,
          });
          this.chartData[chart.title] = {
            type: chart.type,
            data: {},
            loaded: false,
            error: message,
          };
        });
    },
    setActiveTab(key) {
      const { configData } = this;

      if (configData) {
        const page = configData[key];

        if (page) {
          this.activeTab = key;
          this.activePage = page;
        } else {
          createAlert({
            message: __('The specified tab is invalid, please select another'),
          });
        }
      }
    },
    initChartData(keys) {
      this.chartData = keys.reduce((acc, key) => {
        acc[key] = {};
        return acc;
      }, {});
    },
  },
});
