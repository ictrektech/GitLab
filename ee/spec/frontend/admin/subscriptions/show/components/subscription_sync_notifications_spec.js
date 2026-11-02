import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import Vue from 'vue';
import SubscriptionSyncNotifications, {
  i18n,
} from 'ee/admin/subscriptions/show/components/subscription_sync_notifications.vue';
import { subscriptionSyncStatus } from 'ee/admin/subscriptions/show/constants';
import { useAdminSubscription } from 'ee/admin/subscriptions/show/store';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';

Vue.use(PiniaVuePlugin);

describe('Subscription Sync Notifications', () => {
  let pinia;
  let store;
  let wrapper;

  const connectivityHelpURL = 'connectivity/help/url';

  const findAllAlerts = () => wrapper.findAllComponents(GlAlert);
  const findFailureAlert = () => wrapper.findComponentByTestId('sync-failure-alert');
  const findSuccessAlert = () => wrapper.findComponentByTestId('sync-success-alert');
  const findLink = () => wrapper.findComponent(GlLink);

  const createComponent = ({ stubs } = {}) => {
    wrapper = extendedWrapper(
      shallowMount(SubscriptionSyncNotifications, {
        pinia,
        provide: { connectivityHelpURL },
        stubs,
      }),
    );
  };

  beforeEach(() => {
    pinia = createTestingPinia();
    store = useAdminSubscription();
  });

  describe('idle state', () => {
    it('displays no alert', () => {
      createComponent();

      expect(findAllAlerts()).toHaveLength(0);
    });
  });

  describe('sync info notification', () => {
    beforeEach(() => {
      store.subscriptionSyncStatus = subscriptionSyncStatus.SYNC_SUCCESS;

      createComponent();
    });

    it('displays an info alert', () => {
      expect(findSuccessAlert().props('variant')).toBe('info');
    });

    it('displays an alert with a title', () => {
      expect(findSuccessAlert().props('title')).toBe(i18n.MANUAL_SYNC_SUCCESS_TITLE);
    });

    it('displays an alert with a message', () => {
      expect(findSuccessAlert().text()).toBe(i18n.MANUAL_SYNC_SUCCESS_TEXT);
    });

    it('triggers dismissAlert action when dismiss event is emitted', () => {
      findSuccessAlert().vm.$emit('dismiss');

      expect(store.dismissAlert).toHaveBeenCalled();
    });
  });

  describe('sync failure notification', () => {
    beforeEach(() => {
      store.subscriptionSyncStatus = subscriptionSyncStatus.SYNC_FAILURE;

      createComponent({ stubs: { GlSprintf } });
    });

    it('displays an alert with a failure title', () => {
      expect(findFailureAlert().props('title')).toBe(i18n.CONNECTIVITY_ERROR_TITLE);
    });

    it('displays an alert with a failure message', () => {
      expect(findFailureAlert().text()).toBe(
        'Subscription details did not synchronize due to a possible connectivity issue with GitLab servers. How do I check connectivity?',
      );
    });

    it('does not trigger dismissAlert action when dismiss event is emitted', () => {
      findFailureAlert().vm.$emit('dismiss');

      expect(store.dismissAlert).not.toHaveBeenCalled();
    });

    it('displays a link', () => {
      expect(findLink().attributes('href')).toBe(connectivityHelpURL);
    });
  });
});
