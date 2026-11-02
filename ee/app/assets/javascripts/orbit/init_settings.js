import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import { initLazyHandRaiseLeadModal } from 'ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal';
import { parseOrbitPlatform } from './access/platform';
import GroupSettingsPage from './settings/group_settings_page.vue';
import AdminSettingsPage from './settings/admin/admin_settings_page.vue';
import { ADMIN_CACHE_CONFIG } from './settings/admin/graphql/cache_config';
import { GROUP_SETTINGS_CACHE_CONFIG } from './settings/graphql/cache_config';

Vue.use(VueApollo);

export default function initOrbitSettings() {
  const el = document.getElementById('js-orbit-settings');

  if (!el) return null;

  const { groupFullPath } = el.dataset;

  if (!groupFullPath) {
    const {
      settingsPath,
      overviewPath,
      schemaPath,
      newGroupPath,
      orbitPlatform,
      autoIndexEnabled,
      duoDefaultEnabled,
    } = el.dataset;

    return initVueApp({
      el,
      name: 'OrbitAdminSettingsRoot',
      apolloProvider: new VueApollo({
        defaultClient: createDefaultClient({}, { cacheConfig: ADMIN_CACHE_CONFIG }),
      }),
      component: AdminSettingsPage,
      provide: {
        orbitPlatform: parseOrbitPlatform(orbitPlatform),
      },
      props: {
        settingsPath,
        overviewPath,
        schemaPath,
        newGroupPath,
        autoIndexEnabled: parseBoolean(autoIndexEnabled),
        duoDefaultEnabled: parseBoolean(duoDefaultEnabled),
      },
    });
  }

  initLazyHandRaiseLeadModal(el);

  const { orbitPlatform, duoAvailable, orbitPath, usageQuotasPath, duoSettingsPath } = el.dataset;

  return initVueApp({
    el,
    name: 'OrbitGroupSettingsRoot',
    apolloProvider: new VueApollo({
      defaultClient: createDefaultClient({}, { cacheConfig: GROUP_SETTINGS_CACHE_CONFIG }),
    }),
    component: GroupSettingsPage,
    provide: {
      orbitPlatform: parseOrbitPlatform(orbitPlatform),
    },
    props: {
      groupFullPath,
      duoAvailable: parseBoolean(duoAvailable),
      orbitPath,
      usageQuotasPath,
      duoSettingsPath,
    },
  });
}
