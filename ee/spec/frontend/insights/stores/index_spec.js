import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { CHART_TYPES } from 'ee/insights/constants';
import { useInsightsStore } from 'ee/insights/stores';
import { configData } from 'ee_jest/insights/mock_data';
import { TEST_HOST } from 'helpers/test_constants';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR, HTTP_STATUS_OK } from '~/lib/utils/http_status';

const ERROR_MESSAGE = 'TEST_ERROR_MESSAGE';

jest.mock('~/alert');

describe('Insights store', () => {
  let store;
  let mock;

  const key = 'bugsPerTeam';
  const chart = {
    title: 'Bugs Per Team',
    type: CHART_TYPES.STACKED_BAR,
    description: 'Chart Description',
    data_source: 'issuables',
    query: {
      params: {
        name: 'filter_issues_by_label_category',
        filter_labels: ['bug'],
        collection_labels: ['Plan', 'Create', 'Manage'],
        group_by: 'month',
        issuable_type: 'issue',
      },
    },
  };
  const page = {
    title: 'Bugs Charts',
    charts: [chart],
  };

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useInsightsStore();
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
    createAlert.mockClear();
  });

  it('has the initial state', () => {
    expect(store.$state).toEqual({
      configData: null,
      configLoading: true,
      activeTab: null,
      activePage: null,
      chartData: {},
    });
  });

  describe('fetchConfigData', () => {
    describe('when the request succeeds', () => {
      beforeEach(() => {
        mock.onGet(TEST_HOST).reply(HTTP_STATUS_OK, configData);
      });

      it('sets configLoading and resets configData when starting the request', async () => {
        store.configData = { stale: page };
        store.configLoading = false;

        store.fetchConfigData(TEST_HOST);

        expect(store.configLoading).toBe(true);
        expect(store.configData).toBe(null);

        await waitForPromises();
      });

      it('sets configLoading to false on success', async () => {
        store.fetchConfigData(TEST_HOST);
        await waitForPromises();

        expect(store.configLoading).toBe(false);
      });

      it('sets configData to the incoming data without the invalid entries', async () => {
        store.fetchConfigData(TEST_HOST);
        await waitForPromises();

        const expected = { ...configData };
        delete expected.invalid;

        expect(store.configData).toEqual(expected);
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when the request fails', () => {
      beforeEach(() => {
        mock.onGet(TEST_HOST).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR, { message: ERROR_MESSAGE });
      });

      it('resets the config state and shows an alert', async () => {
        store.fetchConfigData(TEST_HOST);
        await waitForPromises();

        expect(store.configLoading).toBe(false);
        expect(store.configData).toBe(null);
        expect(createAlert).toHaveBeenCalledWith({
          message: `There was an error fetching configuration for charts: ${ERROR_MESSAGE}`,
        });
      });
    });

    describe('when the request returns null data', () => {
      beforeEach(() => {
        mock.onGet(TEST_HOST).reply(HTTP_STATUS_OK, null);
      });

      it('resets the config state and shows an `Unknown Error` alert', async () => {
        store.fetchConfigData(TEST_HOST);
        await waitForPromises();

        expect(store.configLoading).toBe(false);
        expect(store.configData).toBe(null);
        expect(createAlert).toHaveBeenCalledWith({
          message: 'There was an error fetching configuration for charts: Unknown Error',
        });
      });
    });
  });

  describe('fetchChartData', () => {
    const payload = { endpoint: `${TEST_HOST}/query`, chart };

    const incomingData = {
      labels: ['January', 'February'],
      datasets: [
        {
          label: 'Dataset 1',
          fill: true,
          backgroundColor: ['rgba(255, 99, 132)'],
          data: [1],
        },
        {
          label: 'Dataset 2',
          fill: true,
          backgroundColor: ['rgba(54, 162, 235)'],
          data: [2],
        },
      ],
    };

    const transformedData = {
      datasets: [
        { name: 'Dataset 1', data: [1] },
        { name: 'Dataset 2', data: [2] },
      ],
      labels: ['January', 'February'],
      xAxisTitle: 'Months',
      yAxisTitle: 'Issues',
      seriesNames: [],
    };

    beforeEach(() => {
      store.initChartData([chart.title]);
    });

    describe('successful request', () => {
      beforeEach(async () => {
        mock.onPost(`${TEST_HOST}/query`, chart).reply(HTTP_STATUS_OK, incomingData);

        store.fetchChartData(payload);
        await waitForPromises();
      });

      it('sets the chart loaded state to true', () => {
        expect(store.chartData[chart.title].loaded).toBe(true);
      });

      it('sets the chart data to the transformed data', () => {
        expect(store.chartData[chart.title].data).toStrictEqual(transformedData);
      });

      it('sets the chart type to the incoming type', () => {
        expect(store.chartData[chart.title].type).toBe(chart.type);
      });

      it('sets the chart description to the incoming description', () => {
        expect(store.chartData[chart.title].description).toBe(chart.description);
      });

      it('sets the chart filterLabels to the incoming filter_labels', () => {
        expect(store.chartData[chart.title].filterLabels).toEqual(chart.query.params.filter_labels);
      });

      it('sets the chart collectionLabels to the incoming collection_labels', () => {
        expect(store.chartData[chart.title].collectionLabels).toEqual(
          chart.query.params.collection_labels,
        );
      });

      it('sets the chart groupBy to the incoming group_by', () => {
        expect(store.chartData[chart.title].groupBy).toEqual(chart.query.params.group_by);
      });

      it('sets the chart dataSourceType to the incoming issuable_type', () => {
        expect(store.chartData[chart.title].dataSourceType).toBe(chart.query.params.issuable_type);
      });

      it('does not show an alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('successful request with the dora data source', () => {
      it('sets the chart dataSourceType to the incoming DORA metric', async () => {
        const doraChart = {
          ...chart,
          query: {
            data_source: 'dora',
            params: { ...chart.query.params, metric: 'deployment_frequency' },
          },
        };
        mock.onPost(`${TEST_HOST}/query`, doraChart).reply(HTTP_STATUS_OK, incomingData);

        store.fetchChartData({ endpoint: `${TEST_HOST}/query`, chart: doraChart });
        await waitForPromises();

        expect(store.chartData[chart.title].dataSourceType).toBe('deployment_frequency');
      });
    });

    describe('failed request', () => {
      const errorMessage = 'There was an error gathering the chart data';

      beforeEach(async () => {
        mock.onPost(`${TEST_HOST}/query`, chart).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        store.fetchChartData(payload);
        await waitForPromises();
      });

      it('shows an alert', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: errorMessage });
      });

      it('sets the chart loaded state to false', () => {
        expect(store.chartData[chart.title].loaded).toBe(false);
      });

      it('sets the chart data to an empty object', () => {
        expect(Object.keys(store.chartData[chart.title].data)).toHaveLength(0);
      });

      it('sets the chart type to the incoming type', () => {
        expect(store.chartData[chart.title].type).toBe(chart.type);
      });

      it('sets the chart error to the error message', () => {
        expect(store.chartData[chart.title].error).toBe(errorMessage);
      });
    });

    describe('failed request with a message from the server', () => {
      it('appends the server message to the error', async () => {
        mock
          .onPost(`${TEST_HOST}/query`, chart)
          .reply(HTTP_STATUS_INTERNAL_SERVER_ERROR, { message: ERROR_MESSAGE });

        store.fetchChartData(payload);
        await waitForPromises();

        expect(store.chartData[chart.title].error).toBe(
          `There was an error gathering the chart data: ${ERROR_MESSAGE}`,
        );
      });
    });
  });

  describe('setActiveTab', () => {
    it('sets the activeTab and activePage', () => {
      store.configData = { [key]: page };

      store.setActiveTab(key);

      expect(store.activeTab).toBe(key);
      expect(store.activePage).toEqual(page);
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('does not change the state with no configData', () => {
      store.configData = null;

      store.setActiveTab(key);

      expect(store.activeTab).toBe(null);
      expect(store.activePage).toBe(null);
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('shows an alert and does not change the state with no matching tab', () => {
      store.configData = { [key]: page };

      store.setActiveTab('invalidTab');

      expect(store.activeTab).toBe(null);
      expect(store.activePage).toBe(null);
      expect(createAlert).toHaveBeenCalledWith({
        message: 'The specified tab is invalid, please select another',
      });
    });
  });

  describe('initChartData', () => {
    it('sets an empty entry for each key', () => {
      store.initChartData(['a', 'b']);

      expect(store.chartData).toEqual({ a: {}, b: {} });
    });
  });
});
