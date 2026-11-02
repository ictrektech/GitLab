import { pinia } from '~/pinia/instance';
import { useIssuesAnalytics } from '../stores';
import IssuesAnalyticsChart from './issues_analytics_chart.vue';
import { mockIssueAnalyticsChartData } from './stories_constants';

export default {
  component: IssuesAnalyticsChart,
  title: 'ee/issues_analytics/components/issues_analytics_chart',
};

const createStoryWithState = ({ state = {} }) => {
  return (args, { argTypes }) => {
    const store = useIssuesAnalytics(pinia);
    store.$reset();
    store.$patch({
      loading: false,
      chartData: mockIssueAnalyticsChartData,
      ...state,
    });
    store.fetchChartData = () => Promise.resolve();

    return {
      components: { IssuesAnalyticsChart },
      props: Object.keys(argTypes),
      pinia,
      template: '<issues-analytics-chart v-bind="$props" />',
    };
  };
};

const defaultState = {};
export const Default = createStoryWithState(defaultState).bind({});

const loadingState = { state: { loading: true } };
export const Loading = createStoryWithState(loadingState).bind({});

const noDataState = { state: { chartData: {} } };
export const NoData = createStoryWithState(noDataState).bind({});
