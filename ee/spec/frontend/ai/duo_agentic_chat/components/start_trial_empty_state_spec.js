import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import {
  DUO_PANEL_EVENT_CLICK_BUY_CREDITS,
  DUO_PANEL_EVENT_CLICK_LEARN_MORE_CREDITS,
  DUO_PANEL_EVENT_CLICK_START_TRIAL,
  DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE,
} from 'ee/ai/constants';
import StartTrialEmptyState from 'ee/ai/duo_agentic_chat/components/start_trial_empty_state.vue';
import DuoWorkflowExamplesCard from 'ee/ai/duo_agentic_chat/components/duo_workflow_examples_card.vue';

const { bindInternalEventDocument } = useMockInternalEventsTracking();
const newTrialPathMock = '/-/trials/new';
const trialDurationMock = '20';

describe('StartTrialEmptyState', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(StartTrialEmptyState, {
      propsData: {
        newTrialPath: newTrialPathMock,
        trialDuration: trialDurationMock,
        ...props,
      },
      stubs: {
        GlSprintf,
      },
    });
  };

  const findEmptyStateText = () => wrapper.findByTestId('empty-state-text');
  const findTrialCard = () => wrapper.findByTestId('trial-card');
  const findCreditsCard = () => wrapper.findByTestId('credits-card');
  const findStartTrialLink = () => wrapper.findComponentByTestId('start-trial-link');
  const findBuyCreditsLink = () => wrapper.findComponentByTestId('buy-credits-link');
  const findCreditsDocsLink = () => wrapper.findComponentByTestId('credits-docs-link');
  const findWorkflowExamplesCard = () => wrapper.findComponent(DuoWorkflowExamplesCard);

  beforeEach(() => createComponent());

  it('tracks the `view_duo_agentic_not_available_empty_state` on mount', () => {
    createComponent();
    const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

    expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE, {}, undefined);
  });

  it('renders the workflow examples card', () => {
    expect(findWorkflowExamplesCard().exists()).toBe(true);
  });

  describe('when buyCreditsPath is not provided', () => {
    it('renders the single-option description', () => {
      expect(findEmptyStateText().text()).toBe(
        'Automate tasks with AI agents, from searching projects to creating commits.',
      );
    });

    it('does not render the credits card', () => {
      expect(findCreditsCard().exists()).toBe(false);
    });
  });

  describe('when buyCreditsPath is provided', () => {
    beforeEach(() => {
      createComponent({ buyCreditsPath: '/buy-credits' });
    });

    it('renders the two-ways-to-start description', () => {
      expect(findEmptyStateText().text()).toBe(
        'Automate tasks with AI agents, from searching projects to creating commits. Two ways to start.',
      );
    });

    it('renders the credits card', () => {
      expect(findCreditsCard().exists()).toBe(true);
    });

    it('describes credits without referring to compute minutes', () => {
      expect(findCreditsCard().text()).toContain('power AI capabilities and other add-ons.');
    });

    it('renders the buy-credits button with the correct href', () => {
      expect(findBuyCreditsLink().props('href')).toBe('/buy-credits');
    });

    it('tracks `click_duo_agentic_not_available_empty_state_buy_credits` when clicked', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent(findBuyCreditsLink().element);

      expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_CLICK_BUY_CREDITS, {});
    });

    it('renders the credits docs link with the correct href', () => {
      expect(findCreditsDocsLink().props('href')).toBe(
        '/help/subscriptions/gitlab_credits#monthly-commitment-pool',
      );
    });

    it('tracks `click_duo_agentic_not_available_empty_state_learn_more_credits` when clicked', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent(findCreditsDocsLink().element);

      expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_CLICK_LEARN_MORE_CREDITS, {});
    });
  });

  describe('trial card', () => {
    it('interpolates the trial duration into the heading', () => {
      expect(findTrialCard().text()).toContain('Start a free 20-day trial');
    });

    it('renders the start-trial button with the correct href', () => {
      expect(findStartTrialLink().props('href')).toBe(newTrialPathMock);
    });

    it('renders the start-trial button text', () => {
      expect(findStartTrialLink().text()).toBe('Start a free trial');
    });

    it('tracks `click_duo_agentic_not_available_empty_state_start_trial` when clicked', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent(findStartTrialLink().element);

      expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_CLICK_START_TRIAL, {});
    });
  });
});
