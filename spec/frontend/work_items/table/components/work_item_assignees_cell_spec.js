import { GlAvatarLink, GlAvatarsInline, GlCollapsibleListbox, GlTruncate } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkItemAssigneesCell from '~/work_items/table/components/work_item_assignees_cell.vue';
import updateWorkItemMutation from '~/work_items/graphql/update_work_item.mutation.graphql';
import usersSearchQuery from '~/graphql_shared/queries/workspace_autocomplete_users.query.graphql';
import workItemEditMetadataQuery from '~/work_items/table/graphql/work_item_edit_metadata.query.graphql';
import { buildWorkItemNode, buildAssigneesWidget, mockAssignees } from '../../board/mock_data';
import { updateWorkItemMutationResponse } from '../../mock_data';

Vue.use(VueApollo);

describe('WorkItemAssigneesCell', () => {
  let wrapper;

  const [alice, bob] = mockAssignees;
  const toAutocompletedUser = (user) => ({
    ...user,
    __typename: 'AutocompletedUser',
    compositeIdentityEnforced: false,
    status: { availability: 'NOT_SET' },
    duoStatus: { disabled: false, disabledReason: null, flowTriggerEvents: [] },
  });
  const carol = toAutocompletedUser({
    id: 'gid://gitlab/User/3',
    avatarUrl: '/avatar/3.png',
    name: 'Carol',
    username: 'carol',
    webUrl: '/carol',
    webPath: '/carol',
  });
  const agent = {
    ...toAutocompletedUser({
      id: 'gid://gitlab/User/4',
      avatarUrl: '/avatar/4.png',
      name: 'Agent',
      username: 'agent',
      webUrl: '/agent',
      webPath: '/agent',
    }),
    compositeIdentityEnforced: true,
  };

  const item = buildWorkItemNode(1, { widgets: [buildAssigneesWidget([alice, bob])] });
  const itemWithOneAssignee = buildWorkItemNode(2, { widgets: [buildAssigneesWidget([alice])] });
  const itemWithoutAssignees = buildWorkItemNode(3, { widgets: [buildAssigneesWidget([])] });

  const users = [toAutocompletedUser(alice), toAutocompletedUser(bob), carol, agent];
  const projectUsersResponse = {
    data: { namespace: { __typename: 'Project', id: 'gid://gitlab/Project/1', users } },
  };
  const groupUsersResponse = {
    data: {
      groupNamespace: { __typename: 'Group', id: 'gid://gitlab/Group/1', users },
      namespace: null,
    },
  };

  const editMetadataResponse = (allowsMultipleAssignees) => ({
    data: {
      workItem: {
        __typename: 'WorkItem',
        id: item.id,
        widgets: [
          { __typename: 'WorkItemWidgetAssignees', type: 'ASSIGNEES', allowsMultipleAssignees },
        ],
      },
    },
  });

  let defaultMutationHandler;
  let usersQueryHandler;
  let editMetadataQueryHandler;
  let mockToast;

  beforeEach(() => {
    defaultMutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
    usersQueryHandler = jest.fn().mockResolvedValue(projectUsersResponse);
    editMetadataQueryHandler = jest.fn().mockResolvedValue(editMetadataResponse(true));
    mockToast = { show: jest.fn() };
  });

  const findCell = () => wrapper.findByTestId('cell-assignees');
  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findAvatars = () => wrapper.findComponent(GlAvatarsInline);
  const findAvatarLinks = () => wrapper.findAllComponents(GlAvatarLink);
  const findBadge = () => wrapper.findByTestId('collapsed-avatars-badge');
  const findNameLink = () => wrapper.findByTestId('assignee-name-link');

  const createComponent = ({
    props = {},
    provide = {},
    mutationHandler = defaultMutationHandler,
  } = {}) => {
    const apolloProvider = createMockApollo([
      [updateWorkItemMutation, mutationHandler],
      [usersSearchQuery, usersQueryHandler],
      [workItemEditMetadataQuery, editMetadataQueryHandler],
    ]);

    wrapper = mountExtended(WorkItemAssigneesCell, {
      apolloProvider,
      propsData: {
        item,
        ...props,
      },
      provide: {
        glFeatures: { workItemFeaturesField: false },
        isGroup: false,
        rootPageFullPath: 'group/project',
        ...provide,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      mocks: {
        $toast: mockToast,
      },
    });
  };

  const startEditing = async () => {
    await findCell().trigger('click');
    findListbox().vm.$emit('shown');
    await waitForPromises();
  };

  const selectAndClose = async (value) => {
    findListbox().vm.$emit('select', value);
    await nextTick();
    findListbox().vm.$emit('hidden');
    await waitForPromises();
  };

  describe('display mode', () => {
    describe('when the item has several assignees', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders the assignee avatars', () => {
        expect(findAvatars().props('avatars')).toEqual([alice, bob]);
      });

      it('links each avatar to the user with their name in a tooltip', () => {
        const links = findAvatarLinks();

        expect(links.wrappers.map((link) => link.attributes('href'))).toEqual(['/alice', '/bob']);
        expect(links.wrappers.map((link) => link.attributes('title'))).toEqual(['Alice', 'Bob']);
        expect(getBinding(links.at(0).element, 'gl-tooltip')).not.toBeUndefined();
      });

      it('does not render a name', () => {
        expect(findNameLink().exists()).toBe(false);
      });

      it('does not render a badge', () => {
        expect(findBadge().exists()).toBe(false);
      });

      it('does not show the listbox', () => {
        expect(findListbox().exists()).toBe(false);
      });

      it('does not fetch users', () => {
        expect(usersQueryHandler).not.toHaveBeenCalled();
      });

      it('does not fetch the edit metadata', () => {
        expect(editMetadataQueryHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the item has more than three assignees', () => {
      const dave = { ...alice, id: 'gid://gitlab/User/5', name: 'Dave', webPath: '/dave' };
      const erin = { ...alice, id: 'gid://gitlab/User/6', name: 'Erin', webPath: '/erin' };

      beforeEach(() => {
        createComponent({
          props: {
            item: buildWorkItemNode(5, {
              widgets: [buildAssigneesWidget([alice, bob, carol, dave, erin])],
            }),
          },
        });
      });

      it('shows three stacked avatars', () => {
        expect(findAvatars().props()).toMatchObject({ maxVisible: 3, collapsed: true });
        expect(findAvatarLinks()).toHaveLength(3);
      });

      it('shows a badge with the number of hidden assignees', () => {
        expect(findBadge().text()).toBe('+2');
        expect(wrapper.findByTestId('badge-sr-only-text').text()).toBe('2 additional assignees');
      });

      it('names the hidden assignees in the badge tooltip', () => {
        expect(findAvatars().props('badgeTooltipProp')).toBe('name');
      });
    });

    describe('when the item has a single assignee', () => {
      beforeEach(() => {
        createComponent({ props: { item: itemWithOneAssignee } });
      });

      it('renders the avatar and the assignee name linked to the user', () => {
        expect(findAvatars().props('avatars')).toEqual([alice]);
        expect(findNameLink().attributes('href')).toBe(alice.webPath);
        expect(findNameLink().findComponent(GlTruncate).props('text')).toBe(alice.name);
      });

      it('does not enter edit mode when clicking the name', async () => {
        // jsdom does not implement navigation
        findNameLink().element.addEventListener('click', (event) => event.preventDefault());
        await findNameLink().trigger('click');

        expect(findListbox().exists()).toBe(false);
      });
    });

    describe('when the item has no assignees', () => {
      beforeEach(() => {
        createComponent({ props: { item: itemWithoutAssignees } });
      });

      it('renders no avatars', () => {
        expect(findAvatars().exists()).toBe(false);
      });

      it('can still enter edit mode', async () => {
        await findCell().trigger('click');

        expect(findListbox().exists()).toBe(true);
      });
    });
  });

  describe('when clicking the cell', () => {
    beforeEach(async () => {
      createComponent();
      await startEditing();
    });

    it('shows the listbox with multi-select and the current assignees selected', () => {
      expect(findListbox().props()).toMatchObject({
        multiple: true,
        searchable: true,
        headerText: 'Select assignees',
        resetButtonLabel: 'Clear',
        selected: [alice.id, bob.id],
      });
    });

    it('fetches the edit metadata for the work item', () => {
      expect(editMetadataQueryHandler).toHaveBeenCalledWith({ id: item.id });
    });

    it('fetches users for the project', () => {
      expect(usersQueryHandler).toHaveBeenCalledWith({
        fullPath: 'group/project',
        search: '',
        isProject: true,
      });
    });

    it('groups the current assignees first', () => {
      const items = findListbox().props('items');

      expect(items.map(({ text, textSrOnly }) => ({ text, textSrOnly }))).toEqual([
        { text: 'Selected', textSrOnly: undefined },
        { text: 'All users', textSrOnly: true },
      ]);
      expect(items[0].options.map(({ value }) => value)).toEqual([alice.id, bob.id]);
      expect(items[1].options.map(({ value }) => value)).toEqual([carol.id, agent.id]);
    });
  });

  describe('when the table belongs to a group', () => {
    beforeEach(async () => {
      usersQueryHandler.mockResolvedValue(groupUsersResponse);
      createComponent({ provide: { isGroup: true } });
      await startEditing();
    });

    it('fetches users for the group', () => {
      expect(usersQueryHandler).toHaveBeenCalledWith({
        fullPath: 'group/project',
        search: '',
        isProject: false,
      });
      expect(findListbox().props('items')[1].options).toHaveLength(2);
    });
  });

  describe('when the work item allows one assignee', () => {
    beforeEach(async () => {
      editMetadataQueryHandler.mockResolvedValue(editMetadataResponse(false));
      createComponent({ props: { item: itemWithOneAssignee } });
      await startEditing();
    });

    it('shows a single-select listbox', () => {
      expect(findListbox().props()).toMatchObject({
        multiple: false,
        headerText: 'Select assignee',
        selected: alice.id,
      });
    });

    it('replaces the assignee', async () => {
      await selectAndClose(carol.id);

      expect(defaultMutationHandler).toHaveBeenCalledWith({
        input: { id: itemWithOneAssignee.id, assigneesWidget: { assigneeIds: [carol.id] } },
        useWorkItemFeatures: false,
      });
    });
  });

  describe('when fetching the edit metadata fails', () => {
    beforeEach(async () => {
      editMetadataQueryHandler.mockRejectedValue(new Error('Network error'));
      createComponent();
      await startEditing();
    });

    it('shows a multi-select listbox', () => {
      expect(findListbox().props('multiple')).toBe(true);
    });
  });

  describe('when an agent was assigned but can no longer be assigned', () => {
    // For example, its assign trigger was removed after it was assigned. List rows only include
    // basic user fields, so the row does not say this user is an agent.
    const agentFromRow = {
      __typename: 'UserCore',
      id: agent.id,
      avatarUrl: agent.avatarUrl,
      name: agent.name,
      username: agent.username,
      webUrl: agent.webUrl,
      webPath: agent.webPath,
    };
    const itemWithAgent = buildWorkItemNode(5, {
      widgets: [buildAssigneesWidget([alice, agentFromRow])],
    });

    beforeEach(async () => {
      createComponent({ props: { item: itemWithAgent } });
      await startEditing();
    });

    it('shows the agent badge in the selected group', () => {
      expect(wrapper.findAllByTestId('sidebar-participant-agent-badge')).toHaveLength(1);
    });

    it('lets the agent be unassigned but not assigned again', async () => {
      findListbox().vm.$emit('select', [alice.id]);
      await nextTick();
      findListbox().vm.$emit('select', [alice.id, agent.id]);
      await nextTick();

      expect(findListbox().props('selected')).toEqual([alice.id]);
    });
  });

  describe('when saving', () => {
    beforeEach(async () => {
      createComponent();
      await startEditing();
    });

    it('sends the full list of assignees', async () => {
      await selectAndClose([alice.id, bob.id, carol.id]);

      expect(defaultMutationHandler).toHaveBeenCalledWith({
        input: { id: item.id, assigneesWidget: { assigneeIds: [alice.id, bob.id, carol.id] } },
        useWorkItemFeatures: false,
      });
      expect(findListbox().exists()).toBe(false);
    });

    it('unassigns everyone when the selection is cleared', async () => {
      findListbox().vm.$emit('reset');
      await nextTick();
      findListbox().vm.$emit('hidden');
      await waitForPromises();

      expect(defaultMutationHandler).toHaveBeenCalledWith({
        input: { id: item.id, assigneesWidget: { assigneeIds: [] } },
        useWorkItemFeatures: false,
      });
    });

    it('does not save when the assignees are unchanged', async () => {
      await selectAndClose([bob.id, alice.id]);

      expect(defaultMutationHandler).not.toHaveBeenCalled();
      expect(findListbox().exists()).toBe(false);
    });

    it('does not select a user who cannot be assigned', async () => {
      findListbox().vm.$emit('select', [alice.id, bob.id, agent.id]);
      await nextTick();

      expect(findListbox().props('selected')).toEqual([alice.id, bob.id]);
    });
  });

  describe.each`
    description                 | mutationHandler
    ${'returns errors'}         | ${jest.fn().mockResolvedValue({ data: { workItemUpdate: { workItem: null, errors: ['Error'] } } })}
    ${'fails with a exception'} | ${jest.fn().mockRejectedValue(new Error('Network error'))}
  `('when the mutation $description', ({ mutationHandler }) => {
    beforeEach(async () => {
      createComponent({ mutationHandler });
      await startEditing();
      await selectAndClose([alice.id]);
    });

    it('shows a toast and exits edit mode', () => {
      expect(mockToast.show).toHaveBeenCalledWith(
        'Something went wrong while updating the assignees.',
      );
      expect(findListbox().exists()).toBe(false);
    });
  });

  describe('when fetching users fails', () => {
    beforeEach(async () => {
      usersQueryHandler.mockRejectedValue(new Error('Network error'));
      createComponent();
      await startEditing();
    });

    it('shows a toast', () => {
      expect(mockToast.show).toHaveBeenCalledWith('Something went wrong when fetching users.');
    });
  });
});
