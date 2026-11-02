import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';

import SubscriptionApp from './components/app.vue';
import apolloProvider from './provider';

export default (containerId = 'js-billing-plans') => {
  const containerEl = document.getElementById(containerId);

  if (!containerEl) {
    return false;
  }

  const {
    namespaceId,
    namespaceName,
    addSeatsHref,
    planRenewHref,
    customerPortalUrl,
    billableSeatsHref,
    planName,
    refreshSeatsHref,
    readOnly,
    seatsLastUpdated,
  } = containerEl.dataset;

  return initVueApp({
    el: containerEl,
    name: 'SubscriptionAppRoot',
    pinia,
    apolloProvider,
    provide: {
      namespaceId: Number(namespaceId),
      namespaceName,
      addSeatsHref,
      planRenewHref,
      customerPortalUrl,
      billableSeatsHref,
      planName,
      refreshSeatsHref,
      readOnly: parseBoolean(readOnly),
      seatsLastUpdated,
    },
    component: SubscriptionApp,
  });
};
