import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { useAdminSubscription } from 'ee/admin/subscriptions/show/store';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK, HTTP_STATUS_UNAUTHORIZED } from '~/lib/utils/http_status';
import { refreshCurrentPage } from '~/lib/utils/url_utility';

jest.mock('~/lib/utils/url_utility');

describe('Admin Subscription store', () => {
  const licenseRemovalPath = '/license/remove';
  const subscriptionSyncPath = '/subscription/sync';

  let store;
  let axiosMock;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useAdminSubscription();
    axiosMock = new MockAdapter(axios);
  });

  afterEach(() => {
    axiosMock.restore();
  });

  describe('setInitialData', () => {
    it('sets the paths', () => {
      store.setInitialData({ licenseRemovalPath, subscriptionSyncPath });

      expect(store.licenseRemovalPath).toBe(licenseRemovalPath);
      expect(store.subscriptionSyncPath).toBe(subscriptionSyncPath);
    });
  });

  describe('didSyncFail', () => {
    it.each([
      [true, 'SYNC_FAILURE'],
      [false, 'SYNC_PENDING'],
      [false, 'SYNC_SUCCESS'],
      [false, null],
    ])('returns %s when subscriptionSyncStatus is %s', (expected, syncStatus) => {
      store.subscriptionSyncStatus = syncStatus;

      expect(store.didSyncFail).toBe(expected);
    });
  });

  describe('didSyncSucceed', () => {
    it.each([
      [false, 'SYNC_FAILURE'],
      [false, 'SYNC_PENDING'],
      [true, 'SYNC_SUCCESS'],
      [false, null],
    ])('returns %s when subscriptionSyncStatus is %s', (expected, syncStatus) => {
      store.subscriptionSyncStatus = syncStatus;

      expect(store.didSyncSucceed).toBe(expected);
    });
  });

  describe('syncSubscription', () => {
    beforeEach(() => {
      store.setInitialData({ licenseRemovalPath, subscriptionSyncPath });
    });

    it('sets the pending state while the request is in flight', async () => {
      axiosMock.onPost(subscriptionSyncPath).replyOnce(HTTP_STATUS_OK);

      const request = store.syncSubscription();

      expect(store.subscriptionSyncStatus).toBe('SYNC_PENDING');
      expect(store.breakdown.hasAsyncActivity).toBe(true);

      await request;
    });

    it('posts to the subscription sync path', async () => {
      axiosMock.onPost(subscriptionSyncPath).replyOnce(HTTP_STATUS_OK);

      await store.syncSubscription();

      expect(axiosMock.history.post).toHaveLength(1);
      expect(axiosMock.history.post[0].url).toBe(subscriptionSyncPath);
    });

    it.each`
      description   | status                      | expectedStatus
      ${'succeeds'} | ${HTTP_STATUS_OK}           | ${'SYNC_SUCCESS'}
      ${'fails'}    | ${HTTP_STATUS_UNAUTHORIZED} | ${'SYNC_FAILURE'}
    `(
      'sets status to $expectedStatus and shows notifications when the request $description',
      async ({ status, expectedStatus }) => {
        axiosMock.onPost(subscriptionSyncPath).replyOnce(status);

        await store.syncSubscription();

        expect(store.subscriptionSyncStatus).toBe(expectedStatus);
        expect(store.breakdown.hasAsyncActivity).toBe(false);
        expect(store.breakdown.shouldShowNotifications).toBe(true);
      },
    );
  });

  describe('removeLicense', () => {
    beforeEach(() => {
      store.setInitialData({ licenseRemovalPath, subscriptionSyncPath });
    });

    it('sets hasAsyncActivity while the request is in flight', async () => {
      axiosMock.onDelete(licenseRemovalPath).replyOnce(HTTP_STATUS_OK);

      const request = store.removeLicense();

      expect(store.breakdown.hasAsyncActivity).toBe(true);

      await request;
    });

    describe('when the request succeeds', () => {
      beforeEach(async () => {
        axiosMock.onDelete(licenseRemovalPath).replyOnce(HTTP_STATUS_OK);

        await store.removeLicense();
      });

      it('sends a delete request to the license removal path', () => {
        expect(axiosMock.history.delete).toHaveLength(1);
        expect(axiosMock.history.delete[0].url).toBe(licenseRemovalPath);
      });

      it('calls removeLicenseSuccess', () => {
        expect(store.removeLicenseSuccess).toHaveBeenCalledTimes(1);
      });
    });

    describe('when the request fails', () => {
      beforeEach(async () => {
        axiosMock.onDelete(licenseRemovalPath).replyOnce(HTTP_STATUS_UNAUTHORIZED);

        await store.removeLicense();
      });

      it('sets the license error and clears hasAsyncActivity', () => {
        expect(store.breakdown.licenseError).toEqual(
          new Error('Request failed with status code 401'),
        );
        expect(store.breakdown.hasAsyncActivity).toBe(false);
      });

      it('does not call removeLicenseSuccess', () => {
        expect(store.removeLicenseSuccess).not.toHaveBeenCalled();
      });
    });
  });

  describe('removeLicenseSuccess', () => {
    it('clears hasAsyncActivity and refreshes the page', () => {
      store.breakdown.hasAsyncActivity = true;

      store.removeLicenseSuccess();

      expect(store.breakdown.hasAsyncActivity).toBe(false);
      expect(refreshCurrentPage).toHaveBeenCalledTimes(1);
    });
  });

  describe('dismissAlert', () => {
    it('hides notifications and clears the license error', () => {
      store.breakdown.shouldShowNotifications = true;
      store.breakdown.licenseError = new Error('error');

      store.dismissAlert();

      expect(store.breakdown.shouldShowNotifications).toBe(false);
      expect(store.breakdown.licenseError).toBe(null);
    });
  });
});
