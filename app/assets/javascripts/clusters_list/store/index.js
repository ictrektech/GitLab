import { defineStore } from 'pinia';
import { normalizeHeaders, parseBoolean } from '@gitlab/frontend-utils';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { parseIntPagination } from '~/lib/utils/common_utils';
import Poll from '~/lib/utils/poll';
import { s__ } from '~/locale';
import { MAX_REQUESTS } from '../constants';

const allNodesPresent = (clusters, retryCount) => {
  /*
    Nodes are coming from external Kubernetes clusters.
    They may fail for reasons GitLab cannot control.
    MAX_REQUESTS will ensure this poll stops at some point.
  */
  return retryCount > MAX_REQUESTS || clusters.every((cluster) => cluster.nodes != null);
};

export const useClustersList = defineStore('clustersList', {
  state() {
    return {
      ancestorHelperPath: undefined,
      endpoint: undefined,
      hasAncestorClusters: false,
      clusters: [],
      clustersPerPage: 20,
      loadingClusters: true,
      loadingNodes: true,
      page: 1,
      providers: {
        aws: { path: undefined, text: undefined },
        default: { path: undefined, text: undefined },
        gcp: { path: undefined, text: undefined },
      },
      totalClusters: 0,
      canAddCluster: false,
    };
  },
  actions: {
    setInitialState(initialState = {}) {
      this.ancestorHelperPath = initialState.ancestorHelpPath;
      this.endpoint = initialState.endpoint;
      this.providers = {
        aws: { path: initialState.imgTagsAwsPath, text: initialState.imgTagsAwsText },
        default: { path: initialState.imgTagsDefaultPath, text: initialState.imgTagsDefaultText },
        gcp: { path: initialState.imgTagsGcpPath, text: initialState.imgTagsGcpText },
      };
      this.canAddCluster = parseBoolean(initialState.canAddCluster);
    },
    reportSentryError({ error, tag }) {
      Sentry.captureException(error, {
        tags: {
          javascript_clusters_list: tag,
        },
      });
    },
    fetchClusters() {
      let retryCount = 0;

      this.loadingNodes = true;

      const poll = new Poll({
        resource: {
          fetchClusters: (paginatedEndPoint) =>
            axios.get(paginatedEndPoint, {
              params: {
                page: this.page,
                per_page: this.clustersPerPage,
              },
            }),
        },
        data: `${this.endpoint}?page=${this.page}`,
        method: 'fetchClusters',
        successCallback: ({ data, headers }) => {
          retryCount += 1;

          try {
            if (data.clusters) {
              const normalizedHeaders = normalizeHeaders(headers);
              const paginationInformation = parseIntPagination(normalizedHeaders);

              this.clusters = data.clusters;
              this.clustersPerPage = paginationInformation.perPage;
              this.hasAncestorClusters = data.has_ancestor_clusters;
              this.totalClusters = paginationInformation.total;
              this.loadingClusters = false;

              if (allNodesPresent(data.clusters, retryCount)) {
                poll.stop();
                this.loadingNodes = false;
              }
            }
          } catch (error) {
            poll.stop();

            this.loadingClusters = false;
            this.loadingNodes = false;

            this.reportSentryError({ error, tag: 'fetchClustersSuccessCallback' });
          }
        },
        errorCallback: (response) => {
          poll.stop();

          this.loadingClusters = false;
          this.loadingNodes = false;
          createAlert({
            message: s__('Clusters|An error occurred while loading clusters'),
          });

          this.reportSentryError({ error: response, tag: 'fetchClustersErrorCallback' });
        },
      });

      poll.makeRequest();
    },
    setPage(page) {
      this.page = Number(page) || 1;
    },
    setClustersPerPage(limit) {
      this.clustersPerPage = Number(limit) || 1;
    },
  },
});
