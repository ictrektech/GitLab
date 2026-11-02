import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import waitForPromises from 'helpers/wait_for_promises';
import { MAX_REQUESTS } from '~/clusters_list/constants';
import { useClustersList } from '~/clusters_list/store';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import Poll from '~/lib/utils/poll';
import { apiData } from '../mock_data';

jest.mock('~/alert');

describe('Clusters store', () => {
  let store;

  const paginationInformation = {
    nextPage: 1,
    page: 1,
    perPage: 20,
    previousPage: 1,
    total: apiData.clusters.length,
    totalPages: 1,
  };

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useClustersList();
  });

  describe('setInitialState', () => {
    it('has defaults', () => {
      expect(store.hasAncestorClusters).toBe(false);
      expect(store.clusters).toEqual([]);
      expect(store.clustersPerPage).toBe(20);
      expect(store.loadingClusters).toBe(true);
      expect(store.loadingNodes).toBe(true);
      expect(store.page).toBe(1);
      expect(store.totalClusters).toBe(0);
      expect(store.canAddCluster).toBe(false);
    });

    it('seeds the state from the dataset', () => {
      store.setInitialState({
        ancestorHelpPath: '/ancestor/help',
        endpoint: 'some/endpoint',
        imgTagsAwsPath: '/aws.svg',
        imgTagsAwsText: 'AWS Icon',
        imgTagsDefaultPath: '/default.svg',
        imgTagsDefaultText: 'Default Icon',
        imgTagsGcpPath: '/gcp.svg',
        imgTagsGcpText: 'GCP Icon',
        canAddCluster: 'true',
      });

      expect(store.ancestorHelperPath).toBe('/ancestor/help');
      expect(store.endpoint).toBe('some/endpoint');
      expect(store.providers).toEqual({
        aws: { path: '/aws.svg', text: 'AWS Icon' },
        default: { path: '/default.svg', text: 'Default Icon' },
        gcp: { path: '/gcp.svg', text: 'GCP Icon' },
      });
      expect(store.canAddCluster).toBe(true);
    });

    it('treats a non-true canAddCluster value as false', () => {
      store.setInitialState({ canAddCluster: 'false' });

      expect(store.canAddCluster).toBe(false);
    });
  });

  describe('reportSentryError', () => {
    let captureException;

    beforeEach(() => {
      captureException = jest.spyOn(Sentry, 'captureException');
    });

    afterEach(() => {
      captureException.mockRestore();
    });

    it('should report sentry error', () => {
      const sentryError = new Error('New Sentry Error');
      const tag = 'sentryErrorTag';

      store.reportSentryError({ error: sentryError, tag });

      expect(captureException).toHaveBeenCalledWith(sentryError, {
        tags: {
          javascript_clusters_list: tag,
        },
      });
    });
  });

  describe('setPage', () => {
    it('changes page value', () => {
      store.setPage(123);

      expect(store.page).toBe(123);
    });

    it('falls back to the first page for invalid values', () => {
      store.setPage('abc');

      expect(store.page).toBe(1);
    });
  });

  describe('setClustersPerPage', () => {
    it('changes clustersPerPage value', () => {
      store.setClustersPerPage(123);

      expect(store.clustersPerPage).toBe(123);
    });

    it('falls back to 1 for invalid values', () => {
      store.setClustersPerPage('abc');

      expect(store.clustersPerPage).toBe(1);
    });
  });

  describe('fetchClusters', () => {
    let mock;

    const headers = {
      'x-next-page': 1,
      'x-total': apiData.clusters.length,
      'x-total-pages': 1,
      'x-per-page': 20,
      'x-page': 1,
      'x-prev-page': 1,
    };

    beforeEach(() => {
      mock = new MockAdapter(axios);
      store.setInitialState({ endpoint: apiData.endpoint });
    });

    afterEach(() => mock.restore());

    it('sets the loading nodes flag while requesting', () => {
      store.loadingNodes = false;
      mock.onGet().reply(HTTP_STATUS_OK, apiData, headers);

      store.fetchClusters();

      expect(store.loadingNodes).toBe(true);
    });

    it('sets the clusters data with received response', async () => {
      mock.onGet().reply(HTTP_STATUS_OK, apiData, headers);

      store.fetchClusters();
      await waitForPromises();

      expect(store.clusters).toEqual(apiData.clusters);
      expect(store.clustersPerPage).toBe(paginationInformation.perPage);
      expect(store.hasAncestorClusters).toBe(apiData.has_ancestor_clusters);
      expect(store.totalClusters).toBe(paginationInformation.total);
      expect(store.loadingClusters).toBe(false);
    });

    it('should show alert on API error', async () => {
      mock.onGet().reply(HTTP_STATUS_BAD_REQUEST, 'Not Found');

      store.fetchClusters();
      await waitForPromises();

      expect(store.loadingClusters).toBe(false);
      expect(store.loadingNodes).toBe(false);
      expect(store.reportSentryError).toHaveBeenCalledWith({
        error: new Error('Request failed with status code 400'),
        tag: 'fetchClustersErrorCallback',
      });
      expect(createAlert).toHaveBeenCalledWith({
        message: expect.stringMatching('error'),
      });
    });

    describe('multiple api requests', () => {
      let pollRequest;
      let pollStop;

      const pollInterval = 10;
      const pollHeaders = { 'poll-interval': pollInterval, ...headers };

      beforeEach(() => {
        pollRequest = jest.spyOn(Poll.prototype, 'makeRequest');
        pollStop = jest.spyOn(Poll.prototype, 'stop');

        mock.onGet().reply(HTTP_STATUS_OK, apiData, pollHeaders);
      });

      afterEach(() => {
        pollRequest.mockRestore();
        pollStop.mockRestore();
      });

      it('should stop polling after MAX Requests', async () => {
        store.fetchClusters();
        await waitForPromises();

        expect(store.clusters).toEqual(apiData.clusters);
        expect(store.loadingClusters).toBe(false);
        expect(pollRequest).toHaveBeenCalledTimes(1);
        expect(pollStop).toHaveBeenCalledTimes(0);
        jest.advanceTimersByTime(pollInterval);

        return waitForPromises()
          .then(() => {
            expect(pollRequest).toHaveBeenCalledTimes(2);
            expect(pollStop).toHaveBeenCalledTimes(0);
            jest.advanceTimersByTime(pollInterval);
          })
          .then(() => waitForPromises())
          .then(() => {
            expect(pollRequest).toHaveBeenCalledTimes(MAX_REQUESTS);
            expect(pollStop).toHaveBeenCalledTimes(0);
            jest.advanceTimersByTime(pollInterval);
          })
          .then(() => waitForPromises())
          .then(() => {
            expect(pollRequest).toHaveBeenCalledTimes(MAX_REQUESTS + 1);
            // Stops poll once it exceeds the MAX_REQUESTS limit
            expect(pollStop).toHaveBeenCalledTimes(1);
            expect(store.loadingNodes).toBe(false);
            jest.advanceTimersByTime(pollInterval);
          })
          .then(() => waitForPromises())
          .then(() => {
            // Additional poll requests are not made once pollStop is called
            expect(pollRequest).toHaveBeenCalledTimes(MAX_REQUESTS + 1);
            expect(pollStop).toHaveBeenCalledTimes(1);
          });
      });

      it('should stop polling and report to Sentry when data is invalid', async () => {
        const badApiResponse = { clusters: {} };
        mock.onGet().reply(HTTP_STATUS_OK, badApiResponse, pollHeaders);

        store.fetchClusters();
        await waitForPromises();

        expect(store.clusters).toEqual(badApiResponse.clusters);
        expect(store.loadingClusters).toBe(false);
        expect(store.loadingNodes).toBe(false);
        expect(store.reportSentryError).toHaveBeenCalledWith({
          error: new Error('clusters.every is not a function'),
          tag: 'fetchClustersSuccessCallback',
        });
        expect(pollRequest).toHaveBeenCalledTimes(1);
        expect(pollStop).toHaveBeenCalledTimes(1);
      });
    });
  });
});
