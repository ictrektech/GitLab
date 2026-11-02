import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { shallowMount } from '@vue/test-utils';
import SubscriptionApp from 'ee/billings/subscriptions/components/app.vue';
import { useBillingsSubscription } from 'ee/billings/subscriptions/store';

Vue.use(PiniaVuePlugin);

describe('SubscriptionApp component', () => {
  let pinia;

  const providedFields = {
    namespaceId: '42',
    namespaceName: 'bronze',
    planRenewHref: '/url/for/renew',
    customerPortalUrl: 'https://customers.gitlab.com/subscriptions',
  };

  const factory = () => {
    shallowMount(SubscriptionApp, {
      pinia,
      provide: {
        ...providedFields,
      },
    });
  };

  beforeEach(() => {
    pinia = createTestingPinia();
    useBillingsSubscription();
  });

  describe('on creation', () => {
    beforeEach(() => {
      factory();
    });

    it('sets the namespace id on created', () => {
      expect(useBillingsSubscription().setNamespaceId).toHaveBeenCalledTimes(1);
      expect(useBillingsSubscription().setNamespaceId).toHaveBeenCalledWith('42');
    });
  });
});
