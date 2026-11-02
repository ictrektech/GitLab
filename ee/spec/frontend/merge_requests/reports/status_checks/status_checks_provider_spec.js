import MockAdapter from 'axios-mock-adapter';
import { mount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import {
  HTTP_STATUS_OK,
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_UNPROCESSABLE_ENTITY,
} from '~/lib/utils/http_status';
import Poll from '~/lib/utils/poll';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import * as StatusCheckRetryApi from 'ee/api/status_check_api';
import StatusChecksProvider from 'ee/merge_requests/reports/status_checks/status_checks_provider.vue';
import { resetStatusChecksData } from 'ee/merge_requests/reports/status_checks/status_checks_data';
import {
  approvedChecks,
  pendingChecks,
  failedChecks,
  pendingAndFailedChecks,
} from 'ee_jest/ci/reports/status_checks_report/mock_data';

describe('StatusChecksProvider', () => {
  let wrapper;
  let mock;

  const DEFAULT_MR_PROPS = {
    apiStatusChecksPath: '/status_checks',
    targetProjectId: 1,
    iid: 1,
    canRetryExternalStatusChecks: true,
  };

  const InjectedChild = {
    inject: [
      'isStatusChecksLoading',
      'errorMessage',
      'checks',
      'statusIconName',
      'sections',
      'retryFetch',
    ],
    template: `
      <div data-testid="child">
        <span data-testid="is-loading">{{ isStatusChecksLoading }}</span>
        <span data-testid="error-message">{{ errorMessage }}</span>
        <span data-testid="checks-json">{{ JSON.stringify(checks) }}</span>
        <span data-testid="status-icon-name">{{ statusIconName }}</span>
        <span data-testid="sections-count">{{ sections.length }}</span>
        <span data-testid="sections-json">{{ JSON.stringify(sections) }}</span>
        <button data-testid="retry-fetch" @click="retryFetch"></button>
        <template v-if="sections[0]">
          <button
            v-for="child in sections[0].children.filter((c) => c.actions)"
            :key="child.id"
            data-testid="retry-check"
            @click="child.actions[0].onClick"
          ></button>
        </template>
      </div>
    `,
  };

  const mockApi = (statusCode, data, headers = {}) => {
    mock.onGet(DEFAULT_MR_PROPS.apiStatusChecksPath).reply(statusCode, data, headers);
  };

  const createComponent = ({ mr = DEFAULT_MR_PROPS } = {}) => {
    wrapper = mount(StatusChecksProvider, {
      propsData: { mr },
      slots: {
        default: InjectedChild,
      },
    });
  };

  const setupWithResponse = (statusCode, data, headers = {}) => {
    mockApi(statusCode, data, headers);
    createComponent();
    jest.advanceTimersByTime(1);

    return waitForPromises();
  };

  const findByTestId = (testId) => wrapper.find(`[data-testid="${testId}"]`);
  const getTextByTestId = (testId) => findByTestId(testId).text();
  const findIsLoading = () => getTextByTestId('is-loading');
  const findErrorMessage = () => getTextByTestId('error-message');
  const findChecks = () => JSON.parse(getTextByTestId('checks-json'));
  const findStatusIconName = () => getTextByTestId('status-icon-name');
  const findSectionsCount = () => getTextByTestId('sections-count');
  const findSections = () => JSON.parse(getTextByTestId('sections-json'));

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
    resetStatusChecksData();
  });

  describe('data fetching', () => {
    it('does not fetch when the status checks endpoint is missing', async () => {
      createComponent({ mr: {} });
      await waitForPromises();

      expect(mock.history.get).toHaveLength(0);
      expect(findIsLoading()).toBe('false');
    });

    describe('response data', () => {
      it('provides approved, pending, and failed checks', async () => {
        const checks = [...approvedChecks, ...pendingChecks, ...failedChecks];

        mockApi(HTTP_STATUS_OK, checks);
        createComponent();

        expect(findIsLoading()).toBe('true');

        jest.advanceTimersByTime(1);
        await waitForPromises();

        const { approved, pending, failed } = findChecks();

        expect(approved).toHaveLength(1);
        expect(pending).toHaveLength(1);
        expect(failed).toHaveLength(1);
        expect(findIsLoading()).toBe('false');
      });
    });

    describe('error handling', () => {
      it('sets error message, logs to Sentry, clears checks, and sets the error icon when the fetch fails', async () => {
        const sentrySpy = jest.spyOn(Sentry, 'captureException');

        await setupWithResponse(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        expect(findErrorMessage()).toBe('Failed to load status checks');
        expect(sentrySpy).toHaveBeenCalledTimes(1);
        expect(findIsLoading()).toBe('false');
        expect(findChecks()).toEqual({ approved: [], pending: [], failed: [] });
        expect(findStatusIconName()).toBe('error');
      });
    });

    it.each`
      description         | checks                    | icon
      ${'pending'}        | ${pendingChecks}          | ${'neutral'}
      ${'pending+failed'} | ${pendingAndFailedChecks} | ${'warning'}
      ${'all passed'}     | ${approvedChecks}         | ${'success'}
    `('shows the $icon icon for $description checks', async ({ checks, icon }) => {
      await setupWithResponse(HTTP_STATUS_OK, checks);

      expect(findStatusIconName()).toBe(icon);
    });

    describe('sections', () => {
      it('combines approved, pending, and failed checks into a single section', async () => {
        await setupWithResponse(HTTP_STATUS_OK, [
          ...approvedChecks,
          ...pendingChecks,
          ...failedChecks,
        ]);

        expect(findSectionsCount()).toBe('1');
      });

      it('provides no sections when there are no checks', async () => {
        await setupWithResponse(HTTP_STATUS_OK, []);

        expect(findSectionsCount()).toBe('0');
      });

      it('does not include a retry action on failed checks when retries are disabled', async () => {
        mockApi(HTTP_STATUS_OK, failedChecks);
        createComponent({ mr: { ...DEFAULT_MR_PROPS, canRetryExternalStatusChecks: false } });
        jest.advanceTimersByTime(1);
        await waitForPromises();

        const [failedChild] = findSections()[0].children;

        expect(failedChild.actions).toBeUndefined();
      });
    });

    describe('polling', () => {
      it('stops polling once there are no more pending checks', async () => {
        const stopSpy = jest.spyOn(Poll.prototype, 'stop');

        await setupWithResponse(HTTP_STATUS_OK, approvedChecks);

        expect(stopSpy).toHaveBeenCalled();
      });

      it('continues polling while checks are pending', async () => {
        await setupWithResponse(HTTP_STATUS_OK, pendingChecks, { 'poll-interval': 10000 });

        jest.advanceTimersByTime(10000 * 2);
        await waitForPromises();

        expect(mock.history.get).toHaveLength(2);
      });
    });

    describe('multiple providers', () => {
      it('shares a single poller across two mounted providers', async () => {
        mockApi(HTTP_STATUS_OK, approvedChecks);
        const first = mount(StatusChecksProvider, {
          propsData: { mr: DEFAULT_MR_PROPS },
          slots: { default: InjectedChild },
        });
        const second = mount(StatusChecksProvider, {
          propsData: { mr: DEFAULT_MR_PROPS },
          slots: { default: InjectedChild },
        });
        jest.advanceTimersByTime(1);
        await waitForPromises();

        expect(mock.history.get).toHaveLength(1);

        first.destroy();
        second.destroy();
      });

      it('stops polling when the last provider is deactivated by keep-alive', async () => {
        const KeepAliveHost = {
          components: { StatusChecksProvider },
          props: { show: { type: Boolean, required: true } },
          data() {
            return { mr: DEFAULT_MR_PROPS };
          },
          template: `
            <keep-alive>
              <status-checks-provider v-if="show" :mr="mr"><div /></status-checks-provider>
            </keep-alive>
          `,
        };

        mockApi(HTTP_STATUS_OK, pendingChecks, { 'poll-interval': 10000 });
        const host = mount(KeepAliveHost, { propsData: { show: true } });
        jest.advanceTimersByTime(1);
        await waitForPromises();

        expect(mock.history.get).toHaveLength(1);

        await host.setProps({ show: false });
        jest.advanceTimersByTime(10000 * 2);
        await waitForPromises();

        expect(mock.history.get).toHaveLength(1);

        host.destroy();
      });
    });

    describe('retryFetch', () => {
      it('restarts polling when called', async () => {
        await setupWithResponse(HTTP_STATUS_OK, approvedChecks);

        expect(mock.history.get).toHaveLength(1);

        findByTestId('retry-fetch').trigger('click');
        jest.advanceTimersByTime(1);
        await waitForPromises();

        expect(mock.history.get).toHaveLength(2);
      });
    });

    describe('retryStatusCheck', () => {
      const clickRetryCheck = async () => {
        findByTestId('retry-check').trigger('click');
        await waitForPromises();
        jest.advanceTimersByTime(1);
        await waitForPromises();
      };

      it('retries the check and refetches the status checks', async () => {
        const retrySpy = jest
          .spyOn(StatusCheckRetryApi, 'mrStatusCheckRetry')
          .mockResolvedValue({});
        await setupWithResponse(HTTP_STATUS_OK, failedChecks);

        await clickRetryCheck();

        expect(retrySpy).toHaveBeenCalledWith({
          projectId: DEFAULT_MR_PROPS.targetProjectId,
          mergeRequestId: DEFAULT_MR_PROPS.iid,
          externalStatusCheckId: failedChecks[0].id,
        });
        expect(mock.history.get).toHaveLength(2);
      });

      it('logs to Sentry and refetches when the retry fails with a non-422 error', async () => {
        const sentrySpy = jest.spyOn(Sentry, 'captureException');
        jest
          .spyOn(StatusCheckRetryApi, 'mrStatusCheckRetry')
          .mockRejectedValue({ response: { status: HTTP_STATUS_INTERNAL_SERVER_ERROR } });
        await setupWithResponse(HTTP_STATUS_OK, failedChecks);

        await clickRetryCheck();

        expect(sentrySpy).toHaveBeenCalledTimes(1);
        expect(mock.history.get).toHaveLength(2);
      });

      it('refetches without logging to Sentry when the retry fails with a 422', async () => {
        const sentrySpy = jest.spyOn(Sentry, 'captureException');
        jest
          .spyOn(StatusCheckRetryApi, 'mrStatusCheckRetry')
          .mockRejectedValue({ response: { status: HTTP_STATUS_UNPROCESSABLE_ENTITY } });
        await setupWithResponse(HTTP_STATUS_OK, failedChecks);

        await clickRetryCheck();

        expect(sentrySpy).not.toHaveBeenCalled();
        expect(mock.history.get).toHaveLength(2);
      });
    });
  });
});
