import { GlButton } from '@gitlab/ui';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemReadiness from 'ee/work_items/components/implementation_widget/work_item_readiness.vue';
import ReadinessBar from 'ee/work_items/components/implementation_widget/readiness_bar.vue';
import ReadinessDrawer from 'ee/work_items/components/implementation_widget/readiness_drawer.vue';
import { PLAN_READINESS_LEVELS } from 'ee/work_items/components/implementation_widget/constants';
import ImplementationWidgetSegment from 'ee/vue_shared/components/work_items/implementation_widget_segment.vue';

describe('WorkItemReadiness', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(WorkItemReadiness, {
      propsData: {
        workItemId: 'gid://gitlab/WorkItem/42',
        score: 85,
        feedbackHtml: null,
        isDrawerOpen: false,
        isLoading: false,
        hasError: false,
        ...props,
      },
      stubs: { ImplementationWidgetSegment, GlButton },
      attachTo: document.body,
    });
  };

  const findToggle = () => wrapper.findByTestId('readiness-details-button');
  const findDrawer = () => wrapper.findComponent(ReadinessDrawer);

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(() => createComponent({ score: 72 }));

    it('does not track an event on render', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('tracks the score only the first time the drawer opens', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      findDrawer().vm.$emit('opened');
      findDrawer().vm.$emit('opened');
      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_work_item_agent_plan_readiness_score',
        { value: 72, work_item_id: 42 },
        undefined,
      );
    });
  });

  it('passes the score and readiness level to the bar', () => {
    createComponent({ score: 85 });

    expect(wrapper.findComponent(ReadinessBar).props()).toMatchObject({
      score: 85,
      readinessLevel: PLAN_READINESS_LEVELS.HIGH,
    });
  });

  describe.each([
    [0, 'Low'],
    [39, 'Low'],
    [40, 'Medium'],
    [79, 'Medium'],
    [80, 'High'],
    [100, 'High'],
  ])('with a score of %s', (score, level) => {
    beforeEach(() => createComponent({ score }));

    it('shows the readiness level', () => {
      expect(wrapper.findByRole('img').attributes('aria-label')).toBe(`Readiness: ${level}`);
      expect(wrapper.text()).toContain(level);
    });
  });

  describe('with the drawer closed', () => {
    beforeEach(() => createComponent());

    it('exposes an accessible collapsed button', () => {
      expect(findToggle().attributes('aria-expanded')).toBe('false');
      expect(findDrawer().props('isOpen')).toBe(false);
    });

    it('requests the panel on click', async () => {
      await findToggle().trigger('click');
      expect(wrapper.emitted('toggle')).toHaveLength(1);
    });
  });

  describe('with the drawer open', () => {
    beforeEach(() =>
      createComponent({
        isDrawerOpen: true,
        feedbackHtml: '<p><strong>Improve</strong> the plan</p>',
      }),
    );

    it('passes the feedback and display state to the drawer', () => {
      expect(findToggle().attributes('aria-expanded')).toBe('true');
      expect(findDrawer().props()).toEqual({
        isOpen: true,
        feedbackHtml: '<p><strong>Improve</strong> the plan</p>',
        isLoading: false,
        hasError: false,
      });
    });

    it('returns focus to the trigger after closing', async () => {
      await findDrawer().vm.$emit('close');
      expect(wrapper.emitted('close')).toHaveLength(1);
      expect(document.activeElement).toBe(findToggle().element);
    });
  });
});
