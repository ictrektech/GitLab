import { GlAlert, GlModal, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';

describe('EnableAddOnModal', () => {
  let wrapper;

  const subscriptionsUrl = 'https://customers.example.com';

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(EnableAddOnModal, {
      propsData: {
        visible: true,
        ...props,
      },
      provide: { subscriptionsUrl },
      stubs: { GlModal, GlSprintf },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findLinks = () => wrapper.findAllComponents(GlLink);

  describe('when on-demand billing is enabled', () => {
    beforeEach(() => {
      createComponent({ onDemandEnabled: true });
    });

    it('shows the billing-explainer title and a confirm action', () => {
      expect(findModal().props('title')).toBe('Enable GitLab Secrets Manager with GitLab Credits');
      expect(findModal().props('actionPrimary')).toEqual({
        text: 'Enable GitLab Secrets Manager',
        attributes: { variant: 'confirm' },
      });
      expect(findModal().props('actionCancel')).toEqual({ text: 'Cancel' });
    });

    it('emits `enable` when the primary action fires', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('enable')).toHaveLength(1);
    });
  });

  describe('when on-demand billing is not enabled', () => {
    beforeEach(() => {
      createComponent({ onDemandEnabled: false });
    });

    it('shows the no-credits title and no action buttons', () => {
      expect(findModal().props('title')).toBe(
        'Your group subscription does not have GitLab Credits available',
      );
      expect(findModal().props('actionPrimary')).toBe(null);
      expect(findModal().props('actionCancel')).toBe(null);
    });

    it('links to the customer portal', () => {
      const portalLink = findLinks().wrappers.find(
        (link) => link.attributes('href') === subscriptionsUrl,
      );

      expect(portalLink).not.toBeUndefined();
    });
  });

  describe('entitlement check alert', () => {
    it('is hidden by default', () => {
      createComponent();

      expect(wrapper.findComponent(GlAlert).exists()).toBe(false);
    });

    it.each([true, false])(
      'shows a danger alert when the entitlement check failed (onDemandEnabled: %s)',
      (onDemandEnabled) => {
        createComponent({ entitlementCheckFailed: true, onDemandEnabled });

        const alert = wrapper.findComponent(GlAlert);
        expect(alert.props('variant')).toBe('danger');
        expect(alert.props('dismissible')).toBe(false);
        expect(alert.text()).toBe(
          "Couldn't verify the current billing status. Please try again later.",
        );
      },
    );
  });

  it('emits `hide` when the modal is hidden', () => {
    createComponent({ onDemandEnabled: true });
    findModal().vm.$emit('hidden');

    expect(wrapper.emitted('hide')).toHaveLength(1);
  });

  it('always links to the GitLab Secrets Manager billing docs', () => {
    createComponent({ onDemandEnabled: true });
    const docsLink = findLinks().wrappers.find(
      (link) => link.attributes('href') === '/help/ci/secrets/secrets_manager/credit_usage',
    );

    expect(docsLink).not.toBeUndefined();
  });
});
