import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import axios from '~/lib/utils/axios_utils';
import Poll from '~/lib/utils/poll';
import { HTTP_STATUS_UNPROCESSABLE_ENTITY } from '~/lib/utils/http_status';
import { observable } from '~/lib/utils/observable';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import * as StatusCheckRetryApi from 'ee/api/status_check_api';
import {
  getFailedChecksWithLoadingState,
  mapStatusCheckResponse,
} from 'ee/vue_merge_request_widget/widgets/status_checks/mappers';
import { responseHasPendingChecks } from 'ee/vue_merge_request_widget/widgets/status_checks/utils';

const NO_CHECKS = { approved: [], pending: [], failed: [] };

// The nav item and the routed page both mount a provider. This endpoint asks to
// be polled until no check is pending, which an external service may never
// satisfy, so one poller serves both rather than doubling the request rate.
const state = observable('mr_status_checks_data', {
  isFetching: true,
  errorMessage: '',
  checks: NO_CHECKS,
});

let poll = null;
let consumers = 0;
let mergeRequest = null;

const stop = () => {
  poll?.stop();
  poll = null;
};

const startPolling = () => {
  poll?.stop();

  if (!mergeRequest?.apiStatusChecksPath) {
    state.isFetching = false;
    return;
  }

  state.errorMessage = '';
  state.isFetching = true;

  poll = new Poll({
    resource: {
      fetchData: () => axios.get(mergeRequest.apiStatusChecksPath),
    },
    method: 'fetchData',
    successCallback: (response) => {
      state.isFetching = false;

      if (!responseHasPendingChecks(response)) stop();

      state.checks = mapStatusCheckResponse(
        response,
        { canRetry: mergeRequest.canRetryExternalStatusChecks },
        // The poll embeds the retry handler, and a retry refetches.
        // eslint-disable-next-line no-use-before-define
        (statusCheck) => retryStatusCheck(statusCheck),
      );
    },
    errorCallback: (error) => {
      state.isFetching = false;
      state.errorMessage = s__('StatusCheck|Failed to load status checks');
      Sentry.captureException(error);
    },
  });

  poll.makeDelayedRequest(1);
};

export const retryFetch = startPolling;

async function retryStatusCheck(statusCheck) {
  state.checks = {
    ...state.checks,
    failed: getFailedChecksWithLoadingState(state.checks.failed, statusCheck.id),
  };

  try {
    await StatusCheckRetryApi.mrStatusCheckRetry({
      projectId: mergeRequest.targetProjectId,
      mergeRequestId: mergeRequest.iid,
      externalStatusCheckId: statusCheck.id,
    });
  } catch (error) {
    if (error?.response?.status !== HTTP_STATUS_UNPROCESSABLE_ENTITY) {
      Sentry.captureException(error);
    }
  }

  // Refetch whatever the outcome: a 422 means the check already moved on, and a
  // failed retry still has to clear the row's loading state.
  startPolling();
}

// Only for specs: the state and poller outlive any single component.
export const resetStatusChecksData = () => {
  stop();
  consumers = 0;
  mergeRequest = null;
  state.isFetching = true;
  state.errorMessage = '';
  state.checks = NO_CHECKS;
};

export default {
  data() {
    return { isStatusChecksConsumer: false };
  },
  computed: {
    isStatusChecksLoading() {
      return state.isFetching;
    },
    statusChecksError() {
      return state.errorMessage;
    },
    statusChecks() {
      return state.checks;
    },
    statusChecksSections() {
      const { approved, pending, failed } = state.checks;
      const children = [...approved, ...pending, ...failed];

      if (!children.length) return [];

      return [{ children }];
    },
    statusChecksIcon() {
      if (this.statusChecksError) return EXTENSION_ICONS.error;
      if (this.statusChecks.failed.length > 0) return EXTENSION_ICONS.warning;
      if (this.statusChecks.pending.length > 0) return EXTENSION_ICONS.neutral;

      return EXTENSION_ICONS.success;
    },
  },
  created() {
    this.addStatusChecksConsumer();
  },
  // <keep-alive> caches the routed report page, so it deactivates instead of
  // being destroyed. Without these it would hold its slot in the count forever.
  activated() {
    this.addStatusChecksConsumer();
  },
  deactivated() {
    this.removeStatusChecksConsumer();
  },
  beforeDestroy() {
    this.removeStatusChecksConsumer();
  },
  methods: {
    addStatusChecksConsumer() {
      if (this.isStatusChecksConsumer) return;

      this.isStatusChecksConsumer = true;
      consumers += 1;
      mergeRequest = this.mr;

      if (consumers === 1) startPolling();
    },
    removeStatusChecksConsumer() {
      if (!this.isStatusChecksConsumer) return;

      this.isStatusChecksConsumer = false;
      // Clamped: test teardown can destroy a wrapper after the state was reset.
      consumers = Math.max(consumers - 1, 0);

      if (consumers === 0) stop();
    },
  },
};
