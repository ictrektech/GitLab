import { GlButton } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import CreditGatedModelCard from 'ee/ai/duo_agentic_chat/components/credit_gated_model_card.vue';

describe('CreditGatedModelCard', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const createComponent = (props = {}) => {
    wrapper = mountExtended(CreditGatedModelCard, {
      propsData: {
        modelName: 'Claude Fable 5',
        modelRef: 'claude_fable_5',
        purchaseCreditsPath: '/purchase-credits',
        canBuyAddon: true,
        ...props,
      },
    });
  };

  const findPurchaseButton = () => wrapper.findByTestId('purchase-credits-button');
  const findLearnMoreButton = () => wrapper.findByTestId('learn-more-button');
  const findDescription = () => wrapper.findByTestId('credit-gated-model-card-description');

  it('names the model the user picked', () => {
    createComponent();

    expect(wrapper.text()).toContain('Purchase credits to use Claude Fable 5');
  });

  it('explains why the model is unavailable and how to proceed', () => {
    createComponent();

    expect(wrapper.text()).toContain("This model isn't included in your trial");
    expect(wrapper.text()).toContain('or select another model');
  });

  it('links to the purchase path tagged with the card as the source', () => {
    createComponent();

    expect(findPurchaseButton().attributes('href')).toBe(
      '/purchase-credits?ref_source=gated_model_chat_card',
    );
  });

  it('links to the credits documentation', () => {
    createComponent();

    expect(findLearnMoreButton().attributes('href')).toContain(
      'subscriptions/gitlab_credits#for-the-free-tier',
    );
  });

  describe('when the user cannot buy the add-on', () => {
    beforeEach(() => {
      createComponent({ canBuyAddon: false });
    });

    it('offers documentation only', () => {
      expect(findPurchaseButton().exists()).toBe(false);
      expect(wrapper.findAllComponents(GlButton)).toHaveLength(1);
      expect(findLearnMoreButton().attributes('href')).toContain(
        'subscriptions/gitlab_credits#for-the-free-tier',
      );
    });

    it('does not tell the user to buy credits they have no permission to buy', () => {
      expect(wrapper.text()).not.toContain('Purchase credits to use');
      expect(wrapper.text()).toContain("Claude Fable 5 isn't included in your trial");
    });

    it('points at the administrator instead', () => {
      expect(findDescription().text()).toBe(
        'Select another model, or contact your administrator to purchase monthly credits.',
      );
    });
  });

  describe('tracking', () => {
    const trackedProperties = { label: 'claude_fable_5', property: 'chat' };

    it('tracks a view when the card renders', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_duo_agentic_gated_model_purchase_card',
        trackedProperties,
        undefined,
      );
    });

    it('tracks a new view when the user switches to another gated model', async () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      trackEventSpy.mockClear();

      await wrapper.setProps({ modelName: 'Claude Opus 5', modelRef: 'claude_opus_5' });

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_duo_agentic_gated_model_purchase_card',
        { label: 'claude_opus_5', property: 'chat' },
        undefined,
      );
    });

    it('does not track a view when the user cannot buy credits', () => {
      createComponent({ canBuyAddon: false });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        'view_duo_agentic_gated_model_purchase_card',
        expect.any(Object),
        undefined,
      );
    });

    it('tracks a click on Learn more when the user cannot buy credits', async () => {
      createComponent({ canBuyAddon: false });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await wrapper.findComponentByTestId('learn-more-button').vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_duo_agentic_gated_model_learn_more',
        trackedProperties,
        undefined,
      );
    });

    it.each`
      button                | testId                       | event
      ${'Purchase credits'} | ${'purchase-credits-button'} | ${'click_duo_agentic_gated_model_purchase_credits'}
      ${'Learn more'}       | ${'learn-more-button'}       | ${'click_duo_agentic_gated_model_learn_more'}
    `('tracks a click on $button', async ({ testId, event }) => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await wrapper.findComponentByTestId(testId).vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(event, trackedProperties, undefined);
    });
  });

  describe('when there is no purchase path', () => {
    it('does not render a broken purchase link', () => {
      createComponent({ purchaseCreditsPath: '' });

      expect(findPurchaseButton().exists()).toBe(false);
    });
  });
});
