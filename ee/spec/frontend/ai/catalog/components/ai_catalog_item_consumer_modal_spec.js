import { nextTick } from 'vue';
import { noop } from 'lodash-es';
import { GlForm, GlFormGroup, GlFormRadioGroup, GlModal, GlSprintf } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import AiCatalogItemConsumerModal from 'ee/ai/catalog/components/ai_catalog_item_consumer_modal.vue';
import FormProjectDropdown from 'ee/ai/catalog/components/form_project_dropdown.vue';
import AiCatalogItemConsumerDisclaimer from 'ee/ai/catalog/components/ai_catalog_item_consumer_disclaimer.vue';
import FlowTriggerConditions from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_conditions.vue';
import {
  AI_CATALOG_TYPE_AGENT,
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  VISIBILITY_LEVEL_PRIVATE,
  VISIBILITY_LEVEL_RESTRICTED,
} from 'ee/ai/catalog/constants';
import { mockFlow, mockAgent, mockProjectWithGroup } from '../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

const mockProjectWithGroupExtended = {
  ...mockProjectWithGroup,
  name: 'Project 1',
  nameWithNamespace: 'Group-1 / Project 1',
  fullPath: 'group-1/project-1',
  rootGroup: {
    ...mockProjectWithGroup.rootGroup,
    fullPath: 'group-1',
  },
};

const triggerTypes = ['mention', 'assign', 'assign_reviewer'];

describe('AiCatalogItemConsumerModal', () => {
  let wrapper;

  const defaultProps = {
    item: mockFlow,
  };
  const GlFormGroupStub = stubComponent(GlFormGroup, {
    props: ['state', 'labelDescription'],
  });

  const createWrapper = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(AiCatalogItemConsumerModal, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide: {
        isGlobalNamespace: true,
        isProjectNamespace: false,
        isGroupNamespace: false,
        projectId: null,
        ...provide,
      },
      stubs: {
        GlSprintf,
        GlFormGroup: GlFormGroupStub,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findForm = () => wrapper.findComponent(GlForm);
  const findFormRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findErrorAlert = () => wrapper.findByTestId('error-alert');
  const findPrivateAlert = () => wrapper.findByTestId('private-alert');
  const findRestrictedAlert = () => wrapper.findByTestId('restricted-alert');
  const findProjectDropdown = () => wrapper.findComponent(FormProjectDropdown);
  const findProjectMultiSelect = () => wrapper.findComponentByTestId('project-multi-select');
  const findProjectName = () => wrapper.findByTestId('project-name');
  const findTriggers = () => wrapper.findComponent(FlowTriggerConditions);
  const findFlowDisclaimer = () => wrapper.findByTestId('flow-disclaimer');
  const findGroupEnablementDisclaimer = () => wrapper.findByTestId('group-enablement-disclaimer');

  describe('component rendering', () => {
    describe('default', () => {
      beforeEach(() => {
        createWrapper();
      });

      it('renders modal and item name', () => {
        expect(findModal().props('title')).toBe('Enable flow in your project');
        expect(findModal().find('dt').text()).toBe('Selected flow');
        expect(findModal().find('dd').text()).toBe(mockFlow.name);
      });

      it('does not render group/project radio group', () => {
        expect(findFormRadioGroup().exists()).toBe(false);
      });

      it('renders the label description of the project field', () => {
        expect(findProjectMultiSelect().props('projectLabelDescription')).toBe(
          'Select one or more projects where the flow should be enabled.',
        );
      });

      describe.each`
        itemType
        ${AI_CATALOG_TYPE_AGENT}
        ${AI_CATALOG_TYPE_FLOW}
        ${AI_CATALOG_TYPE_THIRD_PARTY_FLOW}
      `('when the selected item type is $itemType', ({ itemType }) => {
        it('renders the disclaimer component with correct itemType and canEnable props', () => {
          const item = {
            ...mockFlow,
            itemType,
          };
          createWrapper({ props: { item, canEnable: true } });

          const disclaimerComponent = wrapper.findComponent(AiCatalogItemConsumerDisclaimer);
          expect(disclaimerComponent.exists()).toBe(true);
          expect(disclaimerComponent.props('itemType')).toBe(itemType);
          expect(disclaimerComponent.props('canEnable')).toBe(true);
        });
      });
    });

    describe('when the item is private', () => {
      beforeEach(() => {
        createWrapper({
          props: {
            item: {
              ...mockFlow,
              visibility: VISIBILITY_LEVEL_PRIVATE,
              project: mockProjectWithGroupExtended,
            },
          },
        });
      });

      it('renders private alert with the managing project name', () => {
        expect(findPrivateAlert().exists()).toBe(true);
        expect(findPrivateAlert().text()).toBe(
          'This private flow is managed by Group-1 / Project 1. You can enable it only in that project. Duplicate the flow to use the same configuration in other projects.',
        );
      });

      it('renders project name instead of dropdown', () => {
        expect(findProjectName().text()).toBe(mockProjectWithGroupExtended.nameWithNamespace);
        expect(findProjectDropdown().exists()).toBe(false);
      });
    });

    describe('when item is private but has missing project ID', () => {
      beforeEach(() => {
        createWrapper({
          props: {
            item: {
              ...mockFlow,
              visibility: VISIBILITY_LEVEL_PRIVATE,
              project: { id: undefined, nameWithNamespace: 'projectNamespace' },
            },
          },
        });
      });

      it('does not render error alert due to missing project', () => {
        expect(findErrorAlert().exists()).toBe(false);
      });

      it('does not submit when missing project id', () => {
        findForm().vm.$emit('submit', { preventDefault: noop });

        expect(wrapper.emitted('submit')).toBeUndefined();
      });
    });

    describe('when the item is public', () => {
      beforeEach(() => {
        createWrapper();
      });

      it('renders project multi select', () => {
        expect(findProjectName().exists()).toBe(false);
        expect(findProjectMultiSelect().exists()).toBe(true);
      });

      it('passes the item id to the project multi select so already-enabled projects are filtered out', () => {
        expect(findProjectMultiSelect().props('itemId')).toBe(mockFlow.id);
      });

      it('does not render the error validation initially', () => {
        expect(findProjectMultiSelect().props('isValid')).toBe(true);
      });

      it('renders alert when there was a problem fetching the projects', async () => {
        const error = 'Failed to load projects.';

        await findProjectMultiSelect().vm.$emit('error', error);

        expect(findErrorAlert().text()).toBe(error);
      });

      it('does not render private alert', () => {
        expect(findPrivateAlert().exists()).toBe(false);
      });
    });

    describe('when the item is restricted', () => {
      const restrictedFlow = {
        ...mockFlow,
        visibility: VISIBILITY_LEVEL_RESTRICTED,
        project: mockProjectWithGroupExtended,
      };

      describe('when restricted option is available', () => {
        beforeEach(() => {
          createWrapper({ props: { item: restrictedFlow } });
        });

        it('renders the restricted alert with the group name', () => {
          expect(findRestrictedAlert().exists()).toBe(true);
          expect(findRestrictedAlert().text()).toContain(
            'This flow can only be enabled in projects within the top-level group Group 1.',
          );
        });

        it('renders the project dropdown instead of the static project name', () => {
          expect(findProjectDropdown().exists()).toBe(true);
          expect(findProjectName().exists()).toBe(false);
        });

        it('does not render the private alert', () => {
          expect(findPrivateAlert().exists()).toBe(false);
        });

        describe('when within project namespace', () => {
          beforeEach(() => {
            createWrapper({
              props: { item: restrictedFlow },
              provide: { isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' },
            });
          });

          it('does not render the restricted alert', () => {
            expect(findRestrictedAlert().exists()).toBe(false);
          });
        });
      });
    });

    describe('when within project namespace', () => {
      describe('when the item is public', () => {
        beforeEach(() => {
          createWrapper({
            provide: { isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' },
          });
        });

        it('hides the project section and does not render the private alert', () => {
          expect(findProjectMultiSelect().exists()).toBe(false);
          expect(findProjectName().exists()).toBe(false);
          expect(findPrivateAlert().exists()).toBe(false);
        });
      });

      describe('when the item is private', () => {
        beforeEach(() => {
          createWrapper({
            props: {
              item: {
                ...mockFlow,
                visibility: VISIBILITY_LEVEL_PRIVATE,
                project: mockProjectWithGroupExtended,
              },
            },
            provide: { isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' },
          });
        });

        it('hides the project section and does not render the private alert', () => {
          expect(findProjectDropdown().exists()).toBe(false);
          expect(findProjectName().exists()).toBe(false);
          expect(findPrivateAlert().exists()).toBe(false);
        });
      });

      describe('when the item has direct project configurations in the group', () => {
        beforeEach(() => {
          createWrapper({
            props: {
              item: { ...mockAgent, hasDirectProjectConfigurationsInGroup: true },
              canEnable: true,
            },
            provide: { isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' },
          });
        });

        it('does not render the group enablement disclaimer', () => {
          expect(findGroupEnablementDisclaimer().exists()).toBe(false);
        });
      });
    });
  });

  describe('when submitting the form', () => {
    it('emits the submit event', async () => {
      createWrapper();

      const projectIds = ['gid://gitlab/Project/1', 'gid://gitlab/Project/2'];

      await findProjectMultiSelect().vm.$emit('input', projectIds);
      findForm().vm.$emit('submit', { preventDefault: noop });

      expect(wrapper.emitted('submit')[0][0]).toStrictEqual({
        target: projectIds,
        triggerTypes,
      });
    });

    it('when in the project namespace, submits with the current project id', () => {
      createWrapper({
        provide: { isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' },
      });

      findForm().vm.$emit('submit', { preventDefault: noop });

      expect(wrapper.emitted('submit')[0][0].target.projectId).toBe('gid://gitlab/Project/1');
    });

    describe('when there is no project selected', () => {
      beforeEach(() => {
        createWrapper({
          props: {
            item: { ...mockFlow, project: null },
          },
        });
      });

      it('renders alert', async () => {
        findForm().vm.$emit('submit', { preventDefault: noop });
        await nextTick();

        expect(wrapper.emitted('submit')).toBeUndefined();
        expect(findProjectMultiSelect().props('isValid')).toBe(false);
      });
    });
  });

  describe.each`
    namespace    | provide
    ${'global'}  | ${{}}
    ${'project'} | ${{ isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' }}
  `('when within $namespace namespace', ({ provide }) => {
    it('does not render the flow disclaimer', () => {
      createWrapper({ props: { item: mockFlow, canEnable: true }, provide });

      expect(findFlowDisclaimer().exists()).toBe(false);
    });
  });

  describe('when within group namespace', () => {
    const groupProvide = {
      isGlobalNamespace: false,
      isGroupNamespace: true,
      groupId: '7',
      groupName: 'Test Group',
    };

    describe('rendering', () => {
      beforeEach(() => {
        createWrapper({ props: { item: mockFlow, canEnable: true }, provide: groupProvide });
      });

      it('renders the group title and primary action', () => {
        expect(findModal().props('title')).toBe('Enable flow for all projects in Test Group');
        expect(findModal().props('actionPrimary').text).toBe('Enable for all projects');
        expect(findModal().props('actionPrimary').attributes.variant).toBe('confirm');
      });

      it('renders the trigger conditions', () => {
        expect(findTriggers().exists()).toBe(true);
      });

      it('renders the flow group availability disclaimer', () => {
        expect(findFlowDisclaimer().text()).toBe(
          'This flow will be available in all current and future projects in this group.',
        );
      });

      it('does not render the project section', () => {
        expect(findProjectMultiSelect().exists()).toBe(false);
        expect(findProjectDropdown().exists()).toBe(false);
        expect(findProjectName().exists()).toBe(false);
      });

      it('does not render the group enablement disclaimer', () => {
        expect(findGroupEnablementDisclaimer().exists()).toBe(false);
      });
    });

    describe('when the item has direct project configurations in the group', () => {
      beforeEach(() => {
        createWrapper({
          props: {
            item: { ...mockAgent, hasDirectProjectConfigurationsInGroup: true },
            canEnable: true,
          },
          provide: groupProvide,
        });
      });

      it('renders the replace primary action with danger variant', () => {
        expect(findModal().props('actionPrimary').text).toBe('Replace and enable for all projects');
        expect(findModal().props('actionPrimary').attributes.variant).toBe('danger');
      });

      it('renders the group enablement disclaimer', () => {
        expect(findGroupEnablementDisclaimer().text()).toContain('Group enablement');
        expect(findGroupEnablementDisclaimer().text()).toContain(
          'This agent is already enabled in one or more projects in this group. If you enable it for all projects, the project configuration for the agent will be deleted and the group configuration will be used instead.',
        );
      });
    });

    it('does not render the flow disclaimer for agents', () => {
      createWrapper({ props: { item: mockAgent, canEnable: true }, provide: groupProvide });

      expect(findFlowDisclaimer().exists()).toBe(false);
    });

    it('submits the group as target, without requiring a project', () => {
      createWrapper({ props: { item: mockAgent, canEnable: true }, provide: groupProvide });

      findForm().vm.$emit('submit', { preventDefault: noop });

      expect(wrapper.emitted('submit')[0][0]).toStrictEqual({
        target: { groupId: 'gid://gitlab/Group/7' },
      });
    });

    it('submits the group as target with the flow trigger types', () => {
      createWrapper({ props: { item: mockFlow, canEnable: true }, provide: groupProvide });

      findForm().vm.$emit('submit', { preventDefault: noop });

      expect(wrapper.emitted('submit')[0][0]).toStrictEqual({
        target: { groupId: 'gid://gitlab/Group/7' },
        triggerTypes,
      });
    });

    it('does not submit when trigger conditions are invalid', async () => {
      createWrapper({ props: { item: mockFlow, canEnable: true }, provide: groupProvide });

      await findTriggers().vm.$emit('update:filter-valid', false);
      findForm().vm.$emit('submit', { preventDefault: noop });

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    describe.each`
      item         | itemType   | editPath
      ${mockAgent} | ${'agent'} | ${'/gitlab-org/test-project/-/automate/agents/1/edit'}
      ${mockFlow}  | ${'flow'}  | ${'/gitlab-org/test-project/-/automate/flows/4/edit'}
    `('when the $itemType is private', ({ item, itemType, editPath }) => {
      beforeEach(() => {
        createWrapper({
          props: { item: { ...item, visibility: VISIBILITY_LEVEL_PRIVATE }, canEnable: true },
          provide: groupProvide,
        });
      });

      it('renders the private title', () => {
        expect(findModal().props('title')).toBe(`This ${itemType} is private`);
      });

      it('renders the private messages', () => {
        expect(wrapper.findByTestId('group-private-message').text()).toBe(
          `${item.name} is private and can't be shared with other projects.`,
        );
        expect(wrapper.findByTestId('group-private-instructions').text()).toBe(
          'To enable it for all projects in the group, change its visibility setting to Restricted or Public in Group / Project 1.',
        );
      });

      it('renders a primary action linking to the item edit page, without cancel action', () => {
        expect(findModal().props('actionPrimary')).toStrictEqual({
          text: `Go to ${itemType} settings`,
          attributes: { variant: 'confirm', href: editPath },
        });
        expect(findModal().props('actionCancel')).toBe(null);
      });

      it('does not render the form', () => {
        expect(findForm().exists()).toBe(false);
        expect(findPrivateAlert().exists()).toBe(false);
      });
    });
  });

  describe('when the modal emits the hidden event', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('emits the hide event', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('hide')).toHaveLength(1);
    });

    it('resets form state', async () => {
      await findProjectMultiSelect().vm.$emit('input', ['gid://gitlab/Project/1']);
      await findProjectMultiSelect().vm.$emit('error', 'Some error');

      findModal().vm.$emit('hidden');
      await nextTick();

      expect(wrapper.vm.projectIds).toStrictEqual([]);
      expect(wrapper.vm.error).toBe(null);
      expect(wrapper.vm.isDirty).toBe(false);
    });
  });

  describe('when user does not have permission to enable a private item', () => {
    beforeEach(() => {
      createWrapper({
        props: {
          item: {
            ...mockFlow,
            project: mockProjectWithGroupExtended,
            visibility: VISIBILITY_LEVEL_PRIVATE,
          },
          canEnable: false,
        },
      });
    });

    it('renders project name instead of dropdown', () => {
      expect(findProjectName().text()).toBe(mockProjectWithGroupExtended.nameWithNamespace);
      expect(findProjectDropdown().exists()).toBe(false);
    });
  });

  describe('when user has permission to enable a private item', () => {
    beforeEach(() => {
      createWrapper({
        props: {
          item: {
            ...mockFlow,
            project: mockProjectWithGroupExtended,
            visibility: VISIBILITY_LEVEL_PRIVATE,
          },
          canEnable: true,
        },
      });
    });

    it('renders project name instead of dropdown', () => {
      expect(findProjectName().text()).toBe(mockProjectWithGroupExtended.nameWithNamespace);
      expect(findProjectDropdown().exists()).toBe(false);
    });
  });

  describe('when user has permission to enable a public item', () => {
    beforeEach(() => {
      createWrapper({
        props: {
          item: { ...mockFlow, project: mockProjectWithGroupExtended },
          canEnable: true,
        },
      });
    });

    it('renders project multi select', () => {
      expect(findProjectName().exists()).toBe(false);
      expect(findProjectMultiSelect().exists()).toBe(true);
    });

    describe('trigger conditions', () => {
      it('renders the trigger conditions panel', () => {
        expect(findTriggers().exists()).toBe(true);
      });

      describe('goal support', () => {
        const createWithGoalFlag = (acceptsTriggerGoal) =>
          createWrapper({
            props: {
              item: { ...mockFlow, project: mockProjectWithGroupExtended, acceptsTriggerGoal },
              canEnable: true,
            },
            provide: { glFeatures: { aiFlowTriggerGoals: true } },
          });

        it('is off when the feature flag is off', () => {
          createWrapper({
            props: {
              item: {
                ...mockFlow,
                project: mockProjectWithGroupExtended,
                acceptsTriggerGoal: true,
              },
              canEnable: true,
            },
          });

          expect(findTriggers().props('goalSupported')).toBe(false);
        });

        it('is on for a flow that accepts a trigger goal', () => {
          createWithGoalFlag(true);

          expect(findTriggers().props('goalSupported')).toBe(true);
          expect(findTriggers().props('goalHelpVisible')).toBe(true);
        });

        it('is off for a flow that refuses a trigger goal', () => {
          createWithGoalFlag(false);

          expect(findTriggers().props('goalSupported')).toBe(false);
        });
      });

      describe('schedule support', () => {
        it('is on for a supported flow', () => {
          expect(findTriggers().props('scheduleSupported')).toBe(true);
        });

        it('is off for an external agent, which cannot hold the scheduled event type', () => {
          createWrapper({
            props: {
              item: {
                ...mockFlow,
                itemType: AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
                project: mockProjectWithGroupExtended,
              },
              canEnable: true,
            },
          });

          expect(findTriggers().props('scheduleSupported')).toBe(false);
        });
      });

      it('pre-selects only the default trigger types', () => {
        expect(findTriggers().props('eventTypes')).toStrictEqual([
          'mention',
          'assign',
          'assign_reviewer',
        ]);
        expect(findTriggers().props('eventTypes')).not.toContain('merge_request_ready');
        expect(findTriggers().props('eventTypes')).not.toContain('pipeline_hooks');
      });
    });

    describe('when submitting', () => {
      beforeEach(() => {
        return findProjectMultiSelect().vm.$emit('input', ['gid://gitlab/Project/1']);
      });

      describe('with the default trigger types', () => {
        it('emits the trigger types and omits an empty trigger filter', async () => {
          const projectIds = ['gid://gitlab/Project/1', 'gid://gitlab/Project/2'];

          await findProjectMultiSelect().vm.$emit('input', projectIds);
          findForm().vm.$emit('submit', { preventDefault: noop });

          expect(wrapper.emitted('submit')[0][0]).toStrictEqual({
            target: projectIds,
            triggerTypes,
          });
        });
      });

      describe('with configured trigger goals', () => {
        it('forwards the goals emitted by the panel', async () => {
          await findTriggers().vm.$emit('update:goals', { mention: 'Summarise the thread.' });
          findForm().vm.$emit('submit', { preventDefault: noop });

          expect(wrapper.emitted('submit')[0][0].triggerGoals).toEqual({
            mention: 'Summarise the thread.',
          });
        });

        it('omits the key when no goal is set', () => {
          findForm().vm.$emit('submit', { preventDefault: noop });

          expect(wrapper.emitted('submit')[0][0]).not.toHaveProperty('triggerGoals');
        });

        // goal_keys_match_event_types refuses a goal for an event type the trigger lacks.
        it('copies the goal onto every event type a folded card splits into', async () => {
          await findTriggers().vm.$emit('update:event-types', [...triggerTypes, 'merge_request']);
          await findTriggers().vm.$emit('update:filter', {
            merge_request: {
              rules: [{ field: 'action', operator: 'in', value: ['ready', 'code_conflict'] }],
            },
          });
          await findTriggers().vm.$emit('update:goals', { merge_request: 'Summarise the diff.' });
          findForm().vm.$emit('submit', { preventDefault: noop });

          expect(wrapper.emitted('submit')[0][0].triggerGoals).toEqual({
            merge_request_ready: 'Summarise the diff.',
            merge_request_code_conflict: 'Summarise the diff.',
          });
        });
      });

      describe('with a configured trigger filter', () => {
        it('forwards the trigger filter emitted by the panel', async () => {
          const triggerFilter = {
            pipeline_hooks: {
              rules: [{ field: 'object_attributes.status', operator: 'in', value: ['failed'] }],
            },
          };

          await findTriggers().vm.$emit('update:filter', triggerFilter);
          findForm().vm.$emit('submit', { preventDefault: noop });

          expect(wrapper.emitted('submit')[0][0].triggerFilter).toEqual(triggerFilter);
        });
      });

      describe('with folded merge_request actions', () => {
        it('splits them back into their own event types', async () => {
          await findTriggers().vm.$emit('update:event-types', [...triggerTypes, 'merge_request']);
          await findTriggers().vm.$emit('update:filter', {
            merge_request: {
              rules: [
                { field: 'action', operator: 'in', value: ['ready', 'approved', 'code_conflict'] },
              ],
            },
          });
          findForm().vm.$emit('submit', { preventDefault: noop });

          const emitted = wrapper.emitted('submit')[0][0];
          expect(emitted.triggerTypes).toStrictEqual([
            ...triggerTypes,
            'merge_request',
            'merge_request_code_conflict',
            'merge_request_ready',
          ]);
          expect(emitted.triggerFilter).toEqual({
            merge_request: {
              rules: [{ field: 'action', operator: 'in', value: ['approved'] }],
            },
          });
        });

        it('drops merge_request when only foldable actions are selected', async () => {
          await findTriggers().vm.$emit('update:event-types', [...triggerTypes, 'merge_request']);
          await findTriggers().vm.$emit('update:filter', {
            merge_request: {
              rules: [{ field: 'action', operator: 'in', value: ['ready', 'code_conflict'] }],
            },
          });
          findForm().vm.$emit('submit', { preventDefault: noop });

          const emitted = wrapper.emitted('submit')[0][0];
          expect(emitted.triggerTypes).toStrictEqual([
            ...triggerTypes,
            'merge_request_code_conflict',
            'merge_request_ready',
          ]);
          expect(emitted.triggerTypes).not.toContain('merge_request');
          expect(emitted.triggerFilter).toBeUndefined();
        });
      });

      describe('when the conditions panel reports its configuration is invalid', () => {
        beforeEach(() => {
          return findTriggers().vm.$emit('update:filter-valid', false);
        });

        it('does not submit', async () => {
          findForm().vm.$emit('submit', { preventDefault: noop });
          await nextTick();

          expect(wrapper.emitted('submit')).toBeUndefined();
        });

        it('passes show-errors to the panel once the user attempts to submit', async () => {
          expect(findTriggers().props('showErrors')).toBe(false);

          findForm().vm.$emit('submit', { preventDefault: noop });
          await nextTick();

          expect(findTriggers().props('showErrors')).toBe(true);
        });
      });
    });
  });

  describe('when user has permission to enable a public agent', () => {
    beforeEach(() => {
      createWrapper({
        props: {
          item: { ...mockAgent, project: mockProjectWithGroupExtended },
          canEnable: true,
        },
      });
    });

    it('does not render trigger selection for agents', () => {
      expect(findTriggers().exists()).toBe(false);
    });
  });

  describe('when user does not have permission to enable a public flow', () => {
    beforeEach(() => {
      createWrapper({
        props: {
          item: { ...mockFlow, project: mockProjectWithGroupExtended },
          canEnable: false,
        },
      });
    });

    it('does not render trigger selection', () => {
      expect(findTriggers().exists()).toBe(false);
    });
  });

  describe('when item is private but project is null (race condition)', () => {
    const privateItemWithoutProject = {
      ...mockFlow,
      visibility: VISIBILITY_LEVEL_PRIVATE,
      project: null,
    };
    const privateItemWithProject = {
      ...mockFlow,
      visibility: VISIBILITY_LEVEL_PRIVATE,
      project: mockProjectWithGroupExtended,
    };

    beforeEach(() => {
      createWrapper({
        props: {
          item: privateItemWithoutProject,
        },
      });
    });

    it('does not crash when rendering', () => {
      expect(findModal().exists()).toBe(true);
    });

    it('does not render project name section', () => {
      expect(findProjectName().exists()).toBe(false);
    });

    it('does not render error alert', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });

    it('does not render private alert during race window', () => {
      expect(findPrivateAlert().exists()).toBe(false);
    });

    describe('when project data arrives after mount (prop update)', () => {
      beforeEach(async () => {
        await wrapper.setProps({ item: privateItemWithProject });
      });

      it('renders the static project name once project data is available', () => {
        expect(findProjectName().text()).toBe(mockProjectWithGroupExtended.nameWithNamespace);
        expect(findProjectDropdown().exists()).toBe(false);
      });

      it('renders private alert once project data is available', () => {
        expect(findPrivateAlert().exists()).toBe(true);
      });

      it('submits with the resolved project id from the updated item', async () => {
        findForm().vm.$emit('submit', { preventDefault: noop });
        await nextTick();

        expect(wrapper.emitted('submit')).toHaveLength(1);
        expect(wrapper.emitted('submit')[0][0]).toStrictEqual({
          target: { projectId: mockProjectWithGroupExtended.id },
          triggerTypes,
        });
      });

      it('reports the race condition to Sentry so occurrences can be tracked', () => {
        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
        expect(Sentry.captureException).toHaveBeenCalledWith(
          expect.objectContaining({
            message: expect.stringContaining('project data arrived after mount'),
          }),
          expect.objectContaining({
            level: 'info',
            tags: expect.objectContaining({
              race_type: 'ai_catalog_project_field',
              item_type: privateItemWithProject.itemType,
            }),
            extra: expect.objectContaining({
              item_id: privateItemWithProject.id,
              time_to_resolve_ms: expect.any(Number),
            }),
          }),
        );

        const [, context] = Sentry.captureException.mock.calls[0];
        expect(context.extra.time_to_resolve_ms).toBeGreaterThanOrEqual(0);
      });
    });
  });

  describe('with duoAutomations', () => {
    const projectProvide = { isGlobalNamespace: false, isProjectNamespace: true, projectId: '1' };
    const findGoal = () => wrapper.findComponentByTestId('item-consumer-goal');

    const createAutomationWrapper = ({ provide = projectProvide, glFeatures = {} } = {}) =>
      createWrapper({
        props: { item: { ...mockFlow, acceptsTriggerGoal: true }, canEnable: true },
        provide: {
          ...provide,
          glFeatures: { duoAutomations: true, aiFlowTriggerGoals: true, ...glFeatures },
        },
      });

    it('shows one instructions field and compact conditions without their own goals', () => {
      createAutomationWrapper();

      expect(findGoal().exists()).toBe(true);
      expect(findTriggers().props()).toMatchObject({ compact: true, goalSupported: false });
    });

    it('applies the instructions to every trigger type', async () => {
      createAutomationWrapper();

      await findGoal().vm.$emit('input', ' Fix it ');
      findForm().vm.$emit('submit', { preventDefault: noop });

      expect(wrapper.emitted('submit')[0][0].triggerGoals).toEqual(
        Object.fromEntries(triggerTypes.map((type) => [type, 'Fix it'])),
      );
    });

    it.each`
      context                | provide           | glFeatures
      ${'outside a project'} | ${{}}             | ${{}}
      ${'with the flag off'} | ${projectProvide} | ${{ duoAutomations: false }}
    `('keeps goals on each condition $context', ({ provide, glFeatures }) => {
      createAutomationWrapper({ provide, glFeatures });

      expect(findGoal().exists()).toBe(false);
      expect(findTriggers().props()).toMatchObject({ compact: false, goalSupported: true });
    });
  });
});
