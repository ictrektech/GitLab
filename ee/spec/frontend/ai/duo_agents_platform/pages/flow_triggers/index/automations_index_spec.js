import { GlButton, GlKeysetPagination } from '@gitlab/ui';
import VueApollo from 'vue-apollo';
import Vue, { nextTick } from 'vue';
import VueRouter from 'vue-router';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import PanelActionsPortal from '~/vue_shared/components/panel_actions_portal.vue';
import ResourceListsEmptyState from '~/vue_shared/components/resource_lists/empty_state.vue';
import ResourceListsLoadingStateList from '~/vue_shared/components/resource_lists/loading_state_list.vue';
import EmptyResult from '~/vue_shared/components/empty_result.vue';
import ConfirmActionModal from '~/vue_shared/components/confirm_action_modal.vue';
import AutomationsIndex from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/automations_index.vue';
import AutomationModal from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/automation_modal.vue';
import AutomationDetailsPanel from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_details_panel.vue';
import AutomationRow from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_row.vue';
import AutomationsFilteredSearch from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automations_filtered_search.vue';
import getAiFlowTriggers from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_triggers.query.graphql';
import getAutomations from 'ee/ai/duo_agents_platform/graphql/queries/get_automations.query.graphql';
import getAutomationsCount from 'ee/ai/duo_agents_platform/graphql/queries/get_automations_count.query.graphql';
import AutomationsStats from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automations_stats.vue';
import getAiFlowTriggerRunStats from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_trigger_run_stats.query.graphql';
import deleteAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/delete_ai_flow_trigger.mutation.graphql';
import updateAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import {
  FLOW_TRIGGERS_INDEX_ROUTE,
  FLOW_TRIGGERS_SHOW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { DUO_AGENT_PLATFORM_POLLING_INTERVAL } from 'ee/ai/duo_agents_platform/constants';
import {
  mockAiFlowTriggerRunStatsResponse,
  mockAutomationFactory,
  mockDeleteTriggerResponse,
  mockUpdateTriggerActiveResponse,
  mockUpdateTriggerActiveErrorResponse,
} from '../mocks';

Vue.use(VueApollo);
Vue.use(VueRouter);
jest.mock('~/alert');

const mockTrigger = mockAutomationFactory();

const pageInfo = {
  hasNextPage: true,
  hasPreviousPage: false,
  startCursor: 'start',
  endCursor: 'end',
  __typename: 'PageInfo',
};

const automationsResponse = (nodes = [mockTrigger]) => ({
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: { nodes, pageInfo, __typename: 'AiFlowTriggerConnection' },
      __typename: 'Project',
    },
  },
});

const automationByIdResponse = (nodes) => ({
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: { nodes, __typename: 'AiFlowTriggerConnection' },
      __typename: 'Project',
    },
  },
});

const countResponse = (count) => ({
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: { count, __typename: 'AiFlowTriggerConnection' },
      __typename: 'Project',
    },
  },
});

const defaultVariables = {
  projectPath: 'myProject',
  kind: 'SCHEDULED',
  active: null,
  eventType: null,
  lastRunStatus: null,
  search: null,
  sort: 'LAST_RUN_DESC',
  first: 20,
  last: null,
  after: null,
  before: null,
};

describe('AutomationsIndex', () => {
  let wrapper;
  let router;

  const mockToast = { show: jest.fn() };
  const queryHandler = jest.fn();
  const automationHandler = jest.fn();
  const countHandler = jest.fn();
  const statsHandler = jest.fn();
  const deleteHandler = jest.fn();
  const updateHandler = jest.fn();

  const findPanelActionsPortal = () => wrapper.findComponent(PanelActionsPortal);
  const findLoadingState = () => wrapper.findComponent(ResourceListsLoadingStateList);
  const findEmptyState = () => wrapper.findComponent(ResourceListsEmptyState);
  const findRows = () => wrapper.findAllComponents(AutomationRow);
  const findStats = () => wrapper.findComponent(AutomationsStats);
  const findConfirmModal = () => wrapper.findComponent(ConfirmActionModal);
  const findPanel = () => wrapper.findComponent(AutomationDetailsPanel);
  const findFilteredSearch = () => wrapper.findComponent(AutomationsFilteredSearch);
  const findEmptyResult = () => wrapper.findComponent(EmptyResult);
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findModal = () => wrapper.findComponent(AutomationModal);

  const allAbilities = {
    manageAiFlowTriggers: true,
    readAiCatalogFlow: true,
    readAiCatalogThirdPartyFlow: true,
    createAiCatalogThirdPartyFlow: true,
  };

  const createComponent = async ({ glAbilities = allAbilities, query } = {}) => {
    if (query) await router.push({ query });
    wrapper = shallowMountExtended(AutomationsIndex, {
      router,
      attachTo: document.body,
      apolloProvider: createMockApollo([
        [getAutomations, queryHandler],
        [getAiFlowTriggers, automationHandler],
        [getAutomationsCount, countHandler],
        [getAiFlowTriggerRunStats, statsHandler],
        [deleteAiFlowTriggerMutation, deleteHandler],
        [updateAiFlowTriggerMutation, updateHandler],
      ]),
      provide: { projectPath: 'myProject', glAbilities },
      mocks: { $toast: mockToast },
      stubs: { ResourceListsEmptyState, AutomationsStats },
    });
  };

  beforeEach(() => {
    router = new VueRouter({
      mode: 'abstract',
      routes: [
        { path: '/', name: FLOW_TRIGGERS_INDEX_ROUTE, component: AutomationsIndex },
        { path: '/:id(\\d+)', name: FLOW_TRIGGERS_SHOW_ROUTE, component: AutomationsIndex },
      ],
    });
    queryHandler.mockResolvedValue(automationsResponse());
    automationHandler.mockResolvedValue(automationByIdResponse([mockTrigger]));
    countHandler.mockResolvedValue(countResponse(1));
    statsHandler.mockResolvedValue(mockAiFlowTriggerRunStatsResponse());
    deleteHandler.mockResolvedValue(mockDeleteTriggerResponse);
    updateHandler.mockResolvedValue(mockUpdateTriggerActiveResponse);
  });

  it('renders the loading state while fetching', () => {
    createComponent();

    expect(findLoadingState().exists()).toBe(true);
    expect(findRows()).toHaveLength(0);
    expect(findStats().exists()).toBe(false);
  });

  it('renders a row for each automation', async () => {
    createComponent();
    await waitForPromises();

    expect(queryHandler).toHaveBeenCalledWith(defaultVariables);
    expect(findRows().at(0).props()).toEqual({
      automation: mockTrigger,
      isToggling: false,
      isSelected: false,
    });
    expect(findPanel().exists()).toBe(false);
    expect(findStats().exists()).toBe(true);
    expect(findEmptyState().exists()).toBe(false);
  });

  it('renders the empty state with a "New automation" button when there are no automations', async () => {
    countHandler.mockResolvedValue(countResponse(0));
    createComponent();
    await waitForPromises();

    expect(findEmptyState().props('title')).toBe('No automations yet');
    expect(findStats().exists()).toBe(false);
    expect(findEmptyState().findComponent(GlButton).props('variant')).toBe('confirm');
    expect(findEmptyState().findComponent(GlButton).text()).toBe('New automation');
  });

  it('reports a count query failure to Sentry', async () => {
    jest.spyOn(Sentry, 'captureException');
    const error = new Error();
    countHandler.mockRejectedValue(error);
    createComponent();
    await waitForPromises();

    expect(Sentry.captureException).toHaveBeenCalledWith(
      expect.objectContaining({ networkError: error }),
    );
  });

  it('creates an alert when the query fails', async () => {
    queryHandler.mockRejectedValue(new Error());
    createComponent();
    await waitForPromises();

    expect(createAlert).toHaveBeenCalledWith({
      message: 'Failed to fetch automations',
      captureError: true,
      error: expect.any(Error),
    });
  });

  describe('polling', () => {
    const advancePollInterval = async () => {
      jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
      await waitForPromises();
    };

    it('polls while an automation is running and stops when none are', async () => {
      queryHandler
        .mockResolvedValueOnce(automationsResponse([mockAutomationFactory({ runningCount: 1 })]))
        .mockResolvedValue(automationsResponse());
      createComponent();
      await waitForPromises();

      await advancePollInterval();
      await advancePollInterval();

      expect(queryHandler).toHaveBeenCalledTimes(2);
    });

    it('stops polling when a poll fails', async () => {
      queryHandler
        .mockResolvedValueOnce(automationsResponse([mockAutomationFactory({ runningCount: 1 })]))
        .mockRejectedValue(new Error());
      createComponent();
      await waitForPromises();

      await advancePollInterval();
      await advancePollInterval();
      await advancePollInterval();

      expect(createAlert).toHaveBeenCalledTimes(1);
      expect(queryHandler).toHaveBeenCalledTimes(2);
    });

    it('does not poll when no automation is running', async () => {
      createComponent();
      await waitForPromises();

      await advancePollInterval();

      expect(queryHandler).toHaveBeenCalledTimes(1);
    });
  });

  describe('"New automation" button', () => {
    it('renders in the panel header', () => {
      createComponent();

      const button = findPanelActionsPortal().findComponent(GlButton);

      expect(button.props()).toMatchObject({ variant: 'confirm', size: 'small' });
      expect(button.text()).toBe('New automation');
    });

    it('opens the modal to create an automation', async () => {
      createComponent();
      expect(findModal().exists()).toBe(false);

      findPanelActionsPortal().findComponent(GlButton).vm.$emit('click');
      await nextTick();

      expect(findModal().props('automation')).toBeNull();
    });

    it('does not render in the panel header or the empty state without the abilities', async () => {
      countHandler.mockResolvedValue(countResponse(0));
      createComponent({ glAbilities: {} });
      await waitForPromises();

      expect(findPanelActionsPortal().exists()).toBe(false);
      expect(findEmptyState().findComponent(GlButton).exists()).toBe(false);
    });

    it('does not render without the ability to manage automations', async () => {
      countHandler.mockResolvedValue(countResponse(0));
      createComponent({ glAbilities: { ...allAbilities, manageAiFlowTriggers: false } });
      await waitForPromises();

      expect(findPanelActionsPortal().exists()).toBe(false);
      expect(findEmptyState().findComponent(GlButton).exists()).toBe(false);
      expect(findEmptyState().props('description')).toBe(
        'Automations connect flows or external agents to events or schedules in this project.',
      );
    });
  });

  describe('when a row asks to edit', () => {
    it('opens the modal with the automation, and closes it when hidden', async () => {
      createComponent();
      await waitForPromises();

      findRows().at(0).vm.$emit('edit', mockTrigger);
      await nextTick();

      expect(findModal().props('automation')).toEqual(mockTrigger);

      findModal().vm.$emit('saved');
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);
      expect(countHandler).toHaveBeenCalledTimes(2);

      findModal().vm.$emit('hidden');
      await nextTick();

      expect(findModal().exists()).toBe(false);
    });
  });

  describe('filters', () => {
    it('renders the filtered search with the defaults', async () => {
      createComponent();
      await waitForPromises();

      expect(findFilteredSearch().props()).toEqual({
        kind: 'scheduled',
        filters: {},
        sort: 'LAST_RUN_DESC',
      });
    });

    it('queries with the valid filters from the route query', async () => {
      await createComponent({
        query: {
          kind: 'event',
          status: 'off',
          event: 'mention',
          last_run: 'never',
          search: 'weekly',
          sort: 'TOTAL_RUNS_ASC',
        },
      });
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledWith({
        ...defaultVariables,
        kind: 'EVENT',
        active: false,
        eventType: 'MENTION',
        lastRunStatus: 'NEVER',
        search: 'weekly',
        sort: 'TOTAL_RUNS_ASC',
      });
    });

    it('caps the search at the backend limit', async () => {
      await createComponent({ query: { search: 'a'.repeat(300) } });
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledWith({ ...defaultVariables, search: 'a'.repeat(255) });
    });

    it('ignores invalid values and the event for the scheduled kind', async () => {
      await createComponent({
        query: { kind: 'other', status: 'maybe', event: 'mention', last_run: 'BAD', sort: 'BAD' },
      });
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledWith(defaultVariables);
    });

    it('renders the empty state for the kind when it has no automations', async () => {
      queryHandler.mockResolvedValue(automationsResponse([]));
      await createComponent({ query: { kind: 'event' } });
      await waitForPromises();

      expect(findEmptyState().props('title')).toBe('No event based automations');
      expect(findFilteredSearch().exists()).toBe(true);
    });

    it('renders the no results state when no automations match', async () => {
      queryHandler.mockResolvedValue(automationsResponse([]));
      await createComponent({ query: { search: 'nothing' } });
      await waitForPromises();

      expect(findEmptyResult().props('type')).toBe('filter');
      expect(findFilteredSearch().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('pagination', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      findPagination().vm.$emit('next');
      await waitForPromises();
    });

    it('fetches the next page', () => {
      expect(findPagination().props()).toMatchObject({ hasNextPage: true, endCursor: 'end' });
      expect(queryHandler).toHaveBeenLastCalledWith({ ...defaultVariables, after: 'end' });
    });

    it('returns to the first page when the filters change', async () => {
      router.replace({ query: { status: 'on' } });
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith({ ...defaultVariables, active: true });
      expect(queryHandler).toHaveBeenCalledTimes(3);
    });

    it('returns to the first page when a later page comes back empty', async () => {
      queryHandler.mockResolvedValueOnce(automationsResponse([]));
      findPagination().vm.$emit('prev');
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith(defaultVariables);
      expect(findRows()).toHaveLength(1);
    });

    it('stays on the page when a details panel opens', async () => {
      router.push({ name: FLOW_TRIGGERS_SHOW_ROUTE, params: { id: 1 } });
      await waitForPromises();

      expect(findPanel().exists()).toBe(true);
      expect(queryHandler).toHaveBeenCalledTimes(2);
    });
  });

  describe('when an automation is toggled', () => {
    const toggle = async () => {
      createComponent();
      await waitForPromises();
      findRows().at(0).vm.$emit('toggle', { id: mockTrigger.id, active: false });
    };

    it('shows the loading state on the row, then a toast', async () => {
      await toggle();
      await Vue.nextTick();

      expect(findRows().at(0).props('isToggling')).toBe(true);

      await waitForPromises();

      expect(updateHandler).toHaveBeenCalledWith({ input: { id: mockTrigger.id, active: false } });
      expect(mockToast.show).toHaveBeenCalledWith('Automation turned off');
      expect(findRows().at(0).props('isToggling')).toBe(false);
      expect(queryHandler).toHaveBeenCalledTimes(1);
    });

    it('refetches the list when a status filter is set', async () => {
      await createComponent({ query: { status: 'on' } });
      await waitForPromises();
      findRows().at(0).vm.$emit('toggle', { id: mockTrigger.id, active: false });
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);
    });

    it('creates an alert with the returned errors', async () => {
      updateHandler.mockResolvedValue(mockUpdateTriggerActiveErrorResponse);
      await toggle();
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Trigger could not be updated' });
      expect(mockToast.show).not.toHaveBeenCalled();
      expect(findRows().at(0).props('isToggling')).toBe(false);
    });

    it('creates an alert with the generic message when the request fails', async () => {
      updateHandler.mockRejectedValue(new Error('Network error'));
      await toggle();
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to update automation.',
        error: expect.any(Error),
        captureError: true,
      });
    });
  });

  describe('when an automation is deleted', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      findRows().at(0).vm.$emit('delete', mockTrigger.id);
      await Vue.nextTick();
    });

    it('deletes the automation after confirmation and shows a toast', async () => {
      expect(findConfirmModal().props('title')).toBe('Delete automation');

      findConfirmModal().props('actionFn')();
      await waitForPromises();

      expect(deleteHandler).toHaveBeenCalledWith({ id: mockTrigger.id });
      expect(queryHandler).toHaveBeenCalledTimes(2);
      expect(countHandler).toHaveBeenCalledTimes(2);
      expect(statsHandler).toHaveBeenCalledTimes(2);
      expect(mockToast.show).toHaveBeenCalledWith('Automation deleted successfully.');
      expect(findConfirmModal().exists()).toBe(false);
    });

    it('creates an alert when the delete fails', async () => {
      deleteHandler.mockRejectedValue(new Error());

      findConfirmModal().props('actionFn')();
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to delete automation.',
        captureError: true,
        error: expect.any(Error),
      });
      expect(findConfirmModal().exists()).toBe(false);
    });
  });

  describe('automation details panel', () => {
    const secondTrigger = mockAutomationFactory({
      id: 'gid://gitlab/Ai::FlowTrigger/2',
      description: 'Second trigger',
    });

    beforeEach(() => {
      queryHandler.mockResolvedValue(automationsResponse([mockTrigger, secondTrigger]));
      automationHandler.mockImplementation(({ ids }) =>
        Promise.resolve(
          automationByIdResponse([mockTrigger, secondTrigger].filter(({ id }) => ids.includes(id))),
        ),
      );
    });

    describe('when the route changes to another automation', () => {
      beforeEach(async () => {
        await router.push('/1?foo=bar');
        createComponent();
        await waitForPromises();
        router.push('/2?foo=bar');
        await waitForPromises();
      });

      it('opens the panel for that automation', () => {
        expect(findPanel().props('automation')).toEqual(secondTrigger);
        expect(findRows().at(0).props('isSelected')).toBe(false);
        expect(findRows().at(1).props('isSelected')).toBe(true);
      });

      it('removes the automation from the URL on close and focuses the row', async () => {
        const rowButton = document.createElement('button');
        rowButton.dataset.automationId = secondTrigger.id;
        findRows().at(1).element.appendChild(rowButton);

        findPanel().vm.$emit('close');
        await waitForPromises();

        expect(router.currentRoute.path).toBe('/');
        expect(router.currentRoute.query).toEqual({ foo: 'bar' });
        expect(findPanel().exists()).toBe(false);
        expect(document.activeElement).toBe(rowButton);
      });
    });

    describe('with a deep link to an automation', () => {
      beforeEach(async () => {
        await router.push('/2');
        createComponent();
        await waitForPromises();
      });

      it('opens the panel', () => {
        expect(findPanel().props('automation')).toEqual(secondTrigger);
      });

      it('keeps the panel open when the next page does not include the automation', async () => {
        queryHandler.mockResolvedValue(
          automationsResponse([mockAutomationFactory({ id: 'gid://gitlab/Ai::FlowTrigger/3' })]),
        );
        findPagination().vm.$emit('next');
        await waitForPromises();

        expect(router.currentRoute.path).toBe('/2');
        expect(findPanel().props('automation')).toMatchObject({ id: secondTrigger.id });
      });

      it('removes the automation from the URL when it is deleted', async () => {
        queryHandler.mockResolvedValue(automationsResponse());
        findRows().at(1).vm.$emit('delete', secondTrigger.id);
        await nextTick();
        findConfirmModal().props('actionFn')();
        await waitForPromises();

        expect(router.currentRoute.path).toBe('/');
      });
    });

    describe('with a deep link to an unknown automation', () => {
      beforeEach(async () => {
        await router.push('/999');
        createComponent();
        await waitForPromises();
      });

      it('removes the automation from the URL', () => {
        expect(router.currentRoute.path).toBe('/');
        expect(findPanel().exists()).toBe(false);
      });
    });
  });
});
