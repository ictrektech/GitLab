import { GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FlowTriggerConditionRow from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_condition_row.vue';

describe('FlowTriggerConditionRow', () => {
  let wrapper;

  const pipelineFilter = {
    pipeline_hooks: {
      rules: [{ field: 'object_attributes.status', operator: 'in', value: ['failed'] }],
    },
  };

  const scheduleFilter = {
    scheduled: { frequency: 'DAILY', hour: 9, minute: 15, timezone: 'Etc/UTC' },
  };

  const everyFifteenMinutesFilter = { scheduled: { frequency: 'EVERY_15_MINUTES' } };

  const timezoneData = [
    { identifier: 'America/New_York', name: 'Eastern Time (US & Canada)', offset: -18000 },
  ];

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(FlowTriggerConditionRow, {
      propsData: { typeValue: 'mention', ...props },
      provide: { timezoneData },
    });
  };

  const findIcon = () => wrapper.findComponent(GlIcon);
  const findBetaBadge = () => wrapper.findByTestId('schedule-beta-badge');
  const findError = () => wrapper.findByTestId('row-error');
  const findEditingIndicator = () => wrapper.findByTestId('editing-indicator');
  const findEditButton = () => wrapper.findComponentByTestId('edit-condition-button');
  const findRemoveButton = () => wrapper.findComponentByTestId('remove-condition-button');

  describe('when the condition is an event without configuration', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('summarizes the event by name, marked with the event icon', () => {
      expect(wrapper.text()).toContain('Mention');
      expect(findIcon().props('name')).toBe('trigger-source');
      expect(findBetaBadge().exists()).toBe(false);
    });
  });

  describe('when the condition is a configured event', () => {
    beforeEach(() => {
      createWrapper({ typeValue: 'pipeline_hooks', filter: pipelineFilter });
    });

    it('appends the selected conditions to the summary', () => {
      expect(wrapper.text()).toContain('Pipeline events: Failed');
    });
  });

  describe('when the condition is a schedule', () => {
    beforeEach(() => {
      createWrapper({ typeValue: 'scheduled', filter: scheduleFilter });
    });

    it('describes the frequency, marked with the schedule icon and as beta', () => {
      expect(wrapper.text()).toContain('Schedule: Daily at 09:15 Etc/UTC');
      expect(findIcon().props('name')).toBe('clock');
      expect(findBetaBadge().text()).toBe('Beta');
    });
  });

  describe('when the schedule timezone is in the timezone data', () => {
    beforeEach(() => {
      createWrapper({
        typeValue: 'scheduled',
        filter: {
          scheduled: { frequency: 'DAILY', hour: 9, minute: 15, timezone: 'America/New_York' },
        },
      });
    });

    it('names the timezone inline, formatted like the timezone picker', () => {
      expect(wrapper.text()).toContain(
        'Schedule: Daily at 09:15 [UTC-5] Eastern Time (US & Canada)',
      );
    });
  });

  describe('when the condition is a schedule on another frequency', () => {
    beforeEach(() => {
      createWrapper({ typeValue: 'scheduled', filter: everyFifteenMinutesFilter });
    });

    it('reads differently from the daily schedule', () => {
      expect(wrapper.text()).toContain('Schedule: Every 15 minutes');
    });
  });

  describe('when the schedule is not configured yet', () => {
    beforeEach(() => {
      createWrapper({ typeValue: 'scheduled', filter: {} });
    });

    it('names the schedule without describing it', () => {
      expect(wrapper.text()).toMatch(/^Schedule\s+Beta$/);
    });
  });

  describe('when the condition is not fully configured', () => {
    it('names an event type that exists but cannot be added here', () => {
      createWrapper({ typeValue: 'commit_to_default_branch' });

      expect(wrapper.text()).toContain('Commit to default branch');
    });

    it('falls back for an event type it does not recognize', () => {
      createWrapper({ typeValue: 'not_an_event' });

      expect(wrapper.text()).toContain('Unknown event');
    });
  });

  describe('invalid feedback', () => {
    it('is not rendered by default', () => {
      createWrapper();

      expect(findError().exists()).toBe(false);
    });

    it('is rendered when provided', () => {
      createWrapper({ invalidFeedback: 'Select at least one pipeline event.' });

      expect(findError().text()).toBe('Select at least one pipeline event.');
    });
  });

  describe('actions', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('emits edit when the edit button is clicked', () => {
      findEditButton().vm.$emit('click');

      expect(wrapper.emitted('edit')).toHaveLength(1);
    });

    // A disabled button never gets the mouseleave that dismisses its tooltip, so the button
    // is rebuilt instead. Destroying the old one unbinds the tooltip along with it.
    it('rebuilds the actions when they become disabled, so no tooltip outlives them', async () => {
      const editButton = findEditButton().element;
      const removeButton = findRemoveButton().element;

      await wrapper.setProps({ isEditing: true });

      expect(findEditButton().element).not.toBe(editButton);
      expect(findRemoveButton().element).not.toBe(removeButton);
    });

    it('emits remove when the remove button is clicked', () => {
      findRemoveButton().vm.$emit('click');

      expect(wrapper.emitted('remove')).toHaveLength(1);
    });
  });

  describe('when the condition is not being edited', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('is not marked as editing', () => {
      expect(findEditingIndicator().exists()).toBe(false);
      expect(wrapper.find('li').classes()).not.toContain('gl-bg-subtle');
    });

    it('leaves the actions available', () => {
      expect(findEditButton().props('disabled')).toBe(false);
      expect(findRemoveButton().props('disabled')).toBe(false);
    });
  });

  describe('when the condition is being edited', () => {
    beforeEach(() => {
      createWrapper({ isEditing: true });
    });

    it('marks the row as editing', () => {
      expect(findEditingIndicator().text()).toBe('(editing)');
      expect(wrapper.find('li').classes()).toContain('gl-bg-subtle');
    });

    // The open form already owns this condition, so changing it from the list would either
    // fight the form or delete what the user is working on.
    it('disables the actions', () => {
      expect(findEditButton().props('disabled')).toBe(true);
      expect(findRemoveButton().props('disabled')).toBe(true);
    });
  });

  describe('goal', () => {
    const findGoal = () => wrapper.findByTestId('row-goal');

    it('is not rendered when the condition has no goal', () => {
      createWrapper();

      expect(findGoal().exists()).toBe(false);
    });

    it('shows the goal so a saved value is visible without opening the card', () => {
      createWrapper({ goal: 'Summarize the thread.' });

      expect(findGoal().text()).toBe('Summarize the thread.');
    });
  });
});
