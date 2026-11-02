import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import initOrbit from 'ee/orbit';
import OrbitDashboardApp from 'ee/orbit/dashboard/dashboard_app.vue';
import createDashboardRouter from 'ee/orbit/dashboard/router';
import { initLazyHandRaiseLeadModal } from 'ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal';

jest.mock('~/lib/utils/vue3compat/init_vue_app');
jest.mock('ee/orbit/dashboard/router', () => jest.fn(() => 'dashboard-router'));
jest.mock('ee/hand_raise_leads/hand_raise_lead/init_lazy_hand_raise_lead_modal');

describe('initOrbit', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('without the mount element', () => {
    it('mounts nothing', () => {
      expect(initOrbit()).toBe(null);
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });

  describe('with the mount element', () => {
    let el;

    beforeEach(() => {
      window.gon = { current_user_id: 7 };
      el = document.createElement('div');
      el.id = 'js-orbit-app';
      Object.assign(el.dataset, {
        routerBase: '/dashboard/orbit',
        canAskDuoForQueries: 'false',
        duoAccessible: 'true',
        orbitSettingsEnabled: 'false',
        adminConfigurationPath: '/admin/orbit',
        orbitPlatform: JSON.stringify({ saas: false, instance: { state: 'TRIAL_ELIGIBLE' } }),
        queriesAvailable: 'false',
        trialAvailable: 'true',
        defaultGroupMissing: 'true',
        preferencesPath: '/p',
      });
      document.body.appendChild(el);
      initOrbit();
    });

    it('prepares the hand-raise form for Contact sales', () => {
      expect(initLazyHandRaiseLeadModal).toHaveBeenCalledWith(el);
    });

    it('builds the router on the dashboard path', () => {
      expect(createDashboardRouter).toHaveBeenCalledWith('/dashboard/orbit');
    });

    it('mounts the dashboard app with its injected data and props', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          component: OrbitDashboardApp,
          router: 'dashboard-router',
          provide: expect.objectContaining({
            currentUserId: 7,
            canAskDuoForQueries: false,
            orbitPlatform: { saas: false, instance: { state: 'TRIAL_ELIGIBLE' } },
            queriesAvailable: false,
            adminConfigurationPath: '/admin/orbit',
            trialAvailable: true,
            defaultGroupMissing: true,
            preferencesPath: '/p',
          }),
          props: {
            adminConfigurationPath: '/admin/orbit',
            duoAccessible: true,
            orbitSettingsEnabled: false,
          },
        }),
      );
    });
  });

  describe('with the mount element of a viewer who is not an administrator', () => {
    beforeEach(() => {
      window.gon = { current_user_id: 7 };
      const el = document.createElement('div');
      el.id = 'js-orbit-app';
      Object.assign(el.dataset, {
        routerBase: '/dashboard/orbit',
        orbitPlatform: JSON.stringify({ saas: false, instance: { state: 'UNLICENSED' } }),
        queriesAvailable: 'false',
      });
      document.body.appendChild(el);
      initOrbit();
    });

    it('provides the parsed platform and no admin path', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          provide: expect.objectContaining({
            orbitPlatform: { saas: false, instance: { state: 'UNLICENSED' } },
            adminConfigurationPath: null,
          }),
        }),
      );
    });
  });
});
