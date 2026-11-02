import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { useStatusPageSettings } from 'ee/status_page_settings/store';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import { refreshCurrentPage } from '~/lib/utils/url_utility';

jest.mock('~/alert');
jest.mock('~/lib/utils/url_utility');

describe('Status Page settings store', () => {
  let store;
  let mock;

  const initialState = {
    enabled: 'true',
    url: 'http://status.io',
    bucketName: 'test-bucket',
    region: 'us-west',
    awsAccessKey: 'key-id',
    awsSecretKey: 'secret',
    operationsSettingsEndpoint: '/settings',
  };

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useStatusPageSettings();
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
  });

  describe('setInitialState', () => {
    it('has empty defaults', () => {
      expect(store.$state).toEqual({
        enabled: false,
        url: '',
        bucketName: '',
        region: '',
        awsAccessKey: '',
        awsSecretKey: '',
        operationsSettingsEndpoint: '',
        loading: false,
      });
    });

    it('seeds the state from the dataset', () => {
      store.setInitialState(initialState);

      expect(store.$state).toEqual({
        enabled: true,
        url: 'http://status.io',
        bucketName: 'test-bucket',
        region: 'us-west',
        awsAccessKey: 'key-id',
        awsSecretKey: 'secret',
        operationsSettingsEndpoint: '/settings',
        loading: false,
      });
    });

    it('treats a non-true enabled value as disabled', () => {
      store.setInitialState({ enabled: 'false' });

      expect(store.enabled).toBe(false);
    });
  });

  describe('updateStatusPageSettings', () => {
    beforeEach(() => {
      store.setInitialState(initialState);
    });

    it('sends the settings and handles a successful update', async () => {
      mock.onPatch('/settings').reply(HTTP_STATUS_OK, {});
      jest.spyOn(store, 'receiveStatusPageSettingsUpdateSuccess');

      const promise = store.updateStatusPageSettings();

      expect(store.loading).toBe(true);

      await promise;

      expect(JSON.parse(mock.history.patch[0].data)).toEqual({
        project: {
          status_page_setting_attributes: {
            enabled: true,
            status_page_url: 'http://status.io',
            aws_s3_bucket_name: 'test-bucket',
            aws_region: 'us-west',
            aws_access_key: 'key-id',
            aws_secret_key: 'secret',
          },
        },
      });
      expect(store.receiveStatusPageSettingsUpdateSuccess).toHaveBeenCalledTimes(1);
      expect(store.loading).toBe(false);
    });

    it('handles an unsuccessful update', async () => {
      mock.onPatch('/settings').reply(HTTP_STATUS_BAD_REQUEST, {});
      jest.spyOn(store, 'receiveStatusPageSettingsUpdateError');

      const promise = store.updateStatusPageSettings();

      expect(store.loading).toBe(true);

      await promise;

      expect(store.receiveStatusPageSettingsUpdateError).toHaveBeenCalledWith(expect.any(Object));
      expect(store.loading).toBe(false);
    });
  });

  describe('receiveStatusPageSettingsUpdateSuccess', () => {
    it('refreshes the page', () => {
      store.receiveStatusPageSettingsUpdateSuccess();

      expect(refreshCurrentPage).toHaveBeenCalledTimes(1);
    });
  });

  describe('receiveStatusPageSettingsUpdateError', () => {
    it('creates an alert with the error message', () => {
      const error = { response: { data: { message: 'Update error' } } };

      store.receiveStatusPageSettingsUpdateError(error);

      expect(createAlert).toHaveBeenCalledWith({
        message: `There was an error saving your changes. ${error.response.data.message}`,
      });
    });
  });
});
