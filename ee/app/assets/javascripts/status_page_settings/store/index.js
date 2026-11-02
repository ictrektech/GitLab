import { defineStore } from 'pinia';
import { parseBoolean } from '@gitlab/frontend-utils';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { refreshCurrentPage } from '~/lib/utils/url_utility';
import { __ } from '~/locale';

export const useStatusPageSettings = defineStore('statusPageSettings', {
  state() {
    return {
      enabled: false,
      url: '',
      bucketName: '',
      region: '',
      awsAccessKey: '',
      awsSecretKey: '',
      operationsSettingsEndpoint: '',
      loading: false,
    };
  },
  actions: {
    setInitialState(initialState = {}) {
      this.enabled = parseBoolean(initialState.enabled) || false;
      this.url = initialState.url || '';
      this.bucketName = initialState.bucketName || '';
      this.region = initialState.region || '';
      this.awsAccessKey = initialState.awsAccessKey || '';
      this.awsSecretKey = initialState.awsSecretKey || '';
      this.operationsSettingsEndpoint = initialState.operationsSettingsEndpoint || '';
    },
    updateStatusPageSettings() {
      this.loading = true;

      return axios
        .patch(this.operationsSettingsEndpoint, {
          project: {
            status_page_setting_attributes: {
              enabled: this.enabled,
              status_page_url: this.url,
              aws_s3_bucket_name: this.bucketName,
              aws_region: this.region,
              aws_access_key: this.awsAccessKey,
              aws_secret_key: this.awsSecretKey,
            },
          },
        })
        .then(() => this.receiveStatusPageSettingsUpdateSuccess())
        .catch((error) => this.receiveStatusPageSettingsUpdateError(error))
        .finally(() => {
          this.loading = false;
        });
    },
    receiveStatusPageSettingsUpdateSuccess() {
      /**
       * The operations_controller currently handles successful requests
       * by creating an alert banner message to notify the user.
       */
      refreshCurrentPage();
    },
    receiveStatusPageSettingsUpdateError(error) {
      const { response } = error;
      const message = response?.data?.message || '';

      createAlert({
        message: `${__('There was an error saving your changes.')} ${message}`,
      });
    },
  },
});
