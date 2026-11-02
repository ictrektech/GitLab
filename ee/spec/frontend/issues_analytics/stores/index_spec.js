import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { useIssuesAnalytics } from 'ee/issues_analytics/stores';
import { TEST_HOST } from 'helpers/test_constants';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR, HTTP_STATUS_OK } from '~/lib/utils/http_status';

jest.mock('~/alert');

describe('Issues analytics store', () => {
  let store;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useIssuesAnalytics();
  });

  it('has the expected initial state', () => {
    expect(store.loading).toBe(false);
    expect(store.filters).toEqual({});
    expect(store.chartData).toBeNull();
  });

  describe('getters', () => {
    describe('hasFilters', () => {
      it('returns false when there are no filters', () => {
        expect(store.hasFilters).toBe(false);
      });

      it('returns true when filters are set', () => {
        store.filters = { author_username: 'bob' };

        expect(store.hasFilters).toBe(true);
      });
    });

    describe('appliedFilters', () => {
      it('returns the filters', () => {
        const filters = { author_username: 'bob' };
        store.filters = filters;

        expect(store.appliedFilters).toEqual(filters);
      });
    });
  });

  describe('actions', () => {
    describe('setFilters', () => {
      it('adds applied filters to state', () => {
        const filter = '?state=opened&assignee_username=someone';

        store.setFilters(filter);

        expect(store.filters).toEqual(filter);
      });

      it('sets null filters', () => {
        store.setFilters(null);

        expect(store.filters).toBeNull();
      });
    });

    describe('fetchChartData', () => {
      let mock;
      const chartData = { '2017-11': 0, '2017-12': 2 };

      beforeEach(() => {
        mock = new MockAdapter(axios);
      });

      afterEach(() => {
        mock.restore();
      });

      describe('on success', () => {
        beforeEach(() => {
          mock.onGet().reply(HTTP_STATUS_OK, chartData);
        });

        it('sets the loading state while fetching and stores the chart data', async () => {
          const promise = store.fetchChartData(TEST_HOST);

          expect(store.loading).toBe(true);

          await promise;

          expect(store.chartData).toEqual(chartData);
          expect(store.loading).toBe(false);
          expect(createAlert).not.toHaveBeenCalled();
        });

        it('requests the endpoint with the applied filters', async () => {
          store.setFilters({ hello: 'world' });

          await store.fetchChartData(TEST_HOST);

          expect(mock.history.get).toHaveLength(1);
          expect(mock.history.get[0].url).toBe(`${TEST_HOST}?hello=world`);
        });
      });

      describe('on error', () => {
        beforeEach(() => {
          mock.onGet().reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
        });

        it('creates an alert, keeps the chart data untouched and stops loading', async () => {
          await store.fetchChartData(TEST_HOST);

          expect(createAlert).toHaveBeenCalledWith({
            message: 'An error occurred while loading chart data',
          });
          expect(store.chartData).toBeNull();
          expect(store.loading).toBe(false);
        });
      });
    });
  });
});
