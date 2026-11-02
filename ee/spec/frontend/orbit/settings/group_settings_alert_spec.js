import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { assertProps } from 'helpers/assert_props';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import GroupSettingsAlert from 'ee/orbit/settings/group_settings_alert.vue';
import { orbitPlatform } from '../mock_data';

describe('OrbitGroupSettingsAlert', () => {
  let wrapper;

  const createComponent = ({ saas = true, ...props } = {}) => {
    wrapper = shallowMountExtended(GroupSettingsAlert, {
      propsData: {
        state: 'free_plan',
        groupName: 'Acme',
        usageQuotasPath: '/acme/-/usage_quotas',
        ...props,
      },
      provide: { orbitPlatform: orbitPlatform({ saas }) },
      stubs: { GlSprintf },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findContactSales = () => wrapper.findComponent(ContactSalesButton);
  const findLink = () => wrapper.findComponent(GlLink);

  describe('when the state is free_plan', () => {
    beforeEach(() => {
      createComponent({ state: 'free_plan' });
    });

    it('names the group and offers Contact sales', () => {
      expect(findAlert().props('title')).toBe('GitLab Orbit is available on Premium and Ultimate');
      expect(findAlert().props('variant')).toBe('info');
      expect(wrapper.text()).toContain('Acme is on the Free plan.');
      expect(findContactSales().props('glmContent')).toBe('orbit-free-plan');
    });
  });

  describe('when the state is unlicensed', () => {
    beforeEach(() => {
      createComponent({ state: 'unlicensed' });
    });

    it('offers Contact sales', () => {
      expect(findAlert().props('title')).toBe('Get GitLab Orbit for this group');
      expect(findContactSales().props('glmContent')).toBe('orbit-unlicensed');
    });
  });

  describe('when the state is cdot_unavailable', () => {
    beforeEach(() => {
      createComponent({ state: 'cdot_unavailable' });
    });

    it('warns and offers Contact sales', () => {
      expect(findAlert().props('variant')).toBe('warning');
      expect(wrapper.text()).toContain('Could not check whether Acme');
      expect(findContactSales().props('glmContent')).toBe('orbit-unavailable');
    });
  });

  describe('when the state is cdot_unavailable on GitLab Self-Managed', () => {
    beforeEach(() => {
      createComponent({ state: 'cdot_unavailable', saas: false });
    });

    it('speaks of the instance trial', () => {
      expect(wrapper.text()).toContain(
        'Could not check the trial of this instance. Try again later, or contact sales if this keeps happening.',
      );
      expect(wrapper.text()).not.toContain('Acme');
    });
  });

  describe('when the state is not_eligible', () => {
    beforeEach(() => {
      createComponent({ state: 'not_eligible' });
    });

    it('names the group and offers Contact sales, with no docs link', () => {
      expect(findAlert().props('title')).toBe('Get GitLab Orbit for Acme');
      expect(findContactSales().props('glmContent')).toBe('orbit-not-eligible');
      expect(findLink().exists()).toBe(false);
    });
  });

  describe('when the state is trial_ended', () => {
    beforeEach(() => {
      createComponent({ state: 'trial_ended' });
    });

    it('warns and offers Contact sales, with no docs link', () => {
      expect(findAlert().props('variant')).toBe('warning');
      expect(findAlert().props('title')).toBe('Your GitLab Orbit trial has ended');
      expect(wrapper.text()).toContain('GitLab Orbit is paused for Acme.');
      expect(findContactSales().props('glmContent')).toBe('orbit-trial-ended');
      expect(findLink().exists()).toBe(false);
    });
  });

  describe('when the state is credits_used_up', () => {
    beforeEach(() => {
      createComponent({ state: 'credits_used_up' });
    });

    it('names the group, links to usage quotas, and offers Contact sales', () => {
      expect(findAlert().props('title')).toBe('Acme has no GitLab Credits left');
      expect(wrapper.findByText('View usage quotas').attributes('href')).toBe(
        '/acme/-/usage_quotas',
      );
      expect(findContactSales().props('glmContent')).toBe('orbit-credits-used-up');
    });
  });

  describe.each`
    state                       | variant      | title                                     | text
    ${'instance_not_available'} | ${'info'}    | ${'Get GitLab Orbit for this instance'}   | ${'Ask your administrator, or contact sales.'}
    ${'instance_trial_ended'}   | ${'warning'} | ${'The trial of this instance has ended'} | ${'GitLab Orbit queries are paused. GitLab Orbit still indexes this group when it is on. Ask your administrator, or contact sales.'}
  `('when the state is $state', ({ state, variant, title, text }) => {
    beforeEach(() => {
      createComponent({ state, saas: false });
    });

    it('speaks of the instance and offers Contact sales', () => {
      expect(findAlert().props()).toMatchObject({ variant, title });
      expect(findAlert().text()).toContain(text);
      expect(findContactSales().props()).toMatchObject({
        glmContent: 'orbit-instance',
      });
    });
  });

  describe('with an unknown state', () => {
    it('fails prop validation', () => {
      expect(() =>
        assertProps(GroupSettingsAlert, {
          state: 'nonsense',
          groupName: 'Acme',
          usageQuotasPath: '/acme/-/usage_quotas',
        }),
      ).toThrow();
    });
  });
});
