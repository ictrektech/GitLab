import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import HandRaiseLeadButton from 'ee/hand_raise_leads/hand_raise_lead/components/hand_raise_lead_button.vue';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import { orbitPlatform } from '../../mock_data';

describe('OrbitContactSalesButton', () => {
  let wrapper;

  const createComponent = ({ saas = false, ...props } = {}) => {
    wrapper = shallowMountExtended(ContactSalesButton, {
      propsData: { glmContent: 'orbit-free-plan', ...props },
      provide: { orbitPlatform: orbitPlatform({ saas }) },
    });
  };

  const findHandRaise = () => wrapper.findComponent(HandRaiseLeadButton);
  const findLink = () => wrapper.findComponent(GlButton);

  describe('on GitLab.com', () => {
    beforeEach(() => {
      createComponent({ saas: true });
    });

    it('opens the hand-raise lead modal', () => {
      expect(findHandRaise().props('glmContent')).toBe('orbit-free-plan');
      expect(findHandRaise().props('ctaTracking')).toMatchObject({ label: 'orbit_contact_sales' });
      expect(findHandRaise().props('buttonAttributes')).toEqual({
        category: 'secondary',
        size: 'medium',
      });
      expect(findLink().exists()).toBe(false);
    });

    it('sends the lead to the personal namespace by default', () => {
      expect(findHandRaise().props('namespaceId')).toBeNull();
    });
  });

  describe('on GitLab.com with a group', () => {
    beforeEach(() => {
      createComponent({ saas: true, namespaceId: 24 });
    });

    it('sends the lead to the group', () => {
      expect(findHandRaise().props('namespaceId')).toBe(24);
    });
  });

  describe('off GitLab.com', () => {
    beforeEach(() => {
      createComponent({ saas: false });
    });

    it('links to the sales page', () => {
      expect(findLink().attributes('href')).toBe('https://about.gitlab.com/sales/');
      expect(findLink().attributes('target')).toBe('_blank');
      expect(findLink().props('category')).toBe('secondary');
      expect(findHandRaise().exists()).toBe(false);
    });
  });

  describe('with a small size', () => {
    it('makes the hand-raise button small on GitLab.com', () => {
      createComponent({ saas: true, size: 'small' });

      expect(findHandRaise().props('buttonAttributes')).toMatchObject({ size: 'small' });
    });

    it('makes the sales link small off GitLab.com', () => {
      createComponent({ saas: false, size: 'small' });

      expect(findLink().props('size')).toBe('small');
    });
  });
});
