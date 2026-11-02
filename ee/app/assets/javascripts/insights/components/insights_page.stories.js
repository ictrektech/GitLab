import { pinia } from '~/pinia/instance';
import { TEST_HOST } from 'helpers/test_constants';
import {
  pageInfo,
  pageInfoNoCharts,
  createLoadingChartData,
  createLoadedChartData,
} from 'ee_jest/insights/mock_data';
import { useInsightsStore } from '../stores';
import InsightsPage from './insights_page.vue';

export default {
  component: InsightsPage,
  title: 'ee/insights/components/insights_page',
};

const createStoryWithState = ({ state, ...options } = {}) => {
  return (_, { argTypes }) => {
    const store = useInsightsStore(pinia);
    store.$reset();
    store.$patch({
      chartData: createLoadedChartData(),
      ...state,
    });
    // The story only displays the seeded state, so the requests are stubbed.
    store.initChartData = () => {};
    store.fetchChartData = () => {};

    return {
      components: { InsightsPage },
      props: Object.keys(argTypes),
      template: '<insights-page v-bind="$props" />',
      pinia,
      ...options,
    };
  };
};

const defaultProps = {
  queryEndpoint: `${TEST_HOST}/query`,
  pageConfig: pageInfo,
};

export const Default = createStoryWithState();
Default.args = defaultProps;

export const WithNoChartsConfigured = createStoryWithState();
WithNoChartsConfigured.args = {
  ...defaultProps,
  pageConfig: pageInfoNoCharts,
};

export const Loading = createStoryWithState({ state: { chartData: createLoadingChartData() } });
Loading.args = defaultProps;
