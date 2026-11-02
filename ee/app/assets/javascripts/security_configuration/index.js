import Vue from 'vue';
import VueRouter from 'vue-router';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import createDefaultClient from '~/lib/graphql';
import { injectVueAppBreadcrumbs } from '~/lib/utils/breadcrumbs';
import SecurityConfigurationBreadcrumb from './components/security_configuration_breadcrumb.vue';
import { routes } from './routes';

Vue.use(VueApollo);
Vue.use(VueRouter);

const parseScanCoverageBanner = (value) => {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
};

export const initSecurityConfiguration = (el) => {
  if (!el) {
    return null;
  }

  const {
    groupFullPath,
    groupId,
    groupName,
    rootGroupName,
    namespaceId,
    securityInventoryPath,
    canReadAttributes,
    canManageAttributes,
    canReadScanProfiles,
    canApplyProfiles,
    scanCoverageBanner,
  } = el.dataset;

  const router = new VueRouter({ routes });

  injectVueAppBreadcrumbs(router, SecurityConfigurationBreadcrumb);

  return new Vue({
    el,
    name: 'SecurityConfigurationRoot',
    router,
    apolloProvider: new VueApollo({
      defaultClient: createDefaultClient(),
    }),
    provide: {
      groupFullPath,
      groupId,
      groupName,
      rootGroupName,
      namespaceId,
      securityInventoryPath,
      canReadAttributes: parseBoolean(canReadAttributes),
      canManageAttributes: parseBoolean(canManageAttributes),
      canReadScanProfiles: parseBoolean(canReadScanProfiles),
      canApplyProfiles: parseBoolean(canApplyProfiles),
      scanCoverageBanner: parseScanCoverageBanner(scanCoverageBanner),
    },
    render(createElement) {
      return createElement('router-view');
    },
  });
};
