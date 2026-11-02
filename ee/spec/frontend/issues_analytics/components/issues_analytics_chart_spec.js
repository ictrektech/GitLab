import { GlLoadingIcon } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import MockAdapter from 'axios-mock-adapter';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { GlColumnChart } from '@gitlab/ui/src/charts';
import axios from '~/lib/utils/axios_utils';
import IssuesAnalyticsChart from 'ee/issues_analytics/components/issues_analytics_chart.vue';
import IssuesAnalyticsEmptyState from 'ee/issues_analytics/components/issues_analytics_empty_state.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useIssuesAnalytics } from 'ee/issues_analytics/stores';
import { TEST_HOST } from 'helpers/test_constants';

Vue.use(PiniaVuePlugin);

describe('IssuesAnalyticsChart', () => {
  let wrapper;
  let pinia;
  let store;
  let axiosMock;
  const mockChartData = { '2017-11': 0, '2017-12': 2 };
  const mockChartEmptyData = { '2017-11': 0, '2017-12': 0 };
  const mockBarsData = [
    {
      name: 'Issues created',
      data: [
        ['Nov 2017', 0],
        ['Dec 2017', 2],
      ],
    },
  ];
  const mockFilters = { foo: 'bar' };
  const defaultProvide = {
    endpoint: TEST_HOST,
    filterBlockEl: document.querySelector('#mock-filter'),
    filtersEmptyStateSvgPath: 'svg',
  };

  const createComponent = async ({
    provide = defaultProvide,
    loading = false,
    chartData = mockChartData,
    filters = {},
  } = {}) => {
    axiosMock = new MockAdapter(axios);
    pinia = createTestingPinia();
    store = useIssuesAnalytics();
    store.fetchChartData.mockResolvedValue();

    wrapper = shallowMountExtended(IssuesAnalyticsChart, {
      provide,
      pinia,
    });

    store.loading = loading;
    store.chartData = chartData;
    store.filters = filters;

    await nextTick();
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findChartContainer = () => wrapper.findByTestId('issues-analytics-chart-container');
  const findEmptyState = () => wrapper.findComponent(IssuesAnalyticsEmptyState);
  const findColumnChart = () => wrapper.findComponent(GlColumnChart);

  afterEach(() => {
    axiosMock.restore();
  });

  it('fetches chart data when mounted', async () => {
    await createComponent();

    expect(store.fetchChartData).toHaveBeenCalledWith(TEST_HOST);
  });

  it('fetches data when filters are applied', async () => {
    await createComponent({ filters: mockFilters });

    expect(store.fetchChartData).toHaveBeenCalledTimes(2);
    expect(store.fetchChartData).toHaveBeenLastCalledWith(TEST_HOST);
  });

  describe('when there is data', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('renders chart', () => {
      expect(findChartContainer().exists()).toBe(true);
    });

    it('correctly sets the chart `bars` prop', () => {
      expect(findColumnChart().props('bars')).toEqual(mockBarsData);
    });
  });

  it('renders loading state when loading', async () => {
    await createComponent({ loading: true });

    expect(findLoadingIcon().exists()).toBe(true);
    expect(findChartContainer().exists()).toBe(false);
  });

  describe('when chart data is empty', () => {
    describe('and filters have not been applied', () => {
      beforeEach(async () => {
        await createComponent({ chartData: mockChartEmptyData });
      });

      it('should render "no data" empty state', () => {
        expect(findEmptyState().props('emptyStateType')).toBe('noData');
        expect(findChartContainer().exists()).toBe(false);
      });

      it('emits "has-no-data" event', () => {
        expect(wrapper.emitted('has-no-data')).toBeDefined();
      });
    });

    describe('and filters have been applied', () => {
      beforeEach(async () => {
        await createComponent({ chartData: mockChartEmptyData, filters: mockFilters });
      });

      it('should render "filters" empty state', () => {
        expect(findEmptyState().props('emptyStateType')).toBe('noDataWithFilters');
        expect(findChartContainer().exists()).toBe(false);
      });

      it('does not emit "has-no-data" event', () => {
        expect(wrapper.emitted('has-no-data')).toBeUndefined();
      });
    });
  });
});
