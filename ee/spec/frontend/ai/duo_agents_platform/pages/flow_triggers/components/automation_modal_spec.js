import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlFormGroup, GlModal, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import AutomationModal from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/automation_modal.vue';
import FlowTriggerConditions from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_conditions.vue';
import UserSelect from '~/vue_shared/components/user_select/user_select.vue';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import createAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/create_ai_flow_trigger.mutation.graphql';
import updateAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import getCatalogConsumerItemsQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_catalog_consumer_items.query.graphql';
import projectServiceAccountRolesQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_project_service_account_roles.query.graphql';
import {
  mockCatalogFlowsResponseFactory,
  mockCatalogItemConsumerFactory,
  mockCreateFlowTriggerErrorMutation,
  mockCreateFlowTriggerSuccessMutation,
  mockFlowTriggerFactory,
  mockServiceAccountRolesResponse,
  mockUpdateFlowTriggerSuccessMutation,
} from '../mocks';

Vue.use(VueApollo);

describe('AutomationModal', () => {
  let wrapper;
  let createMock;
  let updateMock;

  const projectPath = 'group/project';
  const mockToast = { show: jest.fn() };
  const hideMock = jest.fn();
  const developer = mockCatalogItemConsumerFactory({
    id: 3,
    itemId: 30,
    name: 'Developer',
    foundationalFlowReference: 'developer/v1',
  });
  const otherFlow = mockCatalogItemConsumerFactory({ serviceAccountId: 502 });
  const externalAgent = mockCatalogItemConsumerFactory({
    id: 4,
    itemId: 40,
    name: 'External agent',
    itemType: 'THIRD_PARTY_FLOW',
  });

  const createComponent = ({
    automation = null,
    aiFlowTriggerGoals = true,
    createResponse = mockCreateFlowTriggerSuccessMutation,
    catalogItems = [developer, otherFlow, externalAgent],
  } = {}) => {
    createMock = jest.fn().mockResolvedValue(createResponse);
    updateMock = jest.fn().mockResolvedValue(mockUpdateFlowTriggerSuccessMutation);

    wrapper = shallowMountExtended(AutomationModal, {
      apolloProvider: createMockApollo([
        [
          getCatalogConsumerItemsQuery,
          jest.fn().mockResolvedValue(mockCatalogFlowsResponseFactory(catalogItems)),
        ],
        [
          projectServiceAccountRolesQuery,
          jest.fn().mockResolvedValue(mockServiceAccountRolesResponse),
        ],
        [createAiFlowTriggerMutation, createMock],
        [updateAiFlowTriggerMutation, updateMock],
      ]),
      propsData: { automation },
      provide: {
        projectPath,
        projectId: '1',
        glFeatures: { aiFlowTriggerGoals },
        glAbilities: { readAiCatalogFlow: true, createAiCatalogThirdPartyFlow: true },
      },
      mocks: { $toast: mockToast },
      stubs: {
        GlModal: stubComponent(GlModal, { methods: { hide: hideMock } }),
        GlFormGroup,
        GlSprintf,
      },
    });

    return waitForPromises();
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findTargetListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findConditions = () => wrapper.findComponent(FlowTriggerConditions);
  const findInstructionsHelpLink = () =>
    wrapper
      .findAllComponents(HelpPageLink)
      .wrappers.find(
        (link) => link.props('href') === 'user/duo_agent_platform/flows/custom_flows_schema',
      );
  const findGoal = () => wrapper.findComponentByTestId('automation-goal');

  const fillIn = async ({ eventTypes = ['mention'], goal = 'Fix it' } = {}) => {
    wrapper.findComponentByTestId('automation-name').vm.$emit('input', 'Weekly check');
    findConditions().vm.$emit('update:event-types', eventTypes);
    findConditions().vm.$emit('update:filter-valid', true);
    await nextTick();
    findGoal().vm.$emit('input', goal);
  };

  const submit = () => {
    findModal().vm.$emit('primary', { preventDefault: jest.fn() });
    return waitForPromises();
  };

  describe('when creating', () => {
    beforeEach(() => createComponent());

    it('defaults to Duo Developer and shows its service account role', () => {
      expect(findModal().props('title')).toBe('New automation');
      expect(findTargetListbox().props()).toMatchObject({
        selected: developer.id,
        toggleText: 'Developer',
      });
      expect(wrapper.findByTestId('automation-permissions').text()).toBe('Permissions: Developer');
    });

    it('starts the conditions with a schedule draft', () => {
      expect(findConditions().props('startWithSchedule')).toBe(true);
    });

    it('creates an active automation with the instructions on every event type', async () => {
      await fillIn({ eventTypes: ['mention', 'assign'], goal: ' Fix it ' });
      await submit();

      expect(createMock).toHaveBeenCalledWith({
        input: {
          description: 'Weekly check',
          eventTypes: [0, 1],
          filter: {},
          goals: { mention: 'Fix it', assign: 'Fix it' },
          aiCatalogItemConsumerId: developer.id,
          configPath: null,
          userId: null,
          projectPath,
          active: true,
        },
      });
      expect(mockToast.show).toHaveBeenCalledWith('Automation created successfully.');
      expect(wrapper.emitted('saved')).toHaveLength(1);
      expect(hideMock).toHaveBeenCalled();
    });

    it('does not show the instructions help for Duo Developer', () => {
      expect(findGoal().exists()).toBe(true);
      expect(findInstructionsHelpLink()).toBeUndefined();
    });

    it('shows the instructions help for a custom flow', async () => {
      findTargetListbox().vm.$emit('select', otherFlow.id);
      await nextTick();

      expect(wrapper.text()).toContain('This flow might not use these instructions');
      expect(findInstructionsHelpLink().props('anchor')).toBe('goal-values-by-trigger-type');
    });

    it('requires instructions for Duo Developer only', async () => {
      await fillIn({ goal: '' });
      await submit();

      expect(createMock).not.toHaveBeenCalled();
      expect(wrapper.findByTestId('automation-goal-optional').exists()).toBe(false);

      findTargetListbox().vm.$emit('select', otherFlow.id);
      await submit();

      expect(wrapper.findByTestId('automation-goal-optional').exists()).toBe(true);
      expect(createMock).toHaveBeenCalledWith({
        input: expect.objectContaining({ aiCatalogItemConsumerId: otherFlow.id, goals: {} }),
      });
    });

    it.each`
      case                       | setUp
      ${'no name'}               | ${() => wrapper.findComponentByTestId('automation-name').vm.$emit('input', ' ')}
      ${'no configuration path'} | ${() => findTargetListbox().vm.$emit('select', 'config_path')}
      ${'unfinished conditions'} | ${() => findConditions().vm.$emit('update:filter-valid', false)}
    `('does not save with $case', async ({ setUp }) => {
      await fillIn();
      setUp();
      await submit();

      expect(createMock).not.toHaveBeenCalled();
    });

    it('sends the configuration path and service account for a configuration file', async () => {
      findTargetListbox().vm.$emit('select', 'config_path');
      await fillIn();
      wrapper
        .findComponentByTestId('automation-config-path')
        .vm.$emit('input', ' flows/check.yml ');
      wrapper.findComponent(UserSelect).vm.$emit('input', [{ id: 'gid://gitlab/User/5' }]);
      await submit();

      expect(createMock).toHaveBeenCalledWith({
        input: expect.objectContaining({
          aiCatalogItemConsumerId: null,
          configPath: 'flows/check.yml',
          userId: 'gid://gitlab/User/5',
          goals: { mention: 'Fix it' },
        }),
      });
    });

    it('lists service accounts without the Code Review account', async () => {
      findTargetListbox().vm.$emit('select', 'config_path');
      await nextTick();
      const account = { id: 'gid://gitlab/User/5', username: 'automations-bot' };
      const data = {
        project: {
          projectMembers: {
            nodes: [{ user: null }, { user: { username: 'duo-code-review-1' } }, { user: account }],
          },
        },
      };

      expect(wrapper.findComponent(UserSelect).props('customSearchUsersProcessor')(data)).toEqual([
        account,
      ]);
    });

    it('shows mutation errors and keeps the modal open', async () => {
      await createComponent({ createResponse: mockCreateFlowTriggerErrorMutation });
      await fillIn();
      await submit();

      expect(wrapper.findByTestId('automation-modal-errors').text()).toBe('No input was provided.');
      expect(hideMock).not.toHaveBeenCalled();
      expect(wrapper.emitted('saved')).toBeUndefined();
    });

    it('shows the schedule notice only with a schedule', async () => {
      expect(wrapper.findByTestId('automation-schedule-notice').exists()).toBe(false);

      await fillIn({ eventTypes: ['scheduled'] });

      expect(wrapper.findByTestId('automation-schedule-notice').exists()).toBe(true);
    });

    describe('schedule support', () => {
      const selectTarget = async (value) => {
        findTargetListbox().vm.$emit('select', value);
        await nextTick();
      };

      it('is on for a catalog flow', () => {
        expect(findConditions().props('scheduleSupported')).toBe(true);
      });

      it('is off for a configuration file automation', async () => {
        await selectTarget('config_path');

        expect(findConditions().props('scheduleSupported')).toBe(false);
      });

      it('is off for an external agent', async () => {
        await selectTarget(externalAgent.id);

        expect(findConditions().props('scheduleSupported')).toBe(false);
      });

      it('drops a configured schedule when the target stops supporting it', async () => {
        await fillIn({ eventTypes: ['scheduled'] });
        expect(findConditions().props('eventTypes')).toEqual(['scheduled']);

        await selectTarget(externalAgent.id);

        expect(findConditions().props('eventTypes')).toEqual([]);
      });
    });
  });

  describe('when editing', () => {
    const automation = mockFlowTriggerFactory({
      eventTypes: [0],
      goals: { mention: 'Old goal' },
      configPath: null,
    });

    const prepare = async (options) => {
      await createComponent({ automation, ...options });
      findConditions().vm.$emit('update:filter-valid', true);
    };

    it('prefills the automation and saves changes', async () => {
      await prepare();

      expect(findModal().props('title')).toBe('Edit automation');
      expect(findModal().props('actionPrimary').text).toBe('Save changes');
      expect(findConditions().props('startWithSchedule')).toBe(false);
      expect(findTargetListbox().props('selected')).toBe(automation.aiCatalogItemConsumer.id);
      expect(findGoal().props('value')).toBe('Old goal');

      await submit();

      expect(updateMock).toHaveBeenCalledWith({
        input: {
          id: automation.id,
          description: 'Test trigger',
          eventTypes: [0],
          filter: {},
          goals: { mention: 'Old goal' },
          aiCatalogItemConsumerId: automation.aiCatalogItemConsumer.id,
          configPath: null,
          userId: null,
        },
      });
    });

    it('keeps the configuration file and service account', async () => {
      await createComponent({
        automation: { ...automation, aiCatalogItemConsumer: null, configPath: 'flows/a.yml' },
      });
      findConditions().vm.$emit('update:filter-valid', true);
      await submit();

      expect(findTargetListbox().props('selected')).toBe('config_path');
      expect(updateMock).toHaveBeenCalledWith({
        input: expect.objectContaining({
          aiCatalogItemConsumerId: null,
          configPath: 'flows/a.yml',
          userId: automation.user.id,
        }),
      });
    });

    it('drops stored goals for a flow that does not accept them', async () => {
      const noGoalFlow = mockCatalogItemConsumerFactory({
        id: 4,
        itemId: 40,
        acceptsTriggerGoal: false,
      });
      await prepare({ catalogItems: [developer, otherFlow, noGoalFlow] });
      findTargetListbox().vm.$emit('select', noGoalFlow.id);
      await submit();

      expect(updateMock).toHaveBeenCalledWith({
        input: expect.objectContaining({ aiCatalogItemConsumerId: noGoalFlow.id, goals: {} }),
      });
    });

    it('keeps a flow that is not in the catalog list', async () => {
      await prepare({ catalogItems: [developer] });

      expect(findTargetListbox().props('toggleText')).toBe('Test Flow');

      await submit();

      expect(updateMock).toHaveBeenCalledWith({
        input: expect.objectContaining({
          aiCatalogItemConsumerId: automation.aiCatalogItemConsumer.id,
          goals: { mention: 'Old goal' },
        }),
      });
    });

    it('keeps stored goals when instructions are not available', async () => {
      await prepare({ aiFlowTriggerGoals: false });

      expect(findGoal().exists()).toBe(false);

      await submit();

      expect(updateMock).toHaveBeenCalledWith({
        input: expect.objectContaining({ goals: { mention: 'Old goal' } }),
      });
    });
  });
});
