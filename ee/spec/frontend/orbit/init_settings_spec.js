import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { initLazyHandRaiseLeadModal } from 'ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal';
import initOrbitSettings from 'ee/orbit/init_settings';
import GroupSettingsPage from 'ee/orbit/settings/group_settings_page.vue';
import AdminSettingsPage from 'ee/orbit/settings/admin/admin_settings_page.vue';

jest.mock('~/lib/utils/vue3compat/init_vue_app');
jest.mock('ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal');

describe('initOrbitSettings', () => {
  const mount = (dataset) => {
    const el = document.createElement('div');
    el.id = 'js-orbit-settings';
    Object.assign(el.dataset, dataset);
    document.body.appendChild(el);
    return initOrbitSettings();
  };

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('without the mount element', () => {
    it('mounts nothing', () => {
      expect(initOrbitSettings()).toBe(null);
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });

  describe('the admin branch', () => {
    beforeEach(() => {
      mount({
        settingsPath: '/admin/orbit.json',
        overviewPath: '/overview',
        schemaPath: '/schema',
        newGroupPath: '/groups/new',
        orbitPlatform: JSON.stringify({ saas: false, instance: { state: 'TRIAL_ELIGIBLE' } }),
        autoIndexEnabled: 'false',
        duoDefaultEnabled: 'true',
      });
    });

    it('mounts the admin page and provides the parsed platform', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          component: AdminSettingsPage,
          provide: { orbitPlatform: { saas: false, instance: { state: 'TRIAL_ELIGIBLE' } } },
        }),
      );
    });
  });

  describe('the group branch', () => {
    beforeEach(() => {
      mount({
        groupFullPath: 'acme',
        orbitPlatform: JSON.stringify({ saas: true, instance: null }),
        duoAvailable: 'true',
        orbitPath: '/dashboard/orbit',
        usageQuotasPath: '/acme/-/usage_quotas',
        duoSettingsPath: '/acme/-/settings/gitlab_duo',
      });
    });

    it('prepares the hand-raise form for Contact sales', () => {
      expect(initLazyHandRaiseLeadModal).toHaveBeenCalled();
    });

    it('mounts the group settings page and provides the parsed platform', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          component: GroupSettingsPage,
          provide: { orbitPlatform: { saas: true, instance: null } },
        }),
      );
    });
  });
});
