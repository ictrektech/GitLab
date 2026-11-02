import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { WIDGET_TYPE_WORKPLAN } from '~/work_items/constants';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import { namespaceWorkItemTypesQueryResponse } from 'jest/work_items/mock_data';
import WorkItemEventsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/work_item_events_configuration.vue';
import EventActionsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/event_actions_configuration.vue';

jest.mock('~/alert');

Vue.use(VueApollo);

const buildActionFilter = (actions) => ({
  work_item: { rules: [{ field: 'action', operator: 'in', value: actions }] },
});

const buildFullFilter = (actions, statusNames) => ({
  work_item: {
    rules: [
      { field: 'action', operator: 'in', value: actions },
      { field: 'status.name', operator: 'in', value: statusNames },
    ],
  },
});

const actionRule = (actions) => ({ field: 'action', operator: 'in', value: actions });
const statusRule = (statusNames) => ({ field: 'status.name', operator: 'in', value: statusNames });
const typeRule = (typeIds) => ({ field: 'work_item_type_id', operator: 'in', value: typeIds });
const softwareFactoryRule = (values) => ({
  field: 'software_factory_enabled',
  operator: 'in',
  value: values,
});
const buildFilter = (...rules) => ({ work_item: { rules } });

// In namespaceWorkItemTypesQueryResponse, Issue (1) and Task (5) have different lifecycles.
const TASK_STATUS_NAMES = ['To do', 'In dev', 'In review', 'Complete'];
// Epic, Incident, Issue, Key Result, Objective, Requirement, Task, Test Case, Ticket, Story.
const ALL_TYPE_IDS = [8, 2, 1, 7, 6, 4, 5, 3, 9, 1001];

// namespaceWorkItemTypesQueryResponse has no type with the workplan widget. With the workplan
// flag and the ai_workflows license, the query lists the widget for Issue (1) and Task (5).
// Story (1001) is a custom type based on Issue, not converted from a system type, so its ID and
// name are its own. By default, it has the widget too.
const workItemTypesWithWorkplan = (typeIds = [1, 5, 1001]) => {
  const { namespace } = namespaceWorkItemTypesQueryResponse.data;
  const issueType = namespace.workItemTypes.nodes.find(({ name }) => name === 'Issue');
  const storyType = { ...issueType, id: 'gid://gitlab/WorkItems::Type/1001', name: 'Story' };
  const nodes = [...namespace.workItemTypes.nodes, storyType].map((node) =>
    typeIds.includes(getIdFromGraphQLId(node.id))
      ? {
          ...node,
          widgetDefinitions: [
            ...node.widgetDefinitions,
            { type: WIDGET_TYPE_WORKPLAN, __typename: 'WorkItemWidgetDefinitionGeneric' },
          ],
        }
      : node,
  );

  return {
    data: { namespace: { ...namespace, workItemTypes: { ...namespace.workItemTypes, nodes } } },
  };
};

describe('WorkItemEventsConfiguration', () => {
  let wrapper;
  let queryHandler;

  const createComponent = async ({ props = {}, softwareFactory = false } = {}) => {
    wrapper = shallowMountExtended(WorkItemEventsConfiguration, {
      apolloProvider: createMockApollo([[namespaceWorkItemTypesQuery, queryHandler]]),
      provide: {
        projectPath: 'gitlab-org/gitlab-test',
        glFeatures: { dapSoftwareFactory: softwareFactory },
      },
      propsData: {
        value: {},
        ...props,
      },
    });

    await waitForPromises();
  };

  const findActionsConfiguration = () => wrapper.findComponent(EventActionsConfiguration);
  const findTypeFormGroup = () => wrapper.findByTestId('type-form-group');
  const findTypeListbox = () => findTypeFormGroup().findComponent(GlCollapsibleListbox);
  const findStatusFormGroup = () => wrapper.findByTestId('status-form-group');
  const findStatusListbox = () => findStatusFormGroup().findComponent(GlCollapsibleListbox);
  const findSoftwareFactoryFormGroup = () => wrapper.findByTestId('software-factory-form-group');
  const findSoftwareFactoryListbox = () =>
    findSoftwareFactoryFormGroup().findComponent(GlCollapsibleListbox);
  const findSoftwareFactoryOption = (value) =>
    findSoftwareFactoryListbox()
      .props('items')
      .find((item) => item.value === value);
  const typeValues = () =>
    findTypeListbox()
      .props('items')
      .map((item) => item.value);
  const statusValues = () =>
    findStatusListbox()
      .props('items')
      .map((item) => item.value);

  beforeEach(() => {
    queryHandler = jest.fn().mockResolvedValue(namespaceWorkItemTypesQueryResponse);
  });

  describe('action picker', () => {
    const filter = buildActionFilter(['created']);

    beforeEach(async () => {
      await createComponent({
        props: { value: filter, invalidFeedback: 'Select at least one action.' },
      });
    });

    it('renders EventActionsConfiguration for the work_item scope', () => {
      expect(findActionsConfiguration().props()).toMatchObject({
        scope: 'work_item',
        field: 'action',
        value: filter,
        invalidFeedback: 'Select at least one action.',
      });
    });
  });

  describe('status listbox', () => {
    describe('when "status_changed" is not selected', () => {
      beforeEach(async () => {
        await createComponent({ props: { value: buildActionFilter(['created']) } });
      });

      it('is not rendered', () => {
        expect(findStatusFormGroup().exists()).toBe(false);
      });
    });

    describe('when "status_changed" is the only selected action', () => {
      beforeEach(async () => {
        await createComponent({ props: { value: buildActionFilter(['status_changed']) } });
      });

      it('is enabled', () => {
        expect(findStatusListbox().props('disabled')).toBe(false);
      });

      it('is labelled by the form group', () => {
        expect(findStatusFormGroup().attributes('label-for')).toBe(
          findStatusListbox().props('toggleId'),
        );
      });

      it('fetches the statuses of the project', () => {
        expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/gitlab-test' });
      });

      it('lists each status name once', () => {
        const values = findStatusListbox()
          .props('items')
          .map((item) => item.value);

        expect(values).toEqual(expect.arrayContaining(['To do', 'In progress', 'Done']));
        expect(new Set(values).size).toBe(values.length);
      });

      it('shows "Any status" when nothing is selected', () => {
        expect(findStatusListbox().props('toggleText')).toBe('Any status');
        expect(findStatusListbox().props('selected')).toEqual([]);
      });

      it('adds a status.name rule when statuses are selected', () => {
        findStatusListbox().vm.$emit('select', ['In progress', 'Done']);

        expect(wrapper.emitted('input')).toEqual([
          [buildFullFilter(['status_changed'], ['In progress', 'Done'])],
        ]);
      });
    });

    describe('when "status_changed" is selected with another action', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildActionFilter(['created', 'status_changed']) },
        });
      });

      it('is disabled with a hint', () => {
        expect(findStatusListbox().props('disabled')).toBe(true);
        expect(findStatusFormGroup().attributes('description')).toBe(
          'Available only when Status changed is the only selected action.',
        );
      });
    });

    describe('when the status query fails', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockRejectedValue(new Error('boom'));
        await createComponent({ props: { value: buildActionFilter(['status_changed']) } });
      });

      it('shows an alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message:
              'Something went wrong while fetching work item types and statuses. Please try again.',
          }),
        );
      });

      it('explains the empty listbox', () => {
        expect(findStatusListbox().props('items')).toEqual([]);
        expect(findStatusListbox().props('noResultsText')).toBe(
          'Could not load statuses. Refresh the page to try again.',
        );
      });
    });

    describe('with a work_item_type_id rule', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['status_changed']), typeRule([5])) },
        });
      });

      it('lists only the statuses of the selected types', () => {
        expect(statusValues()).toEqual(TASK_STATUS_NAMES);
      });
    });

    describe('with a selected status that the selected types do not use', () => {
      // "Done" belongs to Issue only.
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['status_changed']),
              typeRule([5]),
              statusRule(['In dev', 'Done']),
            ),
          },
        });
      });

      it('lists the status in a separate group', () => {
        expect(findStatusListbox().props('items')).toEqual([
          {
            text: 'Statuses',
            textSrOnly: true,
            options: TASK_STATUS_NAMES.map((name) => ({ value: name, text: name })),
          },
          { text: 'Not used by the selected types', options: [{ value: 'Done', text: 'Done' }] },
        ]);
      });
    });

    describe('with an unused status that the rule holds twice', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['status_changed']),
              typeRule([5]),
              statusRule(['Done', 'Done']),
            ),
          },
        });
      });

      it('lists the status once', () => {
        expect(findStatusListbox().props('items')).toContainEqual({
          text: 'Not used by the selected types',
          options: [{ value: 'Done', text: 'Done' }],
        });
      });
    });

    describe('with a selected status and types that have no statuses', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(actionRule(['status_changed']), typeRule([2]), statusRule(['Done'])),
          },
        });
      });

      it('lists only the group of the unused status', () => {
        expect(findStatusListbox().props('items')).toEqual([
          { text: 'Not used by the selected types', options: [{ value: 'Done', text: 'Done' }] },
        ]);
      });
    });

    describe('with a selected status that no type uses', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFullFilter(['status_changed'], ['Ready for development']) },
        });
      });

      it('lists the status in a group for any type', () => {
        expect(findStatusListbox().props('items')).toContainEqual({
          text: 'Not used by any type',
          options: [{ value: 'Ready for development', text: 'Ready for development' }],
        });
      });
    });

    describe('with a status.name rule', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFullFilter(['status_changed'], ['In progress', 'Done']) },
        });
      });

      it('shows the selected statuses', () => {
        expect(findStatusListbox().props('selected')).toEqual(['In progress', 'Done']);
        expect(findStatusListbox().props('toggleText')).toBe('In progress, Done');
      });

      it('replaces the rule when the selection changes', () => {
        findStatusListbox().vm.$emit('select', ['Done']);

        expect(wrapper.emitted('input')).toEqual([[buildFullFilter(['status_changed'], ['Done'])]]);
      });

      it('removes the rule when the selection is cleared', () => {
        findStatusListbox().vm.$emit('select', []);

        expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['status_changed'])]]);
      });
    });

    describe('with a status.name rule using another operator', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: {
              work_item: {
                rules: [
                  { field: 'action', operator: 'in', value: ['status_changed'] },
                  { field: 'status.name', operator: 'eq', value: 'In progress' },
                ],
              },
            },
          },
        });
      });

      it('shows no selection', () => {
        expect(findStatusListbox().props('selected')).toEqual([]);
      });

      it('replaces the foreign rule on selection', () => {
        findStatusListbox().vm.$emit('select', ['Done']);

        expect(wrapper.emitted('input')).toEqual([[buildFullFilter(['status_changed'], ['Done'])]]);
      });
    });
  });

  describe('type listbox', () => {
    describe('with the "created" action', () => {
      beforeEach(async () => {
        await createComponent({ props: { value: buildActionFilter(['created']) } });
      });

      it('is rendered and enabled', () => {
        expect(findTypeListbox().props('disabled')).toBe(false);
      });

      it('is labelled by the form group', () => {
        expect(findTypeFormGroup().attributes('label-for')).toBe(
          findTypeListbox().props('toggleId'),
        );
      });

      it('fetches the work item types of the project', () => {
        expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/gitlab-test' });
      });

      it('lists each work item type with the numeric part of its ID as the value', () => {
        expect(findTypeListbox().props('items')).toEqual(
          expect.arrayContaining([
            { value: 1, text: 'Issue' },
            { value: 5, text: 'Task' },
          ]),
        );
      });

      it('shows "Any type" when nothing is selected', () => {
        expect(findTypeListbox().props('toggleText')).toBe('Any type');
        expect(findTypeListbox().props('selected')).toEqual([]);
      });

      it('adds a work_item_type_id rule when types are selected', () => {
        findTypeListbox().vm.$emit('select', [5, 1]);

        expect(wrapper.emitted('input')).toEqual([
          [buildFilter(actionRule(['created']), typeRule([5, 1]))],
        ]);
      });
    });

    describe('with a work_item_type_id rule', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), typeRule([5, 1])) },
        });
      });

      it('shows the selected types', () => {
        expect(findTypeListbox().props('selected')).toEqual([5, 1]);
        expect(findTypeListbox().props('toggleText')).toBe('Task, Issue');
      });

      it('replaces the rule when the selection changes', () => {
        findTypeListbox().vm.$emit('select', [1]);

        expect(wrapper.emitted('input')).toEqual([
          [buildFilter(actionRule(['created']), typeRule([1]))],
        ]);
      });

      it('removes the rule when the selection is cleared', () => {
        findTypeListbox().vm.$emit('select', []);

        expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['created'])]]);
      });
    });

    describe('with a type ID that the project does not list', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), typeRule([5, 1001])) },
        });
      });

      it('shows the ID', () => {
        expect(findTypeListbox().props('toggleText')).toBe('Task, 1001');
      });

      // The listbox has no item for the ID, so only the reset button can remove it.
      it('removes the rule on reset', () => {
        expect(findTypeListbox().props('resetButtonLabel')).toBe('Clear');

        findTypeListbox().vm.$emit('reset');

        expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['created'])]]);
      });
    });

    describe('with string type IDs', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), typeRule(['5'])) },
        });
      });

      it('shows no selection', () => {
        expect(findTypeListbox().props('selected')).toEqual([]);
      });
    });

    describe('when the query fails', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockRejectedValue(new Error('boom'));
        await createComponent({ props: { value: buildActionFilter(['created']) } });
      });

      it('explains the empty listbox', () => {
        expect(findTypeListbox().props('items')).toEqual([]);
        expect(findTypeListbox().props('noResultsText')).toBe(
          'Could not load work item types. Refresh the page to try again.',
        );
      });
    });

    describe('when the query fails with stored types and statuses', () => {
      const value = buildFilter(
        actionRule(['status_changed']),
        typeRule([5]),
        statusRule(['In dev']),
      );

      beforeEach(async () => {
        queryHandler = jest.fn().mockRejectedValue(new Error('boom'));
        await createComponent({ props: { value } });
      });

      it('keeps the statuses on reset', () => {
        findTypeListbox().vm.$emit('reset');

        expect(wrapper.emitted('input')).toEqual([
          [buildFilter(actionRule(['status_changed']), statusRule(['In dev']))],
        ]);
      });

      it('does not list the stored statuses as unused', () => {
        expect(findStatusListbox().props('items')).toEqual([]);
      });
    });

    describe('with selected statuses of two types', () => {
      // "In dev" belongs to Task only, and "Done" to Issue only.
      const value = buildFilter(actionRule(['status_changed']), statusRule(['In dev', 'Done']));

      beforeEach(async () => {
        await createComponent({ props: { value } });
      });

      it('drops the statuses that the selected types do not have', () => {
        findTypeListbox().vm.$emit('select', [5]);

        expect(wrapper.emitted('input')).toEqual([
          [buildFilter(actionRule(['status_changed']), typeRule([5]), statusRule(['In dev']))],
        ]);
      });

      it('keeps the statuses that the selected types have', () => {
        findTypeListbox().vm.$emit('select', [1, 5]);

        expect(wrapper.emitted('input')).toEqual([
          [
            buildFilter(
              actionRule(['status_changed']),
              statusRule(['In dev', 'Done']),
              typeRule([1, 5]),
            ),
          ],
        ]);
      });

      it('removes the status rule when the selected types have none of the statuses', () => {
        findTypeListbox().vm.$emit('select', [2]);

        expect(wrapper.emitted('input')).toEqual([
          [buildFilter(actionRule(['status_changed']), typeRule([2]))],
        ]);
      });
    });
  });

  describe('software factory listbox', () => {
    beforeEach(() => {
      queryHandler = jest.fn().mockResolvedValue(workItemTypesWithWorkplan());
    });

    describe.each`
      description              | storedRules
      ${'no rule'}             | ${[]}
      ${'the rule in [true]'}  | ${[softwareFactoryRule([true])]}
      ${'the rule in [false]'} | ${[softwareFactoryRule([false])]}
    `('when dap_software_factory is off, with $description', ({ storedRules }) => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), ...storedRules) },
        });
      });

      it('is not rendered', () => {
        expect(findSoftwareFactoryFormGroup().exists()).toBe(false);
      });

      it('lists every type', () => {
        expect(typeValues()).toEqual(ALL_TYPE_IDS);
      });

      describe('when the types change', () => {
        beforeEach(() => {
          findTypeListbox().vm.$emit('select', [2]);
        });

        it('keeps the stored rules', () => {
          expect(wrapper.emitted('input')).toEqual([
            [buildFilter(actionRule(['created']), ...storedRules, typeRule([2]))],
          ]);
        });
      });
    });

    describe('when dap_software_factory is off, with the rule in [true] and no selected type', () => {
      // Only Task (5) has the widget here. "Done" belongs to Issue and Story only.
      const value = buildFilter(
        actionRule(['status_changed']),
        statusRule(['Done']),
        softwareFactoryRule([true]),
      );

      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workItemTypesWithWorkplan([5]));
        await createComponent({ props: { value } });
      });

      it('lists the statuses of every type', () => {
        expect(statusValues()).toEqual(expect.arrayContaining(['Done', ...TASK_STATUS_NAMES]));
      });

      describe('when the type selection is cleared', () => {
        beforeEach(() => {
          findTypeListbox().vm.$emit('reset');
        });

        it('keeps the status', () => {
          expect(wrapper.emitted('input')).toEqual([[value]]);
        });
      });
    });

    describe.each(['created', 'status_changed'])('with the "%s" action', (action) => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildActionFilter([action]) },
          softwareFactory: true,
        });
      });

      it('is rendered', () => {
        expect(findSoftwareFactoryListbox().exists()).toBe(true);
      });
    });

    describe('without a software_factory_enabled rule', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildActionFilter(['created']) },
          softwareFactory: true,
        });
      });

      it('is labelled by the form group', () => {
        expect(findSoftwareFactoryFormGroup().attributes('label')).toBe('Software Factory');
        expect(findSoftwareFactoryFormGroup().attributes('label-for')).toBe(
          findSoftwareFactoryListbox().props('toggleId'),
        );
      });

      it('shows "Any work item" and no selection, so the Clear button is hidden', () => {
        expect(findSoftwareFactoryListbox().props()).toMatchObject({
          toggleText: 'Any work item',
          selected: null,
          resetButtonLabel: 'Clear',
          headerText: 'Select work items',
        });
      });

      it('offers two enabled options', () => {
        expect(findSoftwareFactoryListbox().props('items')).toEqual([
          { value: 'yes', text: 'Software Factory work items', disabled: false },
          { value: 'no', text: 'Other work items', disabled: false },
        ]);
      });

      it('describes the filter', () => {
        expect(findSoftwareFactoryFormGroup().attributes('description')).toBe(
          'Run only for Software Factory work items, or only for other work items. Leave empty to run for any work item.',
        );
      });

      it('lists every type', () => {
        expect(typeValues()).toEqual(ALL_TYPE_IDS);
      });

      describe.each`
        text                             | option   | values
        ${'Software Factory work items'} | ${'yes'} | ${[true]}
        ${'Other work items'}            | ${'no'}  | ${[false]}
      `('when "$text" is selected', ({ option, values }) => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', option);
        });

        it('adds the rule', () => {
          expect(wrapper.emitted('input')).toEqual([
            [buildFilter(actionRule(['created']), softwareFactoryRule(values))],
          ]);
        });
      });
    });

    describe('with the rule in [true]', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['status_changed']),
              statusRule(['Done']),
              softwareFactoryRule([true]),
            ),
          },
          softwareFactory: true,
        });
      });

      it('selects "Software Factory work items"', () => {
        expect(findSoftwareFactoryListbox().props()).toMatchObject({
          selected: 'yes',
          toggleText: 'Software Factory work items',
        });
      });

      it('lists only the types with the workplan widget', () => {
        expect(findTypeListbox().props('items')).toEqual([
          { value: 1, text: 'Issue' },
          { value: 5, text: 'Task' },
          { value: 1001, text: 'Story' },
        ]);
      });

      describe('when "Other work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'no');
        });

        it('replaces the rule', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['status_changed']),
                statusRule(['Done']),
                softwareFactoryRule([false]),
              ),
            ],
          ]);
        });
      });

      describe('when the selection is cleared', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('reset');
        });

        it('removes the rule and keeps the other rules', () => {
          expect(wrapper.emitted('input')).toEqual([
            [buildFilter(actionRule(['status_changed']), statusRule(['Done']))],
          ]);
        });
      });
    });

    describe('with the rule in [true], a status of a type without the workplan widget, and no selected type', () => {
      // Only Task (5) has the widget here. "Done" belongs to Issue and Story only.
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workItemTypesWithWorkplan([5]));
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['status_changed']),
              statusRule(['Done']),
              softwareFactoryRule([true]),
            ),
          },
          softwareFactory: true,
        });
      });

      it('lists only the statuses of the types with the workplan widget', () => {
        expect(findStatusListbox().props('items')).toEqual([
          {
            text: 'Statuses',
            textSrOnly: true,
            options: TASK_STATUS_NAMES.map((name) => ({ value: name, text: name })),
          },
          {
            text: 'Not used by types that support Software Factory',
            options: [{ value: 'Done', text: 'Done' }],
          },
        ]);
      });

      describe('when the type selection is cleared', () => {
        beforeEach(() => {
          findTypeListbox().vm.$emit('reset');
        });

        it('drops the status', () => {
          expect(wrapper.emitted('input')).toEqual([
            [buildFilter(actionRule(['status_changed']), softwareFactoryRule([true]))],
          ]);
        });
      });
    });

    describe('with the rule in [true], a selected type without the workplan widget, and its status', () => {
      // Only Task (5) has the widget here. "Done" belongs to Issue and Story only.
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workItemTypesWithWorkplan([5]));
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['status_changed']),
              typeRule([1]),
              statusRule(['Done']),
              softwareFactoryRule([true]),
            ),
          },
          softwareFactory: true,
        });
      });

      it('lists no status of the type', () => {
        expect(findStatusListbox().props('items')).toEqual([
          { text: 'Not used by the selected types', options: [{ value: 'Done', text: 'Done' }] },
        ]);
      });

      describe('when a type with the widget is added', () => {
        beforeEach(() => {
          findTypeListbox().vm.$emit('select', [1, 5]);
        });

        it('drops the status', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['status_changed']),
                softwareFactoryRule([true]),
                typeRule([1, 5]),
              ),
            ],
          ]);
        });
      });
    });

    describe('with the rule in [true] and a type without the workplan widget', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['created']),
              typeRule([2, 5]),
              softwareFactoryRule([true]),
            ),
          },
          softwareFactory: true,
        });
      });

      it('lists the type in a separate group', () => {
        expect(findTypeListbox().props('items')).toEqual([
          {
            text: 'Work item types',
            textSrOnly: true,
            options: [
              { value: 1, text: 'Issue' },
              { value: 5, text: 'Task' },
              { value: 1001, text: 'Story' },
            ],
          },
          { text: 'Not supported by Software Factory', options: [{ value: 2, text: 'Incident' }] },
        ]);
      });
    });

    describe('with the rule in [true] and only types without the workplan widget', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(actionRule(['created']), typeRule([2]), softwareFactoryRule([true])),
          },
          softwareFactory: true,
        });
      });

      it('selects the disabled "Software Factory work items" option', () => {
        expect(findSoftwareFactoryListbox().props('selected')).toBe('yes');
        expect(findSoftwareFactoryOption('yes').disabled).toBe(true);
      });

      it('explains why', () => {
        expect(findSoftwareFactoryFormGroup().attributes('description')).toBe(
          'None of the available work item types support Software Factory.',
        );
      });

      it('lists the type in a separate group', () => {
        expect(findTypeListbox().props('items')).toEqual([
          {
            text: 'Work item types',
            textSrOnly: true,
            options: [
              { value: 1, text: 'Issue' },
              { value: 5, text: 'Task' },
              { value: 1001, text: 'Story' },
            ],
          },
          { text: 'Not supported by Software Factory', options: [{ value: 2, text: 'Incident' }] },
        ]);
      });
    });

    describe('with the rule in [false]', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(actionRule(['created']), softwareFactoryRule([false])),
          },
          softwareFactory: true,
        });
      });

      it('selects "Other work items"', () => {
        expect(findSoftwareFactoryListbox().props()).toMatchObject({
          selected: 'no',
          toggleText: 'Other work items',
        });
      });

      it('lists every type', () => {
        expect(typeValues()).toEqual(ALL_TYPE_IDS);
      });

      describe('when the selection is cleared', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('reset');
        });

        it('removes the rule', () => {
          expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['created'])]]);
        });
      });
    });

    describe('with the rule in [true, false]', () => {
      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(actionRule(['created']), softwareFactoryRule([true, false])),
          },
          softwareFactory: true,
        });
      });

      it('shows no selection, because the rule matches every work item', () => {
        expect(findSoftwareFactoryListbox().props('selected')).toBe(null);
      });
    });

    describe('with selected types that do not all have the workplan widget', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), typeRule([2, 1001, 5])) },
          softwareFactory: true,
        });
      });

      describe('when "Software Factory work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'yes');
        });

        it('removes the types without the widget', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['created']),
                softwareFactoryRule([true]),
                typeRule([1001, 5]),
              ),
            ],
          ]);
        });
      });

      describe('when "Other work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'no');
        });

        it('keeps the types', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['created']),
                typeRule([2, 1001, 5]),
                softwareFactoryRule([false]),
              ),
            ],
          ]);
        });
      });
    });

    describe('with a selected type ID that the project does not list', () => {
      beforeEach(async () => {
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), typeRule([5, 1002])) },
          softwareFactory: true,
        });
      });

      describe('when "Software Factory work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'yes');
        });

        it('keeps the ID', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['created']),
                typeRule([5, 1002]),
                softwareFactoryRule([true]),
              ),
            ],
          ]);
        });
      });
    });

    describe('with selected statuses of a type that loses its selection', () => {
      // Only Task (5) has the widget here. "In dev" belongs to Task only, "Done" to Issue and Story.
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workItemTypesWithWorkplan([5]));
        await createComponent({
          props: {
            value: buildFilter(
              actionRule(['status_changed']),
              typeRule([1, 5]),
              statusRule(['In dev', 'Done']),
            ),
          },
          softwareFactory: true,
        });
      });

      describe('when "Software Factory work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'yes');
        });

        it('drops the statuses of the removed types', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['status_changed']),
                softwareFactoryRule([true]),
                typeRule([5]),
                statusRule(['In dev']),
              ),
            ],
          ]);
        });
      });
    });

    describe('with selected statuses and no selected type', () => {
      // Only Task (5) has the widget here. "In dev" belongs to Task only, "Done" to Issue and Story.
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workItemTypesWithWorkplan([5]));
        await createComponent({
          props: {
            value: buildFilter(actionRule(['status_changed']), statusRule(['In dev', 'Done'])),
          },
          softwareFactory: true,
        });
      });

      describe('when "Software Factory work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'yes');
        });

        it('drops the statuses of the types without the widget', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['status_changed']),
                softwareFactoryRule([true]),
                statusRule(['In dev']),
              ),
            ],
          ]);
        });
      });

      describe('when "Other work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'no');
        });

        it('keeps the statuses', () => {
          expect(wrapper.emitted('input')).toEqual([
            [
              buildFilter(
                actionRule(['status_changed']),
                statusRule(['In dev', 'Done']),
                softwareFactoryRule([false]),
              ),
            ],
          ]);
        });
      });
    });

    describe.each`
      description                          | storedRules
      ${'no rule'}                         | ${[]}
      ${'a rule that matches every value'} | ${[softwareFactoryRule([true, false])]}
    `('when no type of the namespace has the widget, with $description', ({ storedRules }) => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(namespaceWorkItemTypesQueryResponse);
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), ...storedRules) },
          softwareFactory: true,
        });
      });

      it('is not rendered', () => {
        expect(findSoftwareFactoryFormGroup().exists()).toBe(false);
      });
    });

    describe.each`
      description                                                            | response                               | value
      ${'no type of the namespace has the widget, with the rule in [false]'} | ${namespaceWorkItemTypesQueryResponse} | ${buildFilter(actionRule(['created']), softwareFactoryRule([false]))}
      ${'no type of the namespace has the widget, with the rule in [true]'}  | ${namespaceWorkItemTypesQueryResponse} | ${buildFilter(actionRule(['created']), softwareFactoryRule([true]))}
      ${'no selected type, listed or not, has the widget'}                   | ${workItemTypesWithWorkplan()}         | ${buildFilter(actionRule(['created']), typeRule([2, 1002]))}
    `('when $description', ({ response, value }) => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(response);
        await createComponent({ props: { value }, softwareFactory: true });
      });

      it('disables only "Software Factory work items"', () => {
        expect(findSoftwareFactoryOption('yes').disabled).toBe(true);
        expect(findSoftwareFactoryOption('no').disabled).toBe(false);
      });

      it('explains why', () => {
        expect(findSoftwareFactoryFormGroup().attributes('description')).toBe(
          'None of the available work item types support Software Factory.',
        );
      });
    });

    describe.each`
      description                | handler
      ${'before the types load'} | ${() => jest.fn().mockReturnValue(new Promise(() => {}))}
      ${'when the query fails'}  | ${() => jest.fn().mockRejectedValue(new Error('boom'))}
    `('$description', ({ handler }) => {
      beforeEach(async () => {
        queryHandler = handler();
        await createComponent({
          props: { value: buildFilter(actionRule(['created']), typeRule([2])) },
          softwareFactory: true,
        });
      });

      it('does not disable an option', () => {
        expect(findSoftwareFactoryOption('yes').disabled).toBe(false);
      });

      describe('when "Software Factory work items" is selected', () => {
        beforeEach(() => {
          findSoftwareFactoryListbox().vm.$emit('select', 'yes');
        });

        it('keeps the types', () => {
          expect(wrapper.emitted('input')).toEqual([
            [buildFilter(actionRule(['created']), typeRule([2]), softwareFactoryRule([true]))],
          ]);
        });
      });
    });

    describe('when the action selection changes', () => {
      const nextFilter = buildFilter(
        actionRule(['created', 'status_changed']),
        softwareFactoryRule([true]),
      );

      beforeEach(async () => {
        await createComponent({
          props: {
            value: buildFilter(actionRule(['status_changed']), softwareFactoryRule([true])),
          },
          softwareFactory: true,
        });
        findActionsConfiguration().vm.$emit('input', nextFilter);
      });

      it('keeps the rule', () => {
        expect(wrapper.emitted('input')).toEqual([[nextFilter]]);
      });
    });
  });

  describe('when the action selection changes', () => {
    beforeEach(async () => {
      await createComponent({
        props: { value: buildFullFilter(['status_changed'], ['In progress']) },
      });
    });

    it('keeps the status rule while "status_changed" is the only action', () => {
      const nextFilter = buildFullFilter(['status_changed'], ['In progress']);
      findActionsConfiguration().vm.$emit('input', nextFilter);

      expect(wrapper.emitted('input')).toEqual([[nextFilter]]);
    });

    it('drops the status rule when another action is added', () => {
      findActionsConfiguration().vm.$emit(
        'input',
        buildFullFilter(['created', 'status_changed'], ['In progress']),
      );

      expect(wrapper.emitted('input')).toEqual([
        [buildActionFilter(['created', 'status_changed'])],
      ]);
    });

    it('drops the status rule when "status_changed" is deselected', () => {
      findActionsConfiguration().vm.$emit('input', buildFullFilter(['created'], ['In progress']));

      expect(wrapper.emitted('input')).toEqual([[buildActionFilter(['created'])]]);
    });

    it('emits an empty filter when every action is deselected', () => {
      findActionsConfiguration().vm.$emit('input', {
        work_item: { rules: [{ field: 'status.name', operator: 'in', value: ['In progress'] }] },
      });

      expect(wrapper.emitted('input')).toEqual([[{}]]);
    });
  });

  describe('when another action is added to a filter with a type rule', () => {
    beforeEach(async () => {
      await createComponent({
        props: {
          value: buildFilter(actionRule(['status_changed']), statusRule(['In dev']), typeRule([5])),
        },
      });

      findActionsConfiguration().vm.$emit(
        'input',
        buildFilter(
          actionRule(['created', 'status_changed']),
          statusRule(['In dev']),
          typeRule([5]),
        ),
      );
    });

    it('drops the status rule and keeps the type rule', () => {
      expect(wrapper.emitted('input')).toEqual([
        [buildFilter(actionRule(['created', 'status_changed']), typeRule([5]))],
      ]);
    });
  });
});
