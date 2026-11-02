import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { TABLE_TYPE_DEFAULT, TABLE_TYPE_FREE, TABLE_TYPE_TRIAL } from 'ee/billings/constants';
import { useBillingsSubscription } from 'ee/billings/subscriptions/store';
import { mockDataSubscription } from 'ee_jest/billings/mock_data';
import { createAlert } from '~/alert';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_NOT_FOUND, HTTP_STATUS_OK } from '~/lib/utils/http_status';

jest.mock('~/alert');

describe('Billings subscription store', () => {
  let store;
  let mock;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useBillingsSubscription();
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
  });

  describe('isFreePlan', () => {
    it('returns false', () => {
      store.plan = { name: 'Gold', code: 'gold' };

      expect(store.isFreePlan).toBe(false);
    });

    it('returns true', () => {
      store.plan = { name: null, code: null };

      expect(store.isFreePlan).toBe(true);
    });
  });

  describe('tableKey', () => {
    it.each`
      tableKey              | planDesc   | plan
      ${TABLE_TYPE_DEFAULT} | ${'valid'} | ${{ name: 'Premium', code: 'premium' }}
      ${TABLE_TYPE_FREE}    | ${'null'}  | ${{ name: 'Premium', code: null }}
      ${TABLE_TYPE_TRIAL}   | ${'trial'} | ${{ name: 'Premium', code: 'premium', trial: 'true' }}
    `('returns $tableKey with $planDesc plan', ({ tableKey, plan }) => {
      store.plan = plan;

      expect(store.tableKey).toBe(tableKey);
    });
  });

  describe('setNamespaceId', () => {
    it('sets namespaceId', () => {
      expect(store.namespaceId).toBeNull();

      store.setNamespaceId('test');

      expect(store.namespaceId).toBe('test');
    });
  });

  describe('fetchSubscription', () => {
    beforeEach(() => {
      gon.api_version = 'v4';
      store.namespaceId = 1;
    });

    describe('on success', () => {
      beforeEach(() => {
        mock
          .onGet(/\/api\/v4\/namespaces\/\d+\/gitlab_subscription(.*)$/)
          .replyOnce(HTTP_STATUS_OK, mockDataSubscription.gold);
      });

      it('requests the subscription and handles the success', async () => {
        jest.spyOn(store, 'requestSubscription');
        jest.spyOn(store, 'receiveSubscriptionSuccess');

        await store.fetchSubscription();

        expect(store.requestSubscription).toHaveBeenCalledTimes(1);
        expect(store.receiveSubscriptionSuccess).toHaveBeenCalledWith(mockDataSubscription.gold);
      });
    });

    describe('on error', () => {
      beforeEach(() => {
        mock
          .onGet(/\/api\/v4\/namespaces\/\d+\/gitlab_subscription(.*)$/)
          .replyOnce(HTTP_STATUS_NOT_FOUND, {});
      });

      it('requests the subscription and handles the error', async () => {
        jest.spyOn(store, 'requestSubscription');
        jest.spyOn(store, 'receiveSubscriptionError');

        await store.fetchSubscription();

        expect(store.requestSubscription).toHaveBeenCalledTimes(1);
        expect(store.receiveSubscriptionError).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('requestSubscription', () => {
    beforeEach(() => {
      store.hasErrorSubscription = true;
      store.requestSubscription();
    });

    it('sets isLoadingSubscription to true', () => {
      expect(store.isLoadingSubscription).toBe(true);
    });

    it('sets hasErrorSubscription to false', () => {
      expect(store.hasErrorSubscription).toBe(false);
    });
  });

  describe('receiveSubscriptionSuccess', () => {
    const getColumnValues = (columns) =>
      columns.reduce(
        (acc, { id, value }) => ({
          ...acc,
          [id]: value,
        }),
        {},
      );
    const getStateTableValues = (key) =>
      store.tables[key].rows.map(({ columns }) => getColumnValues(columns));

    describe.each`
      desc                            | subscription                  | tableKey
      ${'with Ultimate subscription'} | ${mockDataSubscription.gold}  | ${TABLE_TYPE_DEFAULT}
      ${'with Free plan'}             | ${mockDataSubscription.free}  | ${TABLE_TYPE_FREE}
      ${'with Ultimate trial'}        | ${mockDataSubscription.trial} | ${TABLE_TYPE_TRIAL}
    `('$desc', ({ subscription, tableKey }) => {
      beforeEach(() => {
        store.isLoadingSubscription = true;
        store.receiveSubscriptionSuccess(subscription);
      });

      it('sets isLoadingSubscription to false', () => {
        expect(store.isLoadingSubscription).toBe(false);
      });

      it('sets plan', () => {
        const { plan } = convertObjectPropsToCamelCase(subscription, { deep: true });

        expect(store.plan).toEqual(plan);
      });

      it('sets billing information', () => {
        const { billing } = convertObjectPropsToCamelCase(subscription, { deep: true });

        expect(store.billing).toEqual(billing);
      });

      it(`updates table ${tableKey} with subscription plan`, () => {
        expect(getStateTableValues(tableKey)).toMatchSnapshot();
      });
    });
  });

  describe('receiveSubscriptionError', () => {
    beforeEach(() => {
      store.isLoadingSubscription = true;
      store.receiveSubscriptionError();
    });

    it('alerts the error', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'An error occurred while loading the subscription details.',
      });
    });

    it('sets isLoadingSubscription to false', () => {
      expect(store.isLoadingSubscription).toBe(false);
    });

    it('sets hasErrorSubscription to true', () => {
      expect(store.hasErrorSubscription).toBe(true);
    });
  });
});
