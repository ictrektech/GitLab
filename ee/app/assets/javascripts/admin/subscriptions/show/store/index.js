import { defineStore } from 'pinia';
import axios from '~/lib/utils/axios_utils';
import { refreshCurrentPage } from '~/lib/utils/url_utility';
import { subscriptionSyncStatus } from '../constants';

export const useAdminSubscription = defineStore('adminSubscription', {
  state() {
    return {
      licenseRemovalPath: '',
      subscriptionSyncPath: '',
      subscriptionSyncStatus: null,
      breakdown: {
        shouldShowNotifications: false,
        hasAsyncActivity: false,
        licenseError: null,
      },
    };
  },
  getters: {
    didSyncFail() {
      return this.subscriptionSyncStatus === subscriptionSyncStatus.SYNC_FAILURE;
    },
    didSyncSucceed() {
      return this.subscriptionSyncStatus === subscriptionSyncStatus.SYNC_SUCCESS;
    },
  },
  actions: {
    setInitialData({ licenseRemovalPath, subscriptionSyncPath }) {
      this.licenseRemovalPath = licenseRemovalPath;
      this.subscriptionSyncPath = subscriptionSyncPath;
    },
    async syncSubscription() {
      this.subscriptionSyncStatus = subscriptionSyncStatus.SYNC_PENDING;
      this.breakdown.hasAsyncActivity = true;

      try {
        await axios.post(this.subscriptionSyncPath);
        this.subscriptionSyncStatus = subscriptionSyncStatus.SYNC_SUCCESS;
      } catch (e) {
        this.subscriptionSyncStatus = subscriptionSyncStatus.SYNC_FAILURE;
      }

      this.breakdown.hasAsyncActivity = false;
      this.breakdown.shouldShowNotifications = true;
    },
    async removeLicense() {
      this.breakdown.hasAsyncActivity = true;

      try {
        await axios.delete(this.licenseRemovalPath);
        this.removeLicenseSuccess();
      } catch (e) {
        this.breakdown.hasAsyncActivity = false;
        this.breakdown.licenseError = e;
      }
    },
    removeLicenseSuccess() {
      this.breakdown.hasAsyncActivity = false;

      refreshCurrentPage();
    },
    dismissAlert() {
      this.breakdown.shouldShowNotifications = false;
      this.breakdown.licenseError = null;
    },
  },
});
