import { nextTick } from 'vue';
import { GlBadge, GlDisclosureDropdown } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import FlowTriggerConditions from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_conditions.vue';
import FlowTriggerConditionForm from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_condition_form.vue';
import FlowTriggerConditionRow from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_condition_row.vue';

describe('FlowTriggerConditions', () => {
  let wrapper;

  const pipelineFilter = {
    pipeline_hooks: {
      rules: [{ field: 'object_attributes.status', operator: 'in', value: ['failed'] }],
    },
  };

  const createWrapper = ({ props = {}, provide = {}, stubs = {}, attachTo } = {}) => {
    wrapper = shallowMountExtended(FlowTriggerConditions, {
      propsData: { itemTypeLabel: 'flow', ...props },
      provide: { glFeatures: {}, isGroupNamespace: false, ...provide },
      stubs: { CrudComponent, ...stubs },
      attachTo,
    });
  };

  const findRows = () => wrapper.findAllComponents(FlowTriggerConditionRow);
  const findForm = () => wrapper.findComponent(FlowTriggerConditionForm);
  const findAddDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findAddItems = () => findAddDropdown().props('items');
  // The dropdown renders items as data, so adding is driven through the item's action.
  const triggerAddEvent = () => {
    findAddItems()
      .find(({ text }) => text === 'On an event')
      .action();
    return nextTick();
  };
  const findEmpty = () => wrapper.findByTestId('crud-empty');
  const findError = () => wrapper.findByTestId('conditions-error');

  const lastEmitted = (event) => {
    const emissions = wrapper.emitted(event);
    return emissions[emissions.length - 1][0];
  };

  describe('when nothing is configured', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders an empty state that offers only an event', () => {
      expect(findEmpty().text()).toBe('No conditions yet. Add an event.');
    });

    it('reports the list as invalid', () => {
      expect(lastEmitted('update:filter-valid')).toBe(false);
    });

    it('does not show an error until errors are requested', () => {
      expect(findError().exists()).toBe(false);
    });
  });

  describe('when errors are shown and nothing is configured', () => {
    beforeEach(() => {
      createWrapper({ props: { showErrors: true } });
    });

    it('explains that a condition is required', () => {
      expect(findError().text()).toBe('Add a condition so this flow knows when to run.');
    });
  });

  describe('when conditions are configured', () => {
    beforeEach(() => {
      createWrapper({
        props: { eventTypes: ['mention', 'pipeline_hooks'], filter: pipelineFilter },
      });
    });

    it('renders a row per configured condition', () => {
      expect(findRows()).toHaveLength(2);
      expect(findRows().at(0).props('typeValue')).toBe('mention');
      expect(findRows().at(1).props('typeValue')).toBe('pipeline_hooks');
    });

    it('reports the list as valid', () => {
      expect(lastEmitted('update:filter-valid')).toBe(true);
    });
  });

  describe('when a configured event type is missing its configuration', () => {
    beforeEach(() => {
      createWrapper({ props: { eventTypes: ['pipeline_hooks'], showErrors: true } });
    });

    it('reports the list as invalid', () => {
      expect(lastEmitted('update:filter-valid')).toBe(false);
    });

    it('surfaces the error on the row', () => {
      expect(findRows().at(0).props('invalidFeedback')).toBe('Select at least one pipeline event.');
    });
  });

  describe('adding a condition', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('does not render the form until something is being added', () => {
      expect(findForm().exists()).toBe(false);
    });

    // The schedule event type is gated off until the backend lands, so only the event
    // choice is offered for now.
    it('offers a choice per catalyst', () => {
      expect(findAddItems().map(({ text }) => text)).toEqual(['On an event']);
    });

    it('opens an event form', async () => {
      await triggerAddEvent();

      expect(findForm().props()).toMatchObject({ mode: 'event', typeValue: null, isNew: true });
    });

    it('appends the saved condition', async () => {
      await triggerAddEvent();
      await findForm().vm.$emit('save', {
        typeValue: 'pipeline_hooks',
        filter: pipelineFilter,
      });

      expect(lastEmitted('update:event-types')).toEqual(['pipeline_hooks']);
      expect(lastEmitted('update:filter')).toEqual(pipelineFilter);
    });

    it('closes the form on cancel', async () => {
      await triggerAddEvent();
      await findForm().vm.$emit('cancel');

      expect(findForm().exists()).toBe(false);
    });

    describe('when schedules are enabled', () => {
      const glFeatures = { aiFlowSchedules: true, autonomousServiceAccountExecution: true };

      it('offers a schedule and an event', () => {
        createWrapper({ provide: { glFeatures }, props: { scheduleSupported: true } });

        expect(findAddItems().map(({ text }) => text)).toEqual(['On a schedule', 'On an event']);
      });

      it('does not offer a schedule within a group namespace', () => {
        createWrapper({
          provide: { glFeatures, isGroupNamespace: true },
          props: { scheduleSupported: true },
        });

        expect(findAddItems().map(({ text }) => text)).toEqual(['On an event']);
      });

      it('does not offer a schedule when the flow cannot be scheduled', () => {
        createWrapper({ provide: { glFeatures }, props: { scheduleSupported: false } });

        expect(findAddItems().map(({ text }) => text)).toEqual(['On an event']);
      });

      it('names a schedule in the empty state and description when one can be added', () => {
        createWrapper({ provide: { glFeatures }, props: { scheduleSupported: true } });

        expect(findEmpty().text()).toBe('No conditions yet. Add a schedule or an event.');
        expect(wrapper.findComponent(CrudComponent).props('description')).toBe(
          'Run at set times, or when something happens in the project. You can have multiple conditions.',
        );
      });

      it('omits the schedule from the empty state and description when one cannot be added', () => {
        createWrapper({ provide: { glFeatures }, props: { scheduleSupported: false } });

        expect(findEmpty().text()).toBe('No conditions yet. Add an event.');
        expect(wrapper.findComponent(CrudComponent).props('description')).toBe(
          'Run when something happens in the project. You can have multiple conditions.',
        );
      });

      it('marks only the schedule choice as beta', () => {
        createWrapper({
          provide: { glFeatures },
          props: { scheduleSupported: true },
          stubs: {
            GlDisclosureDropdown: {
              props: ['items'],
              template: `<ul><li v-for="item in items" :key="item.text" data-testid="add-item">
                <slot name="list-item" :item="item" /></li></ul>`,
            },
          },
        });
        const items = wrapper.findAllByTestId('add-item').wrappers;

        expect(items.map((item) => item.findComponent(GlBadge).exists())).toEqual([true, false]);
      });
    });
  });

  describe('while a condition form is open', () => {
    beforeEach(async () => {
      createWrapper({ props: { eventTypes: ['mention'], showErrors: true } });
      await triggerAddEvent();
    });

    it('reports the list as invalid, so the trigger cannot be saved mid-edit', () => {
      expect(lastEmitted('update:filter-valid')).toBe(false);
    });

    it('says what to do about it', () => {
      expect(findError().text()).toBe('Finish or cancel the open condition before saving.');
    });

    it('becomes valid again once the form is closed', async () => {
      await findForm().vm.$emit('cancel');

      expect(lastEmitted('update:filter-valid')).toBe(true);
      expect(findError().exists()).toBe(false);
    });
  });

  describe('event types already in the list', () => {
    beforeEach(async () => {
      createWrapper({ props: { eventTypes: ['mention'] } });
      await triggerAddEvent();
    });

    it('are not selectable again', () => {
      const values = findForm()
        .props('typeOptions')
        .map(({ value }) => value);

      expect(values).not.toContain('mention');
    });
  });

  describe('the merge request event description', () => {
    it.each`
      mergeRequestMergedFlowTrigger | dapSoftwareFactory | description
      ${false}                      | ${false}           | ${'Trigger flow when a merge request is created, ready, approved, or has conflicts.'}
      ${true}                       | ${false}           | ${'Trigger flow when a merge request is created, ready, approved, merged, or has conflicts.'}
      ${false}                      | ${true}            | ${'Trigger flow when a merge request is created, ready, approved, has changes requested, or has conflicts.'}
      ${true}                       | ${true}            | ${'Trigger flow when a merge request is created, ready, approved, merged, has changes requested, or has conflicts.'}
    `(
      'is "$description" when merged is $mergeRequestMergedFlowTrigger and dapSoftwareFactory is $dapSoftwareFactory',
      async ({ mergeRequestMergedFlowTrigger, dapSoftwareFactory, description }) => {
        createWrapper({
          provide: { glFeatures: { mergeRequestMergedFlowTrigger, dapSoftwareFactory } },
        });
        await triggerAddEvent();

        const option = findForm()
          .props('typeOptions')
          .find(({ value }) => value === 'merge_request');

        expect(option.description).toBe(description);
      },
    );
  });

  describe('editing a condition', () => {
    beforeEach(async () => {
      createWrapper({
        props: { eventTypes: ['mention', 'pipeline_hooks'], filter: pipelineFilter },
      });
      await findRows().at(1).vm.$emit('edit');
    });

    it('opens the form with the existing configuration', () => {
      expect(findForm().props()).toMatchObject({
        mode: 'event',
        typeValue: 'pipeline_hooks',
        filter: pipelineFilter,
        isNew: false,
      });
    });

    it('marks only the edited row, so the list shows what the form is working on', () => {
      expect(findRows().at(0).props('isEditing')).toBe(false);
      expect(findRows().at(1).props('isEditing')).toBe(true);
    });

    it('unmarks the row once the form closes', async () => {
      await findForm().vm.$emit('cancel');

      expect(findRows().at(1).props('isEditing')).toBe(false);
    });

    it('keeps the edited event type selectable', () => {
      const values = findForm()
        .props('typeOptions')
        .map(({ value }) => value);

      expect(values).toContain('pipeline_hooks');
    });

    it('replaces the condition in place', async () => {
      await findForm().vm.$emit('save', { typeValue: 'work_item', filter: {} });

      expect(lastEmitted('update:event-types')).toEqual(['mention', 'work_item']);
    });

    it('drops the configuration of the event type it replaced', async () => {
      await findForm().vm.$emit('save', { typeValue: 'work_item', filter: {} });

      expect(lastEmitted('update:filter')).toEqual({});
    });
  });

  // The row that opened the form is disabled straight afterwards, so focus cannot be left
  // behind on it. Needs the real form, whose container carries the tabindex, attached to the
  // document so it can actually take focus.
  describe('focus handling', () => {
    const createAttachedWrapper = () =>
      createWrapper({
        props: { eventTypes: ['mention'] },
        stubs: { FlowTriggerConditionForm },
        attachTo: document.body,
      });

    it('moves focus into the form when a condition is opened for editing', async () => {
      createAttachedWrapper();

      await findRows().at(0).vm.$emit('edit');
      await nextTick();

      expect(findForm().element).toBe(document.activeElement);
    });

    it('moves focus into the form when a condition is added', async () => {
      createAttachedWrapper();

      await triggerAddEvent();
      await nextTick();

      expect(findForm().element).toBe(document.activeElement);
    });
  });

  describe('removing a condition', () => {
    beforeEach(async () => {
      createWrapper({
        props: { eventTypes: ['mention', 'pipeline_hooks'], filter: pipelineFilter },
      });
      await findRows().at(1).vm.$emit('remove');
    });

    it('drops the event type', () => {
      expect(lastEmitted('update:event-types')).toEqual(['mention']);
    });

    it('drops its configuration', () => {
      expect(lastEmitted('update:filter')).toEqual({});
    });
  });

  describe('when the condition being edited is removed', () => {
    beforeEach(async () => {
      createWrapper({ props: { eventTypes: ['mention'] } });
      await findRows().at(0).vm.$emit('edit');
      await findRows().at(0).vm.$emit('remove');
    });

    it('closes the form', () => {
      expect(findForm().exists()).toBe(false);
    });
  });

  describe('goals', () => {
    const goals = { mention: 'Summarize the thread.' };

    it('passes the goal for the condition being edited into the form', async () => {
      createWrapper({
        props: { eventTypes: ['mention'], goals, goalSupported: true, goalHelpVisible: true },
      });
      await findRows().at(0).vm.$emit('edit');

      expect(findForm().props()).toMatchObject({
        goal: 'Summarize the thread.',
        goalSupported: true,
        goalHelpVisible: true,
      });
    });

    it('passes an empty goal when the condition has none', async () => {
      createWrapper({ props: { eventTypes: ['mention'], goalSupported: true } });
      await findRows().at(0).vm.$emit('edit');

      expect(findForm().props('goal')).toBe('');
    });

    it('stores the goal the form saves', async () => {
      createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: true } });
      await findRows().at(0).vm.$emit('edit');

      await findForm().vm.$emit('save', {
        typeValue: 'mention',
        filter: {},
        goal: 'Reply in three bullets.',
      });

      expect(lastEmitted('update:goals')).toEqual({ mention: 'Reply in three bullets.' });
    });

    // The model rejects an empty goal, so the key goes rather than holding ''.
    it('drops the key when the goal is cleared', async () => {
      createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: true } });
      await findRows().at(0).vm.$emit('edit');

      await findForm().vm.$emit('save', { typeValue: 'mention', filter: {}, goal: '' });

      expect(lastEmitted('update:goals')).toEqual({});
    });

    it('moves the goal when the condition changes event type', async () => {
      createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: true } });
      await findRows().at(0).vm.$emit('edit');

      await findForm().vm.$emit('save', {
        typeValue: 'pipeline_hooks',
        filter: {},
        goal: 'Summarize the thread.',
      });

      expect(lastEmitted('update:goals')).toEqual({ pipeline_hooks: 'Summarize the thread.' });
    });

    it('shows the goal on the collapsed row', () => {
      createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: true } });

      expect(findRows().at(0).props('goal')).toBe('Summarize the thread.');
    });

    it('passes an empty goal to a row that has none', () => {
      createWrapper({ props: { eventTypes: ['mention'], goalSupported: true } });

      expect(findRows().at(0).props('goal')).toBe('');
    });

    it('drops the goal when the condition is removed', async () => {
      createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: true } });

      await findRows().at(0).vm.$emit('remove');

      expect(lastEmitted('update:goals')).toEqual({});
    });

    // An edit must not erase a goal the author cannot see.
    describe('when the flow accepts no goal', () => {
      it('keeps the stored goal through an edit', async () => {
        createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: false } });
        await findRows().at(0).vm.$emit('edit');

        await findForm().vm.$emit('save', { typeValue: 'mention', filter: {}, goal: '' });

        expect(lastEmitted('update:goals')).toEqual({ mention: 'Summarize the thread.' });
      });

      // Moving it would be a new key, and goals_available refuses one while the flag is off.
      it('drops the stored goal when the event type changes', async () => {
        createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: false } });
        await findRows().at(0).vm.$emit('edit');

        await findForm().vm.$emit('save', { typeValue: 'pipeline_hooks', filter: {}, goal: '' });

        expect(lastEmitted('update:goals')).toEqual({});
      });

      it('shows no goal on the collapsed row', () => {
        createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: false } });

        expect(findRows().at(0).props('goal')).toBe('');
      });

      it('adds no goal for a new condition', async () => {
        createWrapper({ props: { eventTypes: ['mention'], goals, goalSupported: false } });
        await triggerAddEvent();

        await findForm().vm.$emit('save', { typeValue: 'pipeline_hooks', filter: {}, goal: '' });

        expect(lastEmitted('update:goals')).toEqual(goals);
      });
    });
  });

  describe('starting with a schedule', () => {
    const glFeatures = { aiFlowSchedules: true, autonomousServiceAccountExecution: true };
    const timezoneData = [{ identifier: 'America/Chicago', name: 'Central Time', offset: -21600 }];

    const createStartingWrapper = ({ props = {}, attachTo } = {}) =>
      createWrapper({
        props: { startWithSchedule: true, scheduleSupported: true, compact: true, ...props },
        provide: { glFeatures, timezoneData, userTimezone: 'America/Chicago' },
        stubs: { FlowTriggerConditionForm },
        attachTo,
      });

    it('opens a new weekly schedule filled with defaults in the user time zone', async () => {
      createStartingWrapper();
      await nextTick();

      expect(findForm().props()).toMatchObject({ mode: 'scheduled', isNew: true });
      expect(findForm().props('filter')).toEqual({
        scheduled: {
          frequency: 'WEEKLY',
          dayOfWeek: expect.any(Number),
          hour: expect.any(Number),
          minute: expect.any(Number),
          timezone: 'America/Chicago',
        },
      });
    });

    it('leaves focus where it is', async () => {
      createStartingWrapper({ attachTo: document.body });
      await nextTick();

      expect(document.activeElement).toBe(document.body);
    });

    it('does not open a schedule when one cannot be added', async () => {
      createStartingWrapper({ props: { scheduleSupported: false } });
      await nextTick();

      expect(findForm().exists()).toBe(false);
    });

    it('closes the schedule when the target stops supporting schedules', async () => {
      createStartingWrapper();
      await nextTick();
      expect(findForm().exists()).toBe(true);

      await wrapper.setProps({ scheduleSupported: false });

      expect(findForm().exists()).toBe(false);
    });

    it('starts a schedule added from the menu empty when not compact', async () => {
      createStartingWrapper({ props: { startWithSchedule: false, compact: false } });

      findAddItems()
        .find(({ text }) => text === 'On a schedule')
        .action();
      await nextTick();

      expect(findForm().props('filter')).toEqual({});
    });
  });

  describe('when compact', () => {
    beforeEach(() => {
      createWrapper({ props: { compact: true }, stubs: { GlDisclosureDropdown } });
    });

    it('uses the automation modal copy', () => {
      expect(wrapper.findComponent(CrudComponent).props()).toMatchObject({
        title: 'Runs when',
        description: null,
      });
      expect(findAddDropdown().props('toggleText')).toBe('Add trigger');
      expect(findEmpty().text()).toBe('No triggers yet. Add an event.');
    });

    it('passes compact to the condition form', async () => {
      await triggerAddEvent();

      expect(findForm().props('compact')).toBe(true);
    });
  });
});
