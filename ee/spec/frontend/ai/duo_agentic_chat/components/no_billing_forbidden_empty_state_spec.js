import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import NoBillingForbiddenEmptyState from 'ee/ai/duo_agentic_chat/components/no_billing_forbidden_empty_state.vue';

describe('NoBillingForbiddenEmptyState', () => {
  let wrapper;

  const createWrapper = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(NoBillingForbiddenEmptyState, {
      propsData: props,
      stubs: { GlSprintf },
    });
  };

  const findReturnToNonAgenticButton = () =>
    wrapper.findComponentByTestId('return-to-non-agentic-button');

  describe('default', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders the component', () => {
      expect(wrapper.findByTestId('no-billing-forbidden-empty-state').exists()).toBe(true);
    });

    it('shows a headline about usage billing', () => {
      expect(wrapper.text()).toContain('Usage billing not available');
    });

    it('instructs the user to contact their administrator', () => {
      expect(wrapper.text()).toContain('contact your administrator');
    });

    it('does not render a purchase CTA or the return-to-non-agentic button', () => {
      expect(wrapper.find('gl-button-stub').exists()).toBe(false);
    });
  });

  describe('when isClassicAvailable is true', () => {
    beforeEach(() => {
      createWrapper({ props: { isClassicAvailable: true } });
    });

    it('renders the return-to-non-agentic button', () => {
      expect(findReturnToNonAgenticButton().exists()).toBe(true);
      expect(wrapper.text()).toContain('Use non-agentic Chat');
    });

    it('emits return-to-classic when the button is clicked', () => {
      findReturnToNonAgenticButton().vm.$emit('click');

      expect(wrapper.emitted('return-to-classic')).toHaveLength(1);
    });
  });

  describe('when isClassicAvailable is false', () => {
    beforeEach(() => {
      createWrapper({ props: { isClassicAvailable: false } });
    });

    it('does not render the return-to-non-agentic button', () => {
      expect(findReturnToNonAgenticButton().exists()).toBe(false);
    });
  });
});
