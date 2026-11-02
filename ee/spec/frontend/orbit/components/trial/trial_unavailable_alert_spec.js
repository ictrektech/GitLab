import { GlAlert, GlButton, GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import TrialUnavailableAlert from 'ee/orbit/components/trial/trial_unavailable_alert.vue';
import { orbitPlatform } from '../../mock_data';

describe('OrbitTrialUnavailableAlert', () => {
  let wrapper;

  const createComponent = ({ saas = true, ...props } = {}) => {
    wrapper = shallowMountExtended(TrialUnavailableAlert, {
      propsData: {
        glmContent: 'orbit-off-page',
        namespaceId: 24,
        reloading: false,
        ...props,
      },
      provide: { orbitPlatform: orbitPlatform({ saas }) },
      stubs: { GlAlert },
    });
  };

  const findRetry = () => wrapper.findComponent(GlButton);
  const findContactSales = () => wrapper.findComponent(ContactSalesButton);
  const findReloading = () => wrapper.findComponent(GlLoadingIcon);

  it('asks to try again or contact sales', () => {
    createComponent();

    expect(wrapper.findComponent(GlAlert).props()).toMatchObject({
      variant: 'danger',
      title: 'Something went wrong',
    });
    expect(wrapper.text()).toContain(
      'Could not load GitLab Orbit trial details for your groups. Try again, or contact sales if this keeps happening.',
    );
  });

  describe('when the user selects Try again', () => {
    beforeEach(() => {
      createComponent();
      findRetry().vm.$emit('click');
    });

    it('emits retry', () => {
      expect(wrapper.emitted('retry')).toHaveLength(1);
    });
  });

  it('passes the sales context to Contact sales', () => {
    createComponent({ saas: false, glmContent: 'orbit-group-status' });

    expect(findContactSales().props()).toMatchObject({
      glmContent: 'orbit-group-status',
      namespaceId: 24,
    });
  });

  it.each`
    reloading | shown
    ${true}   | ${true}
    ${false}  | ${false}
  `('shows the reload icon: $shown when reloading is $reloading', ({ reloading, shown }) => {
    createComponent({ reloading });

    expect(findReloading().exists()).toBe(shown);
  });
});
