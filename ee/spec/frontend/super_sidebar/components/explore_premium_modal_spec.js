import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { PROMO_URL } from '~/constants';
import { REQUEST_STATE } from 'ee/painted_door_request/utils';
import ExplorePremiumModal from 'ee/super_sidebar/components/explore_premium_modal.vue';
import FreeVsPremiumComparisonTable from 'ee/vue_shared/subscription/components/free_vs_premium_comparison_table.vue';

describe('ExplorePremiumModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ExplorePremiumModal, {
      propsData: { visible: true, state: REQUEST_STATE.NOT_REQUESTED, ...props },
      stubs: { GlModal },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findComparisonTable = () => wrapper.findComponent(FreeVsPremiumComparisonTable);
  const findLearnMoreButton = () =>
    wrapper.findComponentByTestId('explore-premium-learn-more-button');
  const findRequestButton = () => wrapper.findComponentByTestId('explore-premium-request-button');
  const findSupportingText = () => wrapper.findByTestId('explore-premium-supporting-text');

  it('renders the heading', () => {
    createComponent();

    expect(wrapper.text()).toContain('Get more from GitLab');
  });

  it('gives the modal an accessible name via the title prop', () => {
    createComponent();

    expect(findModal().props('title')).toBe('Get more from GitLab');
  });

  it('is a size sm modal not linking table rows', () => {
    createComponent();

    expect(findModal().props('size')).toBe('sm');
    expect(findComparisonTable().props('showFeaturePopovers')).toBe(false);
  });

  describe.each`
    state                                 | expectedBody
    ${REQUEST_STATE.NOT_REQUESTED}        | ${'Premium adds more control over reviews, planning, and delivery. Request an upgrade to unlock it for your group.'}
    ${REQUEST_STATE.REQUESTED}            | ${'Premium adds more control over reviews, planning, and delivery. Request an upgrade to unlock it for your group.'}
    ${REQUEST_STATE.PREVIOUSLY_REQUESTED} | ${'Premium adds more control over reviews, planning, and delivery. Explore what it has to offer for your group.'}
  `('body copy for state $state', ({ state, expectedBody }) => {
    it('renders the expected body sentence', () => {
      createComponent({ state });

      expect(wrapper.text()).toContain(expectedBody);
    });
  });

  describe('state 1: not requested', () => {
    beforeEach(() => createComponent({ state: REQUEST_STATE.NOT_REQUESTED }));

    it('renders Learn more with the default variant', () => {
      expect(findLearnMoreButton().props('variant')).toBe('default');
    });

    it('renders "Request Premium features" with no icon or aria-disabled', () => {
      const button = findRequestButton();

      expect(button.text()).toBe('Request Premium features');
      expect(button.props('icon')).toBe('');
      expect(button.attributes('aria-disabled')).toBeUndefined();
    });

    it('renders an empty, but present, supporting text region', () => {
      expect(findSupportingText().exists()).toBe(true);
      expect(findSupportingText().text()).toBe('');
      expect(findSupportingText().attributes('aria-live')).toBe('polite');
    });

    it('emits request when the button is clicked', () => {
      findRequestButton().vm.$emit('click');

      expect(wrapper.emitted('request')).toHaveLength(1);
    });
  });

  describe('state 2: requested this session', () => {
    beforeEach(() => createComponent({ state: REQUEST_STATE.REQUESTED }));

    it('renders Learn more with the default variant', () => {
      expect(findLearnMoreButton().props('variant')).toBe('default');
    });

    it('renders "Interest recorded" with a check icon and raw aria-disabled', () => {
      const button = findRequestButton();

      expect(button.text()).toBe('Interest recorded');
      expect(button.props('icon')).toBe('check');
      expect(button.attributes('aria-disabled')).toBe('true');
    });

    it('fills the supporting text region', () => {
      expect(findSupportingText().text()).toBe(
        "Thank you for your interest. Your group Owner isn't notified, so ask them directly to upgrade.",
      );
    });

    it('does not emit request when the button is clicked again', () => {
      findRequestButton().vm.$emit('click');

      expect(wrapper.emitted('request')).toBeUndefined();
    });
  });

  describe('state 3: previously requested', () => {
    beforeEach(() => createComponent({ state: REQUEST_STATE.PREVIOUSLY_REQUESTED }));

    it('renders only the Learn more button, with the confirm variant', () => {
      expect(findLearnMoreButton().props('variant')).toBe('confirm');
      expect(findRequestButton().exists()).toBe(false);
    });

    it('renders an empty, but present, supporting text region', () => {
      expect(findSupportingText().exists()).toBe(true);
      expect(findSupportingText().text()).toBe('');
    });
  });

  it('opens the Learn more link to the pricing page in a new tab', () => {
    createComponent();

    const link = findLearnMoreButton();
    expect(link.attributes('href')).toBe(`${PROMO_URL}/pricing/premium`);
    expect(link.attributes('target')).toBe('_blank');
  });

  it('emits learn-more-click when Learn more is clicked', () => {
    createComponent();

    findLearnMoreButton().vm.$emit('click');

    expect(wrapper.emitted('learn-more-click')).toHaveLength(1);
  });

  it('forwards the modal change event', () => {
    createComponent();

    findModal().vm.$emit('change', false);

    expect(wrapper.emitted('change')).toEqual([[false]]);
  });

  it('forwards the modal hide event', () => {
    createComponent();

    const event = { trigger: 'backdrop' };
    findModal().vm.$emit('hide', event);

    expect(wrapper.emitted('hide')).toEqual([[event]]);
  });
});
