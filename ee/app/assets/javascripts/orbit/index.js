import Vue from 'vue';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import { initLazyHandRaiseLeadModal } from 'ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal';
import { parseOrbitPlatform } from './access/platform';
import OrbitDashboardApp from './dashboard/dashboard_app.vue';
import { DASHBOARD_CACHE_CONFIG } from './dashboard/graphql/cache_config';
import createDashboardRouter from './dashboard/router';

Vue.use(VueApollo);
Vue.use(VueRouter);

export default function initOrbit() {
  const el = document.getElementById('js-orbit-app');

  if (!el) return null;

  const {
    routerBase,
    adminConfigurationPath,
    duoAccessible,
    canAskDuoForQueries,
    orbitSettingsEnabled,
    orbitPlatform,
    queriesAvailable,
    trialAvailable,
    defaultGroupMissing,
    listAllGroups,
    preferencesPath,
  } = el.dataset;

  initLazyHandRaiseLeadModal(el);

  return initVueApp({
    el,
    name: 'OrbitRoot',
    apolloProvider: new VueApollo({
      defaultClient: createDefaultClient({}, { cacheConfig: DASHBOARD_CACHE_CONFIG }),
    }),
    router: createDashboardRouter(routerBase),
    component: OrbitDashboardApp,
    provide: {
      canAskDuoForQueries: parseBoolean(canAskDuoForQueries),
      currentUserId: gon.current_user_id,
      orbitPlatform: parseOrbitPlatform(orbitPlatform),
      queriesAvailable: parseBoolean(queriesAvailable),
      adminConfigurationPath: adminConfigurationPath ?? null,
      trialAvailable: parseBoolean(trialAvailable),
      defaultGroupMissing: parseBoolean(defaultGroupMissing),
      listAllGroups: parseBoolean(listAllGroups),
      preferencesPath,
    },
    props: {
      adminConfigurationPath,
      duoAccessible: parseBoolean(duoAccessible),
      orbitSettingsEnabled: parseBoolean(orbitSettingsEnabled),
    },
  });
}
