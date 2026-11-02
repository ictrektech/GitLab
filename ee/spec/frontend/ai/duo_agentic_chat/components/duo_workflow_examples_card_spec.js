import { GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import {
  DUO_PANEL_EVENT_CLICK_LEARN_MORE,
  DUO_PANEL_EVENT_CLICK_LEARN_MORE_REQUEST,
} from 'ee/ai/constants';
import { REQUEST_STATE } from 'ee/painted_door_request/utils';
import DuoWorkflowExamplesCard from 'ee/ai/duo_agentic_chat/components/duo_workflow_examples_card.vue';

const { bindInternalEventDocument } = useMockInternalEventsTracking();

describe('DuoWorkflowExamplesCard', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(DuoWorkflowExamplesCard, { propsData: props });
  };

  const findWorkflowExamples = () => wrapper.findAllByTestId('workflow-example');
  const findLearnMoreLink = () => wrapper.findComponentByTestId('learn-more-link');

  beforeEach(createComponent);

  it('renders the heading', () => {
    expect(wrapper.text()).toContain('Get things done with GitLab Duo');
  });

  it('renders the workflow examples', () => {
    const workflowExamples = findWorkflowExamples();

    expect(workflowExamples.at(0).findComponent(GlIcon).props('name')).toBe('merge-request');
    expect(workflowExamples.at(0).text()).toContain('Review a merge request');
    expect(workflowExamples.at(0).text()).toContain('Identify code improvements');

    expect(workflowExamples.at(1).findComponent(GlIcon).props('name')).toBe('pipeline');
    expect(workflowExamples.at(1).text()).toContain('Fix a failing pipeline');
    expect(workflowExamples.at(1).text()).toContain(
      'Analyze pipeline failures and get fix suggestions',
    );
  });

  it('renders the learn-more link with the correct href', () => {
    expect(findLearnMoreLink().props('href')).toBe('/help/user/duo_agent_platform/_index.md');
  });

  it('opens the learn-more link in a new tab', () => {
    expect(findLearnMoreLink().attributes('target')).toBe('_blank');
  });

  describe('when requestState is not set', () => {
    it('tracks `click_duo_agentic_not_available_empty_state_learn_more` when clicked', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent(findLearnMoreLink().element);

      expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_CLICK_LEARN_MORE, {});
    });
  });

  describe('when requestState is set', () => {
    beforeEach(() => {
      createComponent({ requestState: REQUEST_STATE.NOT_REQUESTED, requestGroupId: 123 });
    });

    it('keeps the data-event-tracking attribute on the learn-more link', () => {
      expect(findLearnMoreLink().attributes('data-event-tracking')).toBe(
        DUO_PANEL_EVENT_CLICK_LEARN_MORE,
      );
    });

    it('tracks through InternalEvents with the request state as the label and the group id as the property', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findLearnMoreLink().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        DUO_PANEL_EVENT_CLICK_LEARN_MORE_REQUEST,
        { label: REQUEST_STATE.NOT_REQUESTED, property: '123' },
        undefined,
      );
    });
  });
});
