import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import { mergeRequestApprovalSettingsMappers } from '../mappers';
import createStore from '../stores';
import approvalSettingsModule from '../stores/modules/approval_settings';
import GroupSettingsApp from './app.vue';

Vue.use(VueApollo);

const mountGroupApprovalSettings = (el) => {
  if (!el) {
    return null;
  }

  const { defaultExpanded, fullPath, approvalSettingsPath } = el.dataset;
  const store = createStore({
    approvalSettings: approvalSettingsModule(mergeRequestApprovalSettingsMappers),
  });

  return initVueApp({
    el,
    name: 'GroupSettingsAppRoot',
    store,
    apolloProvider: new VueApollo({
      defaultClient: createDefaultClient(),
    }),
    provide: {
      fullPath,
      isGroup: true,
    },
    component: GroupSettingsApp,
    props: {
      defaultExpanded: parseBoolean(defaultExpanded),
      approvalSettingsPath,
    },
  });
};

export { mountGroupApprovalSettings };
