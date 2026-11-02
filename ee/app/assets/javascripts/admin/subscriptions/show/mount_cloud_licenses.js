import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { helpPagePath } from '~/helpers/help_page_helper';
import createDefaultClient from '~/lib/graphql';
import { pinia } from '~/pinia/instance';
import CloudLicenseShowApp from './components/app.vue';
import { useAdminSubscription } from './store';

Vue.use(VueApollo);

const apolloProvider = new VueApollo({
  defaultClient: createDefaultClient(),
});

export default () => {
  const el = document.getElementById('js-show-subscription-page');

  if (!el) {
    return null;
  }

  const {
    customersPortalUrl,
    freeTrialPath,
    hasActiveLicense,
    licenseRemovePath,
    subscriptionSyncPath,
    licenseUsageFilePath,
    isAdmin,
    settingsAddLicensePath,
    groupsCount,
    projectsCount,
    usersCount,
    purchaseCreditsPath,
    billableUsageReportPath,
  } = el.dataset;
  const connectivityHelpURL = helpPagePath('/administration/license.html', {
    anchor: 'error-cannot-activate-instance-due-to-a-connectivity-issue',
  });

  useAdminSubscription(pinia).setInitialData({
    licenseRemovalPath: licenseRemovePath,
    subscriptionSyncPath,
  });

  return initVueApp({
    el,
    pinia,
    name: 'CloudLicenseRoot',
    apolloProvider,
    provide: {
      connectivityHelpURL,
      customersPortalUrl,
      freeTrialPath,
      licenseRemovePath,
      settingsAddLicensePath,
      groupsCount: Number(groupsCount),
      projectsCount: Number(projectsCount),
      usersCount: Number(usersCount),
      purchaseCreditsPath,
    },
    component: CloudLicenseShowApp,
    props: {
      hasActiveLicense: parseBoolean(hasActiveLicense),
      licenseUsageFilePath,
      billableUsageReportPath,
      isAdmin: parseBoolean(isAdmin),
    },
  });
};
