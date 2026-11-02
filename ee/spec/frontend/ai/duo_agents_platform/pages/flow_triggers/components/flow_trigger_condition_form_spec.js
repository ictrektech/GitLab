import { GlCollapsibleListbox, GlFormGroup, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import FlowTriggerConditionForm from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_condition_form.vue';
import PipelineEventsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/pipeline_events_configuration.vue';
import ScheduleEventsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/schedule_events_configuration.vue';
import {
  FLOW_TRIGGER_GOAL_MAX_LENGTH,
  FLOW_TRIGGER_MODE_SCHEDULE,
} from 'ee/ai/duo_agents_platform/constants';

describe('FlowTriggerConditionForm', () => {
  let wrapper;

  const typeOptions = [
    { value: 'mention', text: 'Mention', description: 'Trigger flow when mentioned.' },
    { value: 'pipeline_hooks', text: 'Pipeline events' },
  ];

  const pipelineFilter = {
    pipeline_hooks: {
      rules: [{ field: 'object_attributes.status', operator: 'in', value: ['failed'] }],
    },
  };

  const createWrapper = (props = {}, stubs = {}) => {
    wrapper = shallowMountExtended(FlowTriggerConditionForm, {
      propsData: { mode: 'event', typeOptions, ...props },
      stubs: { GlSprintf, ...stubs },
    });
  };

  const findGroup = () => wrapper.findByTestId('condition-form');
  const findHeading = () => wrapper.find('h3');
  const findTypeListbox = () => wrapper.findComponentByTestId('event-type-listbox');
  const findScheduleConfiguration = () => wrapper.findComponent(ScheduleEventsConfiguration);
  const findPipelineConfiguration = () => wrapper.findComponent(PipelineEventsConfiguration);
  const findError = () => wrapper.findByTestId('condition-error');
  const findSaveButton = () => wrapper.findComponentByTestId('save-condition');
  const findCancelButton = () => wrapper.findComponentByTestId('cancel-condition');
  const findGoal = () => wrapper.findComponentByTestId('condition-goal');
  const findGoalGroup = () => wrapper.findComponentByTestId('condition-goal-group');
  const findGoalHelpLink = () => wrapper.findComponent(HelpPageLink);

  describe('event mode', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('offers the selectable event types', () => {
      expect(findTypeListbox().props('items')).toEqual(typeOptions);
    });

    it('does not render a configuration until an event type is selected', () => {
      expect(wrapper.findComponent(GlCollapsibleListbox).exists()).toBe(true);
      expect(findPipelineConfiguration().exists()).toBe(false);
    });

    it('renders the configuration for the selected event type', async () => {
      await findTypeListbox().vm.$emit('select', 'pipeline_hooks');

      expect(findPipelineConfiguration().exists()).toBe(true);
    });

    it('saves an event type that needs no configuration', async () => {
      await findTypeListbox().vm.$emit('select', 'mention');
      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0]).toEqual({
        typeValue: 'mention',
        filter: {},
        goal: '',
      });
    });

    it('saves the configuration collected for the selected event type', async () => {
      await findTypeListbox().vm.$emit('select', 'pipeline_hooks');
      await findPipelineConfiguration().vm.$emit('input', pipelineFilter);
      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0]).toEqual({
        goal: '',
        typeValue: 'pipeline_hooks',
        filter: pipelineFilter,
      });
    });

    it('clears the configuration when the event type changes', async () => {
      await findTypeListbox().vm.$emit('select', 'pipeline_hooks');
      await findPipelineConfiguration().vm.$emit('input', pipelineFilter);
      await findTypeListbox().vm.$emit('select', 'mention');
      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0]).toEqual({
        typeValue: 'mention',
        filter: {},
        goal: '',
      });
    });

    it('emits cancel when the cancel button is clicked', () => {
      findCancelButton().vm.$emit('click');

      expect(wrapper.emitted('cancel')).toHaveLength(1);
    });
  });

  describe('when no event type is selected', () => {
    beforeEach(async () => {
      createWrapper();
      await findSaveButton().vm.$emit('click');
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it('shows an error', () => {
      expect(findError().text()).toBe('Select an event.');
    });
  });

  describe('when the selected event type is not configured', () => {
    beforeEach(async () => {
      createWrapper({ typeValue: 'pipeline_hooks' });
      await findSaveButton().vm.$emit('click');
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it('reports the error on the field that owns it, not as loose text', () => {
      expect(findPipelineConfiguration().props('invalidFeedback')).toBe(
        'Select at least one pipeline event.',
      );
      expect(findError().exists()).toBe(false);
    });
  });

  describe('schedule mode', () => {
    beforeEach(() => {
      createWrapper({ mode: FLOW_TRIGGER_MODE_SCHEDULE, typeValue: 'scheduled' });
    });

    it('skips the event picker', () => {
      expect(findTypeListbox().exists()).toBe(false);
    });

    it('renders the schedule configuration', () => {
      expect(findScheduleConfiguration().exists()).toBe(true);
    });

    it('passes compact to the schedule configuration', () => {
      createWrapper({ mode: FLOW_TRIGGER_MODE_SCHEDULE, typeValue: 'scheduled', compact: true });

      expect(findScheduleConfiguration().props('compact')).toBe(true);
    });

    it('saves a complete schedule', async () => {
      const filter = {
        scheduled: {
          frequency: 'DAILY',
          hour: 9,
          minute: 15,
          timezone: 'Etc/UTC',
        },
      };

      await findScheduleConfiguration().vm.$emit('input', filter);
      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0]).toEqual({
        goal: '',
        typeValue: 'scheduled',
        filter,
      });
    });

    it('does not save an incomplete schedule', async () => {
      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')).toBeUndefined();
      expect(findScheduleConfiguration().props('invalidFeedback')).toBe('Configure the schedule.');
    });
  });

  describe('heading', () => {
    it.each`
      mode                          | isNew    | heading
      ${'event'}                    | ${true}  | ${'New event'}
      ${FLOW_TRIGGER_MODE_SCHEDULE} | ${false} | ${'Edit schedule'}
    `('reads "$heading" for a $mode with isNew $isNew', ({ mode, isNew, heading }) => {
      createWrapper({ mode, isNew });

      expect(findHeading().text()).toBe(heading);
    });

    it('is in the document but not drawn, so it does not repeat the copy on screen', () => {
      createWrapper();

      expect(findHeading().classes()).toContain('gl-sr-only');
    });

    it('names the group', () => {
      createWrapper();

      expect(findGroup().attributes('aria-labelledby')).toBe(findHeading().attributes('id'));
    });
  });

  describe('submit button', () => {
    it.each`
      mode                          | isNew    | label
      ${'event'}                    | ${true}  | ${'Add event'}
      ${FLOW_TRIGGER_MODE_SCHEDULE} | ${true}  | ${'Add schedule'}
      ${'event'}                    | ${false} | ${'Save'}
    `('is labelled "$label" for a $mode with isNew $isNew', ({ mode, isNew, label }) => {
      createWrapper({ mode, isNew });

      expect(findSaveButton().text()).toBe(label);
    });
  });

  describe('goal', () => {
    it('is hidden when the flow does not support a goal', () => {
      createWrapper();

      expect(findGoal().exists()).toBe(false);
    });

    it('is shown and pre-filled when the flow supports a goal', () => {
      createWrapper({ goalSupported: true, goal: 'Summarise the failing jobs.' });

      expect(findGoal().props('value')).toBe('Summarise the failing jobs.');
    });

    it('saves the goal with the condition', async () => {
      createWrapper({ goalSupported: true });
      await findTypeListbox().vm.$emit('select', 'mention');
      await findGoal().vm.$emit('input', '  Summarise the thread.  ');

      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0]).toEqual({
        typeValue: 'mention',
        filter: {},
        goal: 'Summarise the thread.',
      });
    });

    it('keeps the goal when the event type changes', async () => {
      createWrapper({ goalSupported: true, goal: 'Summarise the thread.' });
      await findTypeListbox().vm.$emit('select', 'mention');
      await findTypeListbox().vm.$emit('select', 'pipeline_hooks');

      expect(findGoal().props('value')).toBe('Summarise the thread.');
    });

    describe('when the goal is too long', () => {
      beforeEach(async () => {
        createWrapper({ goalSupported: true });
        await findTypeListbox().vm.$emit('select', 'mention');
        await findGoal().vm.$emit('input', 'a'.repeat(FLOW_TRIGGER_GOAL_MAX_LENGTH + 1));
        await findSaveButton().vm.$emit('click');
      });

      it('does not save', () => {
        expect(wrapper.emitted('save')).toBeUndefined();
      });

      it('reports the limit', () => {
        expect(findGoalGroup().attributes('invalid-feedback')).toBe(
          'Instructions cannot exceed 4096 characters.',
        );
      });
    });

    describe('when the field is hidden with text already typed', () => {
      const createWithTypedGoal = async () => {
        createWrapper({ goalSupported: true });
        await findTypeListbox().vm.$emit('select', 'mention');
        await findGoal().vm.$emit('input', 'a'.repeat(FLOW_TRIGGER_GOAL_MAX_LENGTH + 1));
        await wrapper.setProps({ goalSupported: false });
        await findSaveButton().vm.$emit('click');
      };

      it('saves rather than blocking on a hidden length error', async () => {
        await createWithTypedGoal();

        expect(wrapper.emitted('save')).toHaveLength(1);
      });

      it('saves no goal', async () => {
        await createWithTypedGoal();

        expect(wrapper.emitted('save')[0][0].goal).toBe('');
      });
    });

    it('saves a goal that is exactly at the limit', async () => {
      const goal = 'a'.repeat(FLOW_TRIGGER_GOAL_MAX_LENGTH);
      createWrapper({ goalSupported: true });
      await findTypeListbox().vm.$emit('select', 'mention');
      await findGoal().vm.$emit('input', goal);

      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0].goal).toBe(goal);
    });

    // The model strips a goal before it validates the length, so the form has to
    // measure the same string it sends.
    it('saves a goal that reaches the limit only once trimmed', async () => {
      const goal = 'a'.repeat(FLOW_TRIGGER_GOAL_MAX_LENGTH);
      createWrapper({ goalSupported: true });
      await findTypeListbox().vm.$emit('select', 'mention');
      await findGoal().vm.$emit('input', `  ${goal}  `);

      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0].goal).toBe(goal);
    });

    it('shows the help text as the field description only when asked', async () => {
      createWrapper(
        { goalSupported: true },
        {
          GlFormGroup: stubComponent(GlFormGroup, {
            template: '<div><slot></slot><slot name="description"></slot></div>',
          }),
        },
      );
      expect(findGoalHelpLink().exists()).toBe(false);

      await wrapper.setProps({ goalHelpVisible: true });

      expect(findGoalGroup().text()).toContain('This flow might not use these instructions');
      expect(findGoalHelpLink().props()).toMatchObject({
        href: 'user/duo_agent_platform/flows/custom_flows_schema',
        anchor: 'goal-values-by-trigger-type',
      });
    });

    it('saves the goal of a schedule', async () => {
      const goal = 'Summarise the failing jobs.';
      createWrapper({
        mode: FLOW_TRIGGER_MODE_SCHEDULE,
        typeValue: 'scheduled',
        goalSupported: true,
        goal,
      });
      await findScheduleConfiguration().vm.$emit('input', {
        scheduled: { frequency: 'DAILY', hour: 9, minute: 15, timezone: 'Etc/UTC' },
      });

      await findSaveButton().vm.$emit('click');

      expect(wrapper.emitted('save')[0][0].goal).toBe(goal);
    });
  });
});
