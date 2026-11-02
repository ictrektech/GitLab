import { GlButton, GlEmptyState, GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import BoardView from '~/work_items/board/board_view.vue';
import BoardColumn from '~/work_items/board/components/board_column.vue';
import BoardColumnCount from '~/work_items/board/components/board_column_count.vue';
import DraggableCompat from '~/lib/utils/vue3compat/draggable_compat.vue';
import CreateWorkItemModal from '~/work_items/components/create_work_item_modal.vue';
import { updateDraft } from '~/lib/utils/autosave';
import getBoardNamespaceStatusesQuery from 'ee_else_ce/work_items/board/graphql/get_namespace_statuses.query.graphql';
import getBoardWorkItemsQuery from 'ee_else_ce/work_items/board/graphql/get_board_work_items.query.graphql';
import getWorkItemsCountOnlyQuery from 'ee_else_ce/work_items/list/graphql/get_work_items_count_only.query.graphql';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import updateBoardWorkItemMutation from '~/work_items/board/graphql/update_board_work_item.mutation.graphql';
import { resolveInheritedWidgetsDraft } from '~/work_items/board/filter_inheritance';
import { statusStrategy } from 'ee/work_items/board/grouping/status_strategy';
import { boardColumnQueryVariables, boardColumnCountVariables } from '~/work_items/board/utils';
import { RELATIVE_POSITION_ASC } from '~/work_items/list/constants';
import { MOVE_IN_PROGRESS_INDICATOR_DELAY } from '~/work_items/board/constants';
import { FOCUS_NEXT, FOCUS_PREVIOUS } from '~/work_items/board/keyboard_navigation';
import {
  addWorkItemToColumn,
  adjustWorkItemCountInColumn,
  readWorkItemFromColumn,
  readWorkItemsFromColumn,
  removeWorkItemFromColumn,
} from '~/work_items/board/graphql/cache_updates';
import {
  buildStatus,
  buildStatusWidget,
  buildNamespaceStatusesResponse,
  buildBoardWorkItemsResponse,
  buildBoardWorkItemsCountResponse,
  buildWorkItemNode,
  buildWorkItemTypesResponse,
} from 'jest/work_items/board/mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/work_items/board/graphql/cache_updates');
jest.mock('~/lib/utils/autosave');
jest.mock('~/work_items/board/filter_inheritance');

Vue.use(VueApollo);

describe('BoardView', () => {
  let wrapper;
  let toast;
  let apolloProvider;

  const statusesQueryHandler = jest.fn();
  const workItemTypesQueryHandler = jest.fn();
  const updateMutationHandler = jest.fn();
  const boardWorkItemsQueryHandler = jest.fn();
  const countQueryHandler = jest.fn();

  const defaultStatuses = [
    buildStatus(1, 'To do', 'to_do'),
    buildStatus(2, 'In progress', 'in_progress'),
    buildStatus(3, 'Done', 'done'),
  ];
  // The board always sorts manually, so position gets persisted below.
  const queryVariables = { state: 'opened', sort: RELATIVE_POSITION_ASC };

  const columnVariables = (value) =>
    boardColumnQueryVariables({
      rootPageFullPath: 'full/path',
      baseQueryVariables: queryVariables,
      groupFilter: { status: { name: value.name } },
    });

  const columnCountVariables = (value) =>
    boardColumnCountVariables({
      rootPageFullPath: 'full/path',
      baseQueryVariables: queryVariables,
      groupFilter: { status: { name: value.name } },
    });

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findBoardColumns = () => wrapper.findAllComponents(BoardColumn);
  const findColumnDraggable = () => wrapper.findComponent(DraggableCompat);
  const columnNames = () => findBoardColumns().wrappers.map((column) => column.props('value').name);
  const findCreateModal = () => wrapper.findComponent(CreateWorkItemModal);
  const findAllGroupsHiddenPrompt = () => wrapper.findComponentByTestId('all-groups-hidden-prompt');
  const findDisplayButton = () => findAllGroupsHiddenPrompt().findComponent(GlButton);
  const findAnnouncement = () => wrapper.findByTestId('board-announcement');
  const findColumnActionsToggle = (index) =>
    findBoardColumns().at(index).find('[data-testid="column-actions-menu"] button').element;
  const BoardColumnWithActionsToggle = stubComponent(BoardColumn, {
    template:
      '<div><div data-testid="column-actions-menu"><button>Column actions</button></div></div>',
  });

  const createComponent = ({
    props = {},
    visibleGroups = null,
    visibleGroupsLoaded = true,
    stubs = {},
    slots = {},
    attachTo,
  } = {}) => {
    toast = { show: jest.fn().mockReturnValue({ id: 'gl-toast-0' }) };
    apolloProvider = createMockApollo([
      [getBoardNamespaceStatusesQuery, statusesQueryHandler],
      [getBoardWorkItemsQuery, boardWorkItemsQueryHandler],
      [namespaceWorkItemTypesQuery, workItemTypesQueryHandler],
      [updateBoardWorkItemMutation, updateMutationHandler],
      [getWorkItemsCountOnlyQuery, countQueryHandler],
    ]);

    wrapper = shallowMountExtended(BoardView, {
      apolloProvider,
      mocks: { $toast: toast },
      propsData: {
        rootPageFullPath: 'full/path',
        queryVariables,
        // `true` by default so the statuses query fires immediately, matching
        // the common case in tests below that aren't specifically about loading.
        visibleGroups,
        visibleGroupsLoaded,
        ...props,
      },
      stubs,
      slots,
      attachTo,
    });
  };

  beforeEach(() => {
    // Mirrors the backend's `ids` filter (see StatusesResolver) so tests that
    // scope visibleGroups get realistic, filtered responses back.
    statusesQueryHandler.mockImplementation(({ ids } = {}) =>
      Promise.resolve(
        buildNamespaceStatusesResponse(
          ids ? defaultStatuses.filter((status) => ids.includes(status.id)) : defaultStatuses,
        ),
      ),
    );
    workItemTypesQueryHandler.mockResolvedValue(buildWorkItemTypesResponse());
    boardWorkItemsQueryHandler.mockResolvedValue(
      buildBoardWorkItemsResponse([buildWorkItemNode(9)]),
    );
    // BoardColumnCount is stubbed by shallowMountExtended by default, so this
    // never actually fires except in the 'empty groups' tests below, which
    // mount it for real via `stubs: { BoardColumnCount }`.
    countQueryHandler.mockResolvedValue(buildBoardWorkItemsCountResponse(1));
    resolveInheritedWidgetsDraft.mockResolvedValue({});
    readWorkItemsFromColumn.mockReturnValue([]);
    updateMutationHandler.mockResolvedValue({
      data: { workItemUpdate: { workItem: buildWorkItemNode(1), errors: [] } },
    });
  });

  describe('loading state', () => {
    it('renders the loading icon while the query is loading and no values are present', () => {
      createComponent();

      expect(findLoadingIcon().exists()).toBe(true);
      expect(findBoardColumns()).toHaveLength(0);
    });

    it('hides the loading icon once the query resolves', async () => {
      createComponent();
      await waitForPromises();

      expect(findLoadingIcon().exists()).toBe(false);
    });
  });

  describe('announcement live region', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders an empty polite live region before any move', () => {
      expect(findAnnouncement().attributes()).toMatchObject({
        'aria-live': 'polite',
        'aria-atomic': 'true',
        class: 'gl-sr-only',
      });
      expect(findAnnouncement().text()).toBe('');
    });
  });

  describe('board columns', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders one BoardColumn per status node', () => {
      expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
    });

    it('passes value, strategy, rootPageFullPath, and baseQueryVariables to each BoardColumn', () => {
      findBoardColumns().wrappers.forEach((column, index) => {
        expect(column.props()).toMatchObject({
          value: defaultStatuses[index],
          rootPageFullPath: 'full/path',
          baseQueryVariables: queryVariables,
        });
        expect(column.props('strategy').property).toBe('status');
      });
    });

    it('renders no BoardColumns when the query returns no statuses', async () => {
      statusesQueryHandler.mockResolvedValue(buildNamespaceStatusesResponse([]));
      createComponent();
      await waitForPromises();

      expect(findBoardColumns()).toHaveLength(0);
    });

    it('orders the columns by status category', async () => {
      statusesQueryHandler.mockResolvedValue(
        buildNamespaceStatusesResponse([
          buildStatus(1, 'Cancelled', 'canceled'),
          buildStatus(2, 'Done', 'done'),
          buildStatus(3, 'Triage', 'triage'),
          buildStatus(4, 'In progress', 'in_progress'),
          buildStatus(5, 'To do', 'to_do'),
        ]),
      );
      createComponent();
      await waitForPromises();

      expect(findBoardColumns().wrappers.map((column) => column.props('value').name)).toEqual([
        'Triage',
        'To do',
        'In progress',
        'Done',
        'Cancelled',
      ]);
    });
  });

  describe('empty groups', () => {
    const countByStatusName = (counts) =>
      countQueryHandler.mockImplementation(({ status } = {}) =>
        Promise.resolve(buildBoardWorkItemsCountResponse(counts[status?.name] ?? 0)),
      );

    it('shows every column when showEmptyGroups is true (the default), without waiting on counts', async () => {
      countQueryHandler.mockReturnValue(new Promise(() => {}));
      createComponent({ stubs: { BoardColumnCount } });
      await waitForPromises();

      expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
    });

    it('hides columns with no items once their counts resolve', async () => {
      countByStatusName({ 'To do': 0, 'In progress': 2, Done: 0 });
      createComponent({ props: { showEmptyGroups: false }, stubs: { BoardColumnCount } });
      await waitForPromises();

      expect(columnNames()).toEqual(['In progress']);
    });

    it('keeps the loading icon up while counts are still arriving with the toggle off', async () => {
      countQueryHandler.mockReturnValue(new Promise(() => {}));
      createComponent({ props: { showEmptyGroups: false }, stubs: { BoardColumnCount } });
      await waitForPromises();

      expect(findLoadingIcon().exists()).toBe(true);
      expect(findBoardColumns()).toHaveLength(0);
    });

    describe('when every group is empty', () => {
      beforeEach(async () => {
        countByStatusName({ 'To do': 0, 'In progress': 0, Done: 0 });
        createComponent({
          props: { showEmptyGroups: false },
          stubs: {
            BoardColumnCount,
            GlEmptyState: stubComponent(GlEmptyState, { template: RENDER_ALL_SLOTS_TEMPLATE }),
            GlSprintf,
          },
        });
        await waitForPromises();
      });

      it('tells the user all groups are hidden instead of rendering columns', () => {
        expect(findBoardColumns()).toHaveLength(0);
        expect(findLoadingIcon().exists()).toBe(false);
        expect(findAllGroupsHiddenPrompt().find('h2').text()).toBe('All groups are hidden');
        expect(findAllGroupsHiddenPrompt().find('[data-testid="slot-description"]').text()).toBe(
          'Show groups using the Display options.',
        );
        expect(findAllGroupsHiddenPrompt().find('strong').text()).toBe('Display');
      });

      it('emits open-display-settings when the Display action is clicked', () => {
        findDisplayButton().vm.$emit('click');

        expect(wrapper.emitted('open-display-settings')).toEqual([[]]);
      });

      describe('when empty groups are shown again', () => {
        beforeEach(async () => {
          await wrapper.setProps({ showEmptyGroups: true });
        });

        it('renders every column instead of the prompt', () => {
          expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
          expect(findAllGroupsHiddenPrompt().exists()).toBe(false);
        });
      });
    });

    it('passes the resolved count down to each column', async () => {
      countByStatusName({ 'To do': 3, 'In progress': 0, Done: 7 });
      createComponent({ stubs: { BoardColumnCount } });
      await waitForPromises();

      expect(findBoardColumns().wrappers.map((column) => column.props('count'))).toEqual([3, 0, 7]);
    });

    it('drops the loading icon and keeps the column visible when a count request fails', async () => {
      countQueryHandler.mockImplementation(({ status } = {}) =>
        status?.name === 'To do'
          ? Promise.reject(new Error('boom'))
          : Promise.resolve(buildBoardWorkItemsCountResponse(0)),
      );
      createComponent({ props: { showEmptyGroups: false }, stubs: { BoardColumnCount } });
      await waitForPromises();

      expect(findLoadingIcon().exists()).toBe(false);
      expect(columnNames()).toEqual(['To do']);
    });
  });

  describe('when the namespace has no work items', () => {
    const findEmptyState = () => wrapper.findByTestId('board-empty-state');

    const createEmptyBoard = async (props = {}) => {
      createComponent({
        props: { hasWorkItems: false, ...props },
        stubs: { BoardColumnCount },
        slots: { 'empty-state': '<div data-testid="board-empty-state" />' },
      });
      await waitForPromises();
    };

    describe('while hasWorkItems is loading', () => {
      beforeEach(async () => {
        await createEmptyBoard({ hasWorkItemsLoading: true });
      });

      it('shows the loading icon instead of the empty state', () => {
        expect(findLoadingIcon().exists()).toBe(true);
        expect(findEmptyState().exists()).toBe(false);
      });
    });

    describe('once hasWorkItems has loaded', () => {
      beforeEach(async () => {
        await createEmptyBoard();
      });

      it('renders the empty-state slot instead of the columns', () => {
        expect(findEmptyState().exists()).toBe(true);
        expect(findBoardColumns()).toHaveLength(0);
        expect(findLoadingIcon().exists()).toBe(false);
      });
    });

    describe('with empty groups hidden and counts still pending', () => {
      beforeEach(async () => {
        countQueryHandler.mockReturnValue(new Promise(() => {}));
        await createEmptyBoard({ showEmptyGroups: false });
      });

      it('renders the empty-state slot without waiting for the counts', () => {
        expect(findEmptyState().exists()).toBe(true);
        expect(findLoadingIcon().exists()).toBe(false);
      });
    });
  });

  describe('when hasWorkItems refetches on a board that has work items', () => {
    beforeEach(async () => {
      createComponent({ props: { hasWorkItems: true, hasWorkItemsLoading: true } });
      await waitForPromises();
    });

    it('keeps the columns rendered', () => {
      expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
      expect(findLoadingIcon().exists()).toBe(false);
    });
  });

  describe('when filters match nothing in any column', () => {
    const findEmptyState = () => wrapper.findByTestId('board-empty-state');

    const createFilteredBoard = async (props = {}) => {
      createComponent({
        props: { hasActiveFilters: true, showEmptyGroups: false, ...props },
        stubs: { BoardColumnCount },
        slots: { 'empty-state': '<div data-testid="board-empty-state" />' },
      });
      await waitForPromises();
    };

    describe('once every count has loaded with empty groups hidden', () => {
      beforeEach(async () => {
        countQueryHandler.mockResolvedValue(buildBoardWorkItemsCountResponse(0));
        await createFilteredBoard();
      });

      it('renders the empty-state slot instead of a blank board', () => {
        expect(findEmptyState().exists()).toBe(true);
        expect(findBoardColumns()).toHaveLength(0);
        expect(findLoadingIcon().exists()).toBe(false);
      });

      describe('when the filters are cleared', () => {
        beforeEach(async () => {
          countQueryHandler.mockResolvedValue(buildBoardWorkItemsCountResponse(1));
          await wrapper.setProps({
            hasActiveFilters: false,
            queryVariables: { sort: RELATIVE_POSITION_ASC },
          });
          await waitForPromises();
        });

        it('renders the columns again', () => {
          expect(findEmptyState().exists()).toBe(false);
          expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
        });
      });

      describe('when the board then needs group selection', () => {
        beforeEach(async () => {
          await wrapper.setProps({ visibleGroups: [] });
          await waitForPromises();
        });

        it('shows the all groups hidden prompt', () => {
          expect(findAllGroupsHiddenPrompt().exists()).toBe(true);
          expect(findEmptyState().exists()).toBe(false);
        });
      });
    });

    describe('while a column count is still loading', () => {
      beforeEach(async () => {
        countQueryHandler.mockImplementation(({ status } = {}) =>
          status?.name === 'To do'
            ? new Promise(() => {})
            : Promise.resolve(buildBoardWorkItemsCountResponse(0)),
        );
        await createFilteredBoard();
      });

      it('keeps the loading icon up', () => {
        expect(findEmptyState().exists()).toBe(false);
        expect(findLoadingIcon().exists()).toBe(true);
      });
    });

    describe('when one column count failed', () => {
      beforeEach(async () => {
        countQueryHandler.mockImplementation(({ status } = {}) =>
          status?.name === 'To do'
            ? Promise.reject(new Error('boom'))
            : Promise.resolve(buildBoardWorkItemsCountResponse(0)),
        );
        await createFilteredBoard();
      });

      it('keeps that column', () => {
        expect(findEmptyState().exists()).toBe(false);
        expect(columnNames()).toEqual(['To do']);
      });
    });

    describe('with empty groups shown', () => {
      beforeEach(async () => {
        countQueryHandler.mockResolvedValue(buildBoardWorkItemsCountResponse(0));
        await createFilteredBoard({ showEmptyGroups: true });
      });

      it('keeps the columns', () => {
        expect(findEmptyState().exists()).toBe(false);
        expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
      });
    });
  });

  describe('when every count is zero without active filters', () => {
    beforeEach(async () => {
      countQueryHandler.mockResolvedValue(buildBoardWorkItemsCountResponse(0));
      createComponent({
        props: { showEmptyGroups: false },
        stubs: { BoardColumnCount },
        slots: { 'empty-state': '<div data-testid="board-empty-state" />' },
      });
      await waitForPromises();
    });

    it('does not render the empty-state slot', () => {
      expect(wrapper.findByTestId('board-empty-state').exists()).toBe(false);
    });
  });

  describe('creating a work item in a column', () => {
    const toDo = defaultStatuses[0];
    const createdWorkItem = buildWorkItemNode(9);

    const requestCreate = async (status = toDo) => {
      findBoardColumns().at(defaultStatuses.indexOf(status)).vm.$emit('create-item', status);
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent({ props: { canCreateWorkItem: true } });
      await waitForPromises();
    });

    it('resolves the board filters and merges the inherited widgets into the draft', async () => {
      const bug = { __typename: 'Label', id: 'gid://gitlab/Label/1', title: 'bug' };
      resolveInheritedWidgetsDraft.mockResolvedValue({ LABELS: { labels: { nodes: [bug] } } });
      createComponent({
        props: {
          canCreateWorkItem: true,
          queryVariables: { ...queryVariables, labelName: ['bug'], isGroup: false },
        },
      });
      await waitForPromises();

      await requestCreate();

      expect(resolveInheritedWidgetsDraft).toHaveBeenCalledWith(
        expect.objectContaining({
          fullPath: 'full/path',
          isGroup: false,
          filters: expect.objectContaining({ labelName: ['bug'] }),
        }),
      );
      const [, draftJson] = updateDraft.mock.calls[0];
      expect(JSON.parse(draftJson)).toMatchObject({
        STATUS: { status: { name: toDo.name } },
        LABELS: { labels: { nodes: [bug] } },
      });
    });

    it('pre-populates the new item widgets draft with the column grouping', async () => {
      await requestCreate();

      expect(updateDraft).toHaveBeenCalledTimes(1);
      const [, draftJson] = updateDraft.mock.calls[0];
      expect(JSON.parse(draftJson)).toEqual({ STATUS: { status: toDo } });
    });

    it('opens the create modal preselected for the board type and board context', async () => {
      await requestCreate();

      expect(findCreateModal().props()).toMatchObject({
        creationContext: 'board',
        createSource: 'work_item_board',
        hideNamespaceSelector: true,
        suppressCreatedToast: true,
      });
    });

    it('marks the create modal confidential when the board filters by confidential', async () => {
      createComponent({
        props: {
          canCreateWorkItem: true,
          queryVariables: { ...queryVariables, confidential: true },
        },
      });
      await waitForPromises();

      await requestCreate();

      expect(findCreateModal().props('confidential')).toBe(true);
    });

    it('does not mark the create modal confidential without a confidential filter', async () => {
      await requestCreate();

      expect(findCreateModal().props('confidential')).toBe(false);
    });

    it('inserts the created item at the top of its column and updates the count', async () => {
      await requestCreate();

      findCreateModal().vm.$emit('work-item-created', createdWorkItem);
      await waitForPromises();

      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({ variables: columnVariables(toDo), index: 0 }),
      );
      expect(addWorkItemToColumn.mock.calls[0][0].workItem.id).toBe(createdWorkItem.id);
      expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
        expect.objectContaining({ variables: columnCountVariables(toDo), delta: 1 }),
      );
      expect(wrapper.emitted('work-item-created')).toEqual([[createdWorkItem]]);
    });

    describe('while the created item is being fetched', () => {
      let resolveFetch;

      const placeholderColumns = () =>
        findBoardColumns().wrappers.map((column) => column.props('insertingCard'));

      beforeEach(async () => {
        await requestCreate();
        boardWorkItemsQueryHandler.mockReturnValue(
          new Promise((resolve) => {
            resolveFetch = resolve;
          }),
        );

        findCreateModal().vm.$emit('work-item-created', createdWorkItem);
        await nextTick();
      });

      it('stands a placeholder card in the target column only', () => {
        expect(placeholderColumns()).toEqual([true, false, false]);
      });

      it('clears the placeholder once the fetch lands', async () => {
        resolveFetch(buildBoardWorkItemsResponse([createdWorkItem]));
        await waitForPromises();

        expect(placeholderColumns()).toEqual([false, false, false]);
      });
    });

    it('shows the created toast when the item is on the board view', async () => {
      await requestCreate();

      findCreateModal().vm.$emit('work-item-created', createdWorkItem);
      await waitForPromises();

      expect(toast.show).toHaveBeenCalledWith('Issue created.', expect.any(Object));
    });

    describe('when the created toast renders', () => {
      beforeEach(async () => {
        setHTMLFixture('<div id="gl-toast-0" tabindex="0"></div>');
        await requestCreate();

        findCreateModal().vm.$emit('work-item-created', createdWorkItem);
        await waitForPromises();
      });

      afterEach(() => {
        resetHTMLFixture();
      });

      it('focuses the toast so screen readers announce it', () => {
        expect(document.activeElement).toBe(document.getElementById('gl-toast-0'));
      });
    });

    it('shows a not-shown toast and does not insert when the board filters exclude the item', async () => {
      boardWorkItemsQueryHandler.mockResolvedValue(buildBoardWorkItemsResponse([]));
      await requestCreate();

      findCreateModal().vm.$emit('work-item-created', createdWorkItem);
      await waitForPromises();

      expect(toast.show).toHaveBeenCalledWith(
        'Issue created, but it is not shown on the current view.',
        expect.any(Object),
      );
      expect(addWorkItemToColumn).not.toHaveBeenCalled();
    });

    it('closes the modal after the item is created', async () => {
      await requestCreate();
      expect(findCreateModal().exists()).toBe(true);

      findCreateModal().vm.$emit('work-item-created', createdWorkItem);
      await waitForPromises();

      expect(findCreateModal().exists()).toBe(false);
    });

    it('closes the modal without creating anything when it is dismissed', async () => {
      await requestCreate();

      findCreateModal().vm.$emit('hide-modal');
      await nextTick();

      expect(findCreateModal().exists()).toBe(false);
      expect(addWorkItemToColumn).not.toHaveBeenCalled();
      expect(wrapper.emitted('work-item-created')).toBeUndefined();
    });

    it('does not offer creation when canCreateWorkItem is false', async () => {
      createComponent({ props: { canCreateWorkItem: false } });
      await waitForPromises();

      expect(
        findBoardColumns().wrappers.every((column) => column.props('canCreateWorkItem') === false),
      ).toBe(true);
    });

    describe('focusCreateButton on columns', () => {
      const focusCreateButtonColumns = () =>
        findBoardColumns().wrappers.map((column) => column.props('focusCreateButton'));

      beforeEach(async () => {
        await requestCreate(defaultStatuses[1]);
      });

      describe('when the modal is open', () => {
        it('marks no column', () => {
          expect(focusCreateButtonColumns()).toEqual([false, false, false]);
        });
      });

      describe('when the modal is dismissed', () => {
        beforeEach(async () => {
          findCreateModal().vm.$emit('hide-modal');
          await nextTick();
        });

        it('marks only the clicked column', () => {
          expect(focusCreateButtonColumns()).toEqual([false, true, false]);
        });

        describe('and the modal is opened again', () => {
          beforeEach(async () => {
            await requestCreate(defaultStatuses[1]);
          });

          it('clears the mark on every column', () => {
            expect(focusCreateButtonColumns()).toEqual([false, false, false]);
          });
        });
      });

      describe('when the item is created', () => {
        beforeEach(async () => {
          findCreateModal().vm.$emit('work-item-created', createdWorkItem);
          findCreateModal().vm.$emit('hide-modal');
          await waitForPromises();
        });

        it('marks no column, so focus is left for the created toast', () => {
          expect(focusCreateButtonColumns()).toEqual([false, false, false]);
        });
      });
    });

    describe('on a group-level board', () => {
      const buildType = (id, name, widgetDefinitions) => ({
        __typename: 'WorkItemType',
        id: `gid://gitlab/WorkItems::Type/${id}`,
        name,
        iconName: `issue-type-${name.toLowerCase()}`,
        supportedConversionTypes: [],
        widgetDefinitions,
      });
      const statusWidget = {
        __typename: 'WorkItemWidgetDefinitionStatus',
        type: 'STATUS',
        allowedStatuses: [],
        defaultOpenStatus: null,
      };
      const notesWidget = { __typename: 'WorkItemWidgetDefinitionGeneric', type: 'NOTES' };

      const createGroupBoard = async (types) => {
        workItemTypesQueryHandler.mockResolvedValue(buildWorkItemTypesResponse(types));
        createComponent({
          props: {
            canCreateWorkItem: true,
            queryVariables: { ...queryVariables, isGroup: true },
          },
        });
        await waitForPromises();
      };

      const columnCreateProps = () =>
        findBoardColumns().wrappers.map((column) => column.props('canCreateWorkItem'));

      // Only epics can be created at group level, so an epic without the grouped
      // attribute would land off the board.
      it('does not offer creation when epics cannot carry the grouped attribute', async () => {
        await createGroupBoard([
          buildType(1, 'Issue', [statusWidget]),
          buildType(8, 'Epic', [notesWidget]),
        ]);

        expect(columnCreateProps()).toEqual([false, false, false]);
      });

      it('offers creation when epics can carry the grouped attribute', async () => {
        await createGroupBoard([buildType(8, 'Epic', [statusWidget])]);

        expect(columnCreateProps()).toEqual([true, true, true]);
      });
    });
  });

  describe('persisting the created item position', () => {
    const toDo = defaultStatuses[0];
    const createdWorkItem = buildWorkItemNode(9);
    const topCard = buildWorkItemNode(5);

    const createItem = async ({ nodes = [topCard], props = {} } = {}) => {
      readWorkItemsFromColumn.mockReturnValue(nodes);
      createComponent({
        props: { canCreateWorkItem: true, ...props },
      });
      await waitForPromises();

      findBoardColumns().at(defaultStatuses.indexOf(toDo)).vm.$emit('create-item', toDo);
      await waitForPromises();

      findCreateModal().vm.$emit('work-item-created', createdWorkItem);
      await waitForPromises();
    };

    it('persists the new item above the current top card under manual sort', async () => {
      await createItem();

      expect(updateMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          input: { id: createdWorkItem.id, moveAfterId: topCard.id },
        }),
      );
    });

    it('does not persist a position when the board is not sorted manually', async () => {
      await createItem({ props: { queryVariables: { ...queryVariables, sort: 'CREATED_DESC' } } });

      expect(updateMutationHandler).not.toHaveBeenCalled();
    });
  });

  describe('collapsed groups', () => {
    const groupId = (status) => `status:${status.id}`;

    it('marks only columns whose group id is in collapsedGroups as collapsed', async () => {
      createComponent({ props: { collapsedGroups: [groupId(defaultStatuses[1])] } });
      await waitForPromises();

      expect(findBoardColumns().wrappers.map((column) => column.props('collapsed'))).toEqual([
        false,
        true,
        false,
      ]);
    });

    it('defaults every column to expanded when collapsedGroups is empty', async () => {
      createComponent();
      await waitForPromises();

      expect(findBoardColumns().wrappers.map((column) => column.props('collapsed'))).toEqual([
        false,
        false,
        false,
      ]);
    });

    it('emits toggle-collapse with the group id when a column requests it', async () => {
      createComponent();
      await waitForPromises();

      findBoardColumns().at(2).vm.$emit('toggle-collapse');

      expect(wrapper.emitted('toggle-collapse')).toEqual([[groupId(defaultStatuses[2])]]);
    });
  });

  describe('column keyboard focus', () => {
    const groupId = (status) => `status:${status.id}`;
    const BoardColumnWithBody = stubComponent(BoardColumn, {
      template: '<div :data-column-body-id="value.id" tabindex="-1"></div>',
    });
    const focusableColumns = () =>
      findBoardColumns().wrappers.map((column) => column.props('focusable'));

    const createWithColumnBodies = async (props = {}) => {
      createComponent({
        props,
        stubs: { BoardColumn: BoardColumnWithBody },
        attachTo: document.body,
      });
      await waitForPromises();
    };

    afterEach(() => {
      resetHTMLFixture();
    });

    describe('by default', () => {
      beforeEach(async () => {
        await createWithColumnBodies();
      });

      it('makes only the first column focusable', () => {
        expect(focusableColumns()).toEqual([true, false, false]);
      });
    });

    describe('when the first column is collapsed', () => {
      beforeEach(async () => {
        await createWithColumnBodies({ collapsedGroups: [groupId(defaultStatuses[0])] });
      });

      it('makes the first expanded column focusable', () => {
        expect(focusableColumns()).toEqual([false, true, false]);
      });
    });

    describe('when a column asks to focus the next one', () => {
      beforeEach(async () => {
        await createWithColumnBodies();
        jest.spyOn(findBoardColumns().at(1).element, 'scrollIntoView');

        findBoardColumns().at(0).vm.$emit('focus-adjacent', FOCUS_NEXT);
        await waitForPromises();
      });

      it('scrolls the next column into view', () => {
        expect(findBoardColumns().at(1).element.scrollIntoView).toHaveBeenCalledWith({
          block: 'nearest',
          inline: 'nearest',
        });
      });

      it('makes the next column the focusable one', () => {
        expect(focusableColumns()).toEqual([false, true, false]);
      });

      it('focuses the next column', () => {
        expect(document.activeElement).toBe(findBoardColumns().at(1).element);
      });

      describe('when that column is then collapsed', () => {
        beforeEach(async () => {
          await wrapper.setProps({ collapsedGroups: [groupId(defaultStatuses[1])] });
        });

        it('makes the first expanded column focusable again', () => {
          expect(focusableColumns()).toEqual([true, false, false]);
        });
      });
    });

    describe('when focus moves into another column', () => {
      beforeEach(async () => {
        await createWithColumnBodies();

        findBoardColumns().at(2).vm.$emit('column-focus');
        await nextTick();
      });

      it('makes that column the focusable one', () => {
        expect(focusableColumns()).toEqual([false, false, true]);
      });
    });

    describe('when the column in between is collapsed', () => {
      beforeEach(async () => {
        await createWithColumnBodies({ collapsedGroups: [groupId(defaultStatuses[1])] });

        findBoardColumns().at(0).vm.$emit('focus-adjacent', FOCUS_NEXT);
        await waitForPromises();
      });

      it('skips it', () => {
        expect(document.activeElement).toBe(findBoardColumns().at(2).element);
      });
    });

    describe.each`
      edge       | index | delta
      ${'first'} | ${0}  | ${FOCUS_PREVIOUS}
      ${'last'}  | ${2}  | ${FOCUS_NEXT}
    `('when moving past the $edge column', ({ index, delta }) => {
      beforeEach(async () => {
        await createWithColumnBodies();
        findBoardColumns().at(index).element.focus();

        findBoardColumns().at(index).vm.$emit('focus-adjacent', delta);
        await waitForPromises();
      });

      it('keeps focus where it is', () => {
        expect(document.activeElement).toBe(findBoardColumns().at(index).element);
      });
    });
  });

  describe('groupSort', () => {
    const groupId = (status) => `status:${status.id}`;

    it('orders columns ascending by default', async () => {
      createComponent();
      await waitForPromises();

      expect(columnNames()).toEqual(['To do', 'In progress', 'Done']);
    });

    it('reverses the column order when groupSort is desc', async () => {
      createComponent({ props: { groupSort: 'desc' } });
      await waitForPromises();

      expect(columnNames()).toEqual(['Done', 'In progress', 'To do']);
    });

    it('ignores a stale groupOrder when groupSort is explicitly asc', async () => {
      const groupOrder = [groupId(defaultStatuses[2]), groupId(defaultStatuses[0])];

      createComponent({ props: { groupSort: 'asc', groupOrder } });
      await waitForPromises();

      expect(columnNames()).toEqual(['To do', 'In progress', 'Done']);
    });
  });

  describe('column reordering', () => {
    const groupId = (status) => `status:${status.id}`;
    const createReorderable = ({ props = {}, visibleGroups } = {}) =>
      createComponent({ props: { canManageColumns: true, ...props }, visibleGroups });

    it('renders columns in the persisted groupOrder, appending unlisted ones in default order', async () => {
      createReorderable({
        props: { groupOrder: [groupId(defaultStatuses[1]), groupId(defaultStatuses[0])] },
      });
      await waitForPromises();

      expect(columnNames()).toEqual(['In progress', 'To do', 'Done']);
    });

    it('emits reorder-groups with the new group id order when a column is dragged', async () => {
      createReorderable();
      await waitForPromises();

      findColumnDraggable().vm.$emit('end', { oldIndex: 0, newIndex: 2 });

      expect(wrapper.emitted('reorder-groups')).toEqual([
        [[groupId(defaultStatuses[1]), groupId(defaultStatuses[2]), groupId(defaultStatuses[0])]],
      ]);
    });

    it('shows a toast naming the dragged column', async () => {
      createReorderable();
      await waitForPromises();

      findColumnDraggable().vm.$emit('end', { oldIndex: 0, newIndex: 2 });

      expect(toast.show).toHaveBeenCalledWith('Moved To do');
    });

    it('does not HTML-escape the column name in the toast', async () => {
      const apostropheStatuses = [
        buildStatus(1, "Won't do", 'to_do'),
        defaultStatuses[1],
        defaultStatuses[2],
      ];
      statusesQueryHandler.mockImplementation(() =>
        Promise.resolve(buildNamespaceStatusesResponse(apostropheStatuses)),
      );
      createReorderable();
      await waitForPromises();

      findColumnDraggable().vm.$emit('end', { oldIndex: 0, newIndex: 2 });

      expect(toast.show).toHaveBeenCalledWith("Moved Won't do");
    });

    it('reflects the new order immediately, without waiting for the persisted groupOrder', async () => {
      createReorderable();
      await waitForPromises();

      findColumnDraggable().vm.$emit('end', { oldIndex: 0, newIndex: 2 });
      await nextTick();

      expect(columnNames()).toEqual(['In progress', 'Done', 'To do']);
    });

    it('does not emit reorder-groups or show a toast when a column is dropped in place', async () => {
      createReorderable();
      await waitForPromises();

      findColumnDraggable().vm.$emit('end', { oldIndex: 1, newIndex: 1 });

      expect(wrapper.emitted('reorder-groups')).toBeUndefined();
      expect(toast.show).not.toHaveBeenCalled();
    });

    it('keeps a hidden column in its stored position when reordering the visible ones', async () => {
      // Stored order is Done, In progress, To do, but Done is hidden. Hidden columns aren't
      // fetched (the fetch is scoped to visible ones), so groupValues never includes Done —
      // its stored slot still needs to survive the reorder, since it's a real column.
      createReorderable({
        props: {
          groupOrder: [
            groupId(defaultStatuses[2]),
            groupId(defaultStatuses[1]),
            groupId(defaultStatuses[0]),
          ],
        },
        visibleGroups: [groupId(defaultStatuses[1]), groupId(defaultStatuses[0])],
      });
      await waitForPromises();

      expect(columnNames()).toEqual(['In progress', 'To do']);

      findColumnDraggable().vm.$emit('end', { oldIndex: 0, newIndex: 1 });

      expect(wrapper.emitted('reorder-groups')).toEqual([
        [[groupId(defaultStatuses[2]), groupId(defaultStatuses[0]), groupId(defaultStatuses[1])]],
      ]);
    });

    it('tells each column whether it can move left/right based on its position', async () => {
      createReorderable();
      await waitForPromises();

      const columns = findBoardColumns();
      expect(columns.at(0).props()).toMatchObject({ canMoveLeft: false, canMoveRight: true });
      expect(columns.at(1).props()).toMatchObject({ canMoveLeft: true, canMoveRight: true });
      expect(columns.at(2).props()).toMatchObject({ canMoveLeft: true, canMoveRight: false });
    });

    it('moves a column right via the header menu, reflecting and persisting the new order', async () => {
      createReorderable();
      await waitForPromises();

      findBoardColumns().at(0).vm.$emit('move-column', 1);
      await waitForPromises();

      expect(columnNames()).toEqual(['In progress', 'To do', 'Done']);
      expect(wrapper.emitted('reorder-groups')).toEqual([
        [[groupId(defaultStatuses[1]), groupId(defaultStatuses[0]), groupId(defaultStatuses[2])]],
      ]);
      expect(findAnnouncement().text()).toBe('Moved To do right');
      expect(toast.show).toHaveBeenCalledWith('Moved To do right');
    });

    it('moves a column left via the header menu', async () => {
      createReorderable();
      await waitForPromises();

      findBoardColumns().at(2).vm.$emit('move-column', -1);
      await waitForPromises();

      expect(columnNames()).toEqual(['To do', 'Done', 'In progress']);
      expect(findAnnouncement().text()).toBe('Moved Done left');
      expect(toast.show).toHaveBeenCalledWith('Moved Done left');
    });

    describe('when a column is moved via the header menu', () => {
      beforeEach(async () => {
        createComponent({
          props: { canManageColumns: true },
          stubs: { BoardColumn: BoardColumnWithActionsToggle },
          attachTo: document.body,
        });
        await waitForPromises();

        findBoardColumns().at(0).vm.$emit('move-column', 1);
        await waitForPromises();
      });

      afterEach(() => {
        resetHTMLFixture();
      });

      it('keeps focus on the moved column actions menu', () => {
        expect(document.activeElement).toBe(findColumnActionsToggle(1));
      });
    });

    it('ignores a move past the first or last position and announces nothing', async () => {
      createReorderable();
      await waitForPromises();

      findBoardColumns().at(0).vm.$emit('move-column', -1);
      findBoardColumns().at(2).vm.$emit('move-column', 1);
      await waitForPromises();

      expect(wrapper.emitted('reorder-groups')).toBeUndefined();
      expect(columnNames()).toEqual(['To do', 'In progress', 'Done']);
      expect(findAnnouncement().text()).toBe('');
    });

    describe('tracking', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      it('tracks a drag reorder', async () => {
        createReorderable();
        await waitForPromises();
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findColumnDraggable().vm.$emit('end', { oldIndex: 0, newIndex: 2 });

        expect(trackEventSpy).toHaveBeenCalledWith(
          'configure_columns_on_work_item_board',
          { label: 'reorder_drag' },
          undefined,
        );
      });

      it('tracks a header menu move', async () => {
        createReorderable();
        await waitForPromises();
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findBoardColumns().at(0).vm.$emit('move-column', 1);

        expect(trackEventSpy).toHaveBeenCalledWith(
          'configure_columns_on_work_item_board',
          { label: 'reorder_menu' },
          undefined,
        );
      });

      it('tracks nothing when a column is dropped in place', async () => {
        createReorderable();
        await waitForPromises();
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findColumnDraggable().vm.$emit('end', { oldIndex: 1, newIndex: 1 });

        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'configure_columns_on_work_item_board',
          expect.anything(),
          undefined,
        );
      });

      it('tracks nothing when a move past the first or last position is ignored', async () => {
        createReorderable();
        await waitForPromises();
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findBoardColumns().at(0).vm.$emit('move-column', -1);
        findBoardColumns().at(2).vm.$emit('move-column', 1);

        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'configure_columns_on_work_item_board',
          expect.anything(),
          undefined,
        );
      });
    });

    it('disables column dragging when there is only one column', async () => {
      statusesQueryHandler.mockResolvedValue(
        buildNamespaceStatusesResponse([buildStatus(1, 'To do', 'to_do')]),
      );
      createReorderable();
      await waitForPromises();

      expect(findColumnDraggable().attributes('disabled')).toBeDefined();
      expect(findBoardColumns().at(0).props('reorderable')).toBe(false);
    });

    it('enables column dragging when there is more than one column', async () => {
      createReorderable();
      await waitForPromises();

      expect(findColumnDraggable().attributes('disabled')).toBeUndefined();
      expect(findBoardColumns().at(0).props('reorderable')).toBe(true);
    });

    it('does not allow reordering when the user cannot persist it', async () => {
      createComponent({ props: { canManageColumns: false } });
      await waitForPromises();

      expect(findColumnDraggable().attributes('disabled')).toBeDefined();
      expect(findBoardColumns().at(0).props('reorderable')).toBe(false);
    });
  });

  describe('hiding a column', () => {
    const groupId = (status) => `status:${status.id}`;
    const hideColumn = (index) => findBoardColumns().at(index).vm.$emit('hide-column');

    it('does not offer hiding to a user who cannot persist it', async () => {
      createComponent({ props: { canManageColumns: false } });
      await waitForPromises();

      expect(findBoardColumns().at(0).props('canHide')).toBe(false);
    });

    it('offers hiding on a single column, which is too few to reorder', async () => {
      statusesQueryHandler.mockResolvedValue(
        buildNamespaceStatusesResponse([buildStatus(1, 'To do', 'to_do')]),
      );
      createComponent({ props: { canManageColumns: true } });
      await waitForPromises();

      expect(findBoardColumns().at(0).props()).toMatchObject({
        reorderable: false,
        canHide: true,
      });
    });

    it('emits the remaining ids when nothing was hidden yet', async () => {
      createComponent({ props: { canManageColumns: true } });
      await waitForPromises();

      hideColumn(1);

      expect(wrapper.emitted('hide-group')).toEqual([
        [[groupId(defaultStatuses[0]), groupId(defaultStatuses[2])]],
      ]);
    });

    it('refetches scoped and drops the column once the parent applies the selection', async () => {
      createComponent({ props: { canManageColumns: true } });
      await waitForPromises();

      hideColumn(1);
      await wrapper.setProps({
        visibleGroups: [groupId(defaultStatuses[0]), groupId(defaultStatuses[2])],
      });
      await waitForPromises();

      expect(statusesQueryHandler).toHaveBeenLastCalledWith({
        fullPath: 'full/path',
        ids: [defaultStatuses[0].id, defaultStatuses[2].id],
      });
      expect(columnNames()).toEqual(['To do', 'Done']);
    });

    describe('when a column is hidden', () => {
      const hideAndApply = async (index, remaining) => {
        hideColumn(index);
        await wrapper.setProps({ visibleGroups: remaining.map(groupId) });
        await waitForPromises();
      };

      beforeEach(async () => {
        createComponent({
          props: { canManageColumns: true },
          stubs: { BoardColumn: BoardColumnWithActionsToggle, GlButton },
          attachTo: document.body,
        });
        await waitForPromises();
      });

      afterEach(() => {
        resetHTMLFixture();
      });

      it('does not announce before the parent applies the selection', async () => {
        hideColumn(1);
        await waitForPromises();

        expect(findAnnouncement().text()).toBe('');
      });

      describe('when a middle column is hidden', () => {
        beforeEach(async () => {
          await hideAndApply(1, [defaultStatuses[0], defaultStatuses[2]]);
        });

        it('announces the hidden column', () => {
          expect(findAnnouncement().text()).toBe('In progress list hidden');
        });

        it('moves focus to the next column actions menu', () => {
          expect(document.activeElement).toBe(findColumnActionsToggle(1));
        });
      });

      describe('when the last column is hidden', () => {
        beforeEach(async () => {
          await hideAndApply(2, [defaultStatuses[0], defaultStatuses[1]]);
        });

        it('moves focus to the previous column actions menu', () => {
          expect(document.activeElement).toBe(findColumnActionsToggle(1));
        });
      });

      describe('when the only visible column is hidden', () => {
        beforeEach(async () => {
          await wrapper.setProps({ visibleGroups: [groupId(defaultStatuses[0])] });
          await waitForPromises();
          await hideAndApply(0, []);
        });

        it('moves focus to the display button', () => {
          expect(document.activeElement).toBe(findDisplayButton().element);
        });
      });
    });

    describe('tracking', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      it('tracks hiding a column from the header menu', async () => {
        createComponent({ props: { canManageColumns: true } });
        await waitForPromises();
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        hideColumn(1);
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'configure_columns_on_work_item_board',
          { label: 'hide_group' },
          undefined,
        );
      });
    });
  });

  describe('loading more items in a column', () => {
    const itemsLoaded = (count) => findBoardColumns().at(0).vm.$emit('items-loaded', count);

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    describe('when one item loads', () => {
      beforeEach(async () => {
        itemsLoaded(1);
        await waitForPromises();
      });

      it('announces the singular count and column', () => {
        expect(findAnnouncement().text()).toBe('Loaded 1 more item in To do');
      });
    });

    describe('when several items load', () => {
      beforeEach(async () => {
        itemsLoaded(20);
        await waitForPromises();
      });

      it('announces the plural count and column', () => {
        expect(findAnnouncement().text()).toBe('Loaded 20 more items in To do');
      });
    });
  });

  describe('when selecting a card', () => {
    const workItem = buildWorkItemNode(1);
    const showParam = (id) => btoa(JSON.stringify({ iid: '1', full_path: 'group/project', id }));

    afterEach(() => {
      setWindowLocation('http://test.host/');
    });

    it('opens the detail work item panel', async () => {
      createComponent();
      await waitForPromises();

      findBoardColumns().at(0).vm.$emit('set-active-item', workItem);

      expect(wrapper.emitted('set-active-item')).toEqual([[workItem]]);
    });

    it('opens the detail panel for the item on reload', async () => {
      setWindowLocation(`?show=${showParam(1)}`);
      createComponent();
      await waitForPromises();

      findBoardColumns().at(0).vm.$emit('check-board-params', [workItem]);

      expect(wrapper.emitted('set-active-item')).toEqual([
        [{ ...workItem, fullPath: 'group/project' }],
      ]);
    });

    it('does not open the panel when the "show" item is not in the loaded column', async () => {
      setWindowLocation(`?show=${showParam(999)}`);
      createComponent();
      await waitForPromises();

      findBoardColumns().at(0).vm.$emit('check-board-params', [workItem]);

      expect(wrapper.emitted('set-active-item')).toBeUndefined();
    });
  });

  describe('fetch scoping', () => {
    const groupId = (status) => `status:${status.id}`;

    describe('before the persisted selection is known', () => {
      beforeEach(() => {
        createComponent({ visibleGroupsLoaded: false });
      });

      it('does not fetch the statuses', () => {
        expect(statusesQueryHandler).not.toHaveBeenCalled();
      });
    });

    describe('when no visible groups are set', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('fetches without an ids filter', () => {
        expect(statusesQueryHandler).toHaveBeenCalledWith({
          fullPath: 'full/path',
          ids: undefined,
        });
      });

      it('renders every column', () => {
        expect(findBoardColumns()).toHaveLength(defaultStatuses.length);
      });
    });

    describe('when only some group ids are visible', () => {
      beforeEach(async () => {
        createComponent({
          visibleGroups: [groupId(defaultStatuses[0]), groupId(defaultStatuses[2])],
        });
        await waitForPromises();
      });

      it('fetches only those ids', () => {
        expect(statusesQueryHandler).toHaveBeenCalledWith({
          fullPath: 'full/path',
          ids: [defaultStatuses[0].id, defaultStatuses[2].id],
        });
      });

      it('renders only the columns whose group id is listed', () => {
        expect(findBoardColumns().wrappers.map((column) => column.props('value').name)).toEqual([
          'To do',
          'Done',
        ]);
      });
    });

    describe('when the visible groups list is empty (hide all)', () => {
      beforeEach(async () => {
        // Set up independently of the shared handler's `ids ? filter : defaultStatuses`
        // mock, so this doesn't just prove the mock's own assumption about `ids: []`
        // matches itself — it asserts the backend is actually asked for zero groups.
        statusesQueryHandler.mockResolvedValue(buildNamespaceStatusesResponse([]));
        createComponent({ visibleGroups: [] });
        await waitForPromises();
      });

      it('still fetches the statuses, unscoped, to learn the true total', () => {
        expect(statusesQueryHandler).toHaveBeenCalledWith({
          fullPath: 'full/path',
          ids: undefined,
        });
      });

      it('renders no columns', () => {
        expect(findBoardColumns()).toHaveLength(0);
      });

      it('tells the user all groups are hidden', () => {
        expect(findAllGroupsHiddenPrompt().exists()).toBe(true);
      });
    });

    describe('when the visible groups change', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();

        await wrapper.setProps({ visibleGroups: [groupId(defaultStatuses[1])] });
        await waitForPromises();
      });

      it('refetches and updates the rendered columns', () => {
        expect(findBoardColumns().wrappers.map((column) => column.props('value').name)).toEqual([
          'In progress',
        ]);
      });
    });
  });

  describe('when there are more groups than the board can show', () => {
    const tooManyStatuses = Array.from({ length: 26 }, (_, index) => buildStatus(index + 1));
    const limitDescription =
      'Boards show up to 25 groups at a time. Choose groups using the Display options.';

    const createTooManyGroupsComponent = async ({ visibleGroups } = {}) => {
      statusesQueryHandler.mockResolvedValue(buildNamespaceStatusesResponse(tooManyStatuses));
      createComponent({
        visibleGroups,
        stubs: {
          GlEmptyState: stubComponent(GlEmptyState, { template: RENDER_ALL_SLOTS_TEMPLATE }),
          GlSprintf,
        },
      });
      await waitForPromises();
    };

    beforeEach(async () => {
      await createTooManyGroupsComponent();
    });

    it('renders no columns', () => {
      expect(findBoardColumns()).toHaveLength(0);
    });

    it('tells the user about the group limit', () => {
      expect(findAllGroupsHiddenPrompt().find('h2').text()).toBe('All groups are hidden');
      expect(findAllGroupsHiddenPrompt().find('[data-testid="slot-description"]').text()).toBe(
        limitDescription,
      );
    });

    it('emits open-group-by-settings when the Display action is clicked', () => {
      findDisplayButton().vm.$emit('click');

      expect(wrapper.emitted('open-group-by-settings')).toEqual([[]]);
    });

    describe('when all groups are hidden as well', () => {
      beforeEach(async () => {
        await createTooManyGroupsComponent({ visibleGroups: [] });
      });

      it('shows the group limit message instead', () => {
        expect(findAllGroupsHiddenPrompt().find('[data-testid="slot-description"]').text()).toBe(
          limitDescription,
        );
      });
    });

    describe('once a selection within the limit is saved', () => {
      beforeEach(async () => {
        statusesQueryHandler.mockResolvedValue(
          buildNamespaceStatusesResponse(tooManyStatuses.slice(0, 2)),
        );
        await wrapper.setProps({
          visibleGroups: tooManyStatuses.slice(0, 2).map((status) => `status:${status.id}`),
        });
        await waitForPromises();
      });

      it('renders the selected columns instead of the prompt', () => {
        expect(findBoardColumns()).toHaveLength(2);
        expect(findAllGroupsHiddenPrompt().exists()).toBe(false);
      });
    });
  });

  describe('drag and drop', () => {
    const fromStatus = defaultStatuses[0];
    const toStatus = defaultStatuses[1];
    const movedNode = buildWorkItemNode(1);

    const dragEvent = ({ from = fromStatus, to = toStatus, oldIndex = 0, newIndex = 0 } = {}) => ({
      from: { dataset: { columnValueId: from.id } },
      to: { dataset: { columnValueId: to.id } },
      item: { dataset: { workItemId: movedNode.id } },
      oldIndex,
      newIndex,
    });

    const emitCardMove = (event) => findBoardColumns().at(0).vm.$emit('card-move', event);

    beforeEach(async () => {
      readWorkItemFromColumn.mockReturnValue(movedNode);
      createComponent();
      await waitForPromises();
    });

    it('persists the move with the target status', async () => {
      emitCardMove(dragEvent());
      await waitForPromises();

      expect(updateMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          input: { id: movedNode.id, statusWidget: { status: toStatus.id } },
        }),
      );
    });

    it('optimistically moves the card from the source column to the target column', async () => {
      emitCardMove(dragEvent());
      await waitForPromises();

      expect(removeWorkItemFromColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          variables: columnVariables(fromStatus),
          workItemId: movedNode.id,
        }),
      );
      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          variables: columnVariables(toStatus),
          workItem: movedNode,
          index: 0,
          patchCard: expect.any(Function),
        }),
      );
    });

    it('decrements the source column count and increments the target column count', async () => {
      emitCardMove(dragEvent());
      await waitForPromises();

      expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
        expect.objectContaining({ variables: columnCountVariables(fromStatus), delta: -1 }),
      );
      expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
        expect.objectContaining({ variables: columnCountVariables(toStatus), delta: 1 }),
      );
    });

    it('does nothing when the card is dropped in its original column', () => {
      emitCardMove(dragEvent({ to: fromStatus }));

      expect(updateMutationHandler).not.toHaveBeenCalled();
      expect(removeWorkItemFromColumn).not.toHaveBeenCalled();
      expect(addWorkItemToColumn).not.toHaveBeenCalled();
      expect(adjustWorkItemCountInColumn).not.toHaveBeenCalled();
    });

    it('does nothing when the moved card is not in the cache', () => {
      readWorkItemFromColumn.mockReturnValue(null);

      emitCardMove(dragEvent());

      expect(updateMutationHandler).not.toHaveBeenCalled();
    });

    it('persists a same-column reorder with relative position and no status change', async () => {
      const columnNodes = [buildWorkItemNode(1), buildWorkItemNode(2), buildWorkItemNode(3)];
      readWorkItemsFromColumn.mockReturnValue(columnNodes);

      emitCardMove(dragEvent({ to: fromStatus, oldIndex: 0, newIndex: 2 }));
      await waitForPromises();

      expect(updateMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          input: { id: movedNode.id, moveBeforeId: columnNodes[2].id },
        }),
      );
      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          variables: columnVariables(fromStatus),
          index: 2,
          patchCard: null,
        }),
      );
    });

    it('includes relative position alongside the status change on a cross-column move', async () => {
      const columnNodes = [buildWorkItemNode(10), buildWorkItemNode(11)];
      readWorkItemsFromColumn.mockReturnValue(columnNodes);

      emitCardMove(dragEvent({ newIndex: 1 }));
      await waitForPromises();

      expect(updateMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          input: {
            id: movedNode.id,
            statusWidget: { status: toStatus.id },
            moveBeforeId: columnNodes[0].id,
            moveAfterId: columnNodes[1].id,
          },
        }),
      );
    });

    it('disables dragging until the move mutation resolves', async () => {
      let resolveMutation;
      updateMutationHandler.mockReturnValue(
        new Promise((resolve) => {
          resolveMutation = resolve;
        }),
      );

      expect(findBoardColumns().at(0).props('dragDisabled')).toBe(false);

      emitCardMove(dragEvent());
      await nextTick();

      expect(findBoardColumns().at(0).props('dragDisabled')).toBe(true);

      resolveMutation({
        data: { workItemUpdate: { workItem: buildWorkItemNode(1), errors: [] } },
      });
      await waitForPromises();

      expect(findBoardColumns().at(0).props('dragDisabled')).toBe(false);
    });

    it('lets columns offer the card actions menu under manual sort', () => {
      expect(findBoardColumns().at(0).props('canReorderCards')).toBe(true);
    });

    it('withholds the card actions menu once a move is in progress', async () => {
      let resolveMutation;
      updateMutationHandler.mockReturnValue(
        new Promise((resolve) => {
          resolveMutation = resolve;
        }),
      );

      emitCardMove(dragEvent());
      await nextTick();

      expect(findBoardColumns().at(0).props('canReorderCards')).toBe(false);

      resolveMutation({
        data: { workItemUpdate: { workItem: buildWorkItemNode(1), errors: [] } },
      });
      await waitForPromises();

      expect(findBoardColumns().at(0).props('canReorderCards')).toBe(true);
    });

    describe('busy indicator', () => {
      beforeEach(() => {
        jest.useFakeTimers({ legacyFakeTimers: false });
      });

      afterEach(() => {
        jest.useRealTimers();
      });

      it('does not show the busy indicator when the mutation resolves before the delay elapses', async () => {
        emitCardMove(dragEvent());
        await waitForPromises();

        jest.advanceTimersByTime(MOVE_IN_PROGRESS_INDICATOR_DELAY);
        await nextTick();

        expect(findBoardColumns().at(0).props('showBusyIndicator')).toBe(false);
      });

      it('shows the busy indicator only once the mutation has been in flight for the configured delay', async () => {
        let resolveMutation;
        updateMutationHandler.mockReturnValue(
          new Promise((resolve) => {
            resolveMutation = resolve;
          }),
        );

        emitCardMove(dragEvent());
        await nextTick();

        expect(findBoardColumns().at(0).props('showBusyIndicator')).toBe(false);

        jest.advanceTimersByTime(MOVE_IN_PROGRESS_INDICATOR_DELAY);
        await nextTick();

        expect(findBoardColumns().at(0).props('showBusyIndicator')).toBe(true);

        resolveMutation({
          data: { workItemUpdate: { workItem: buildWorkItemNode(1), errors: [] } },
        });
        await waitForPromises();

        expect(findBoardColumns().at(0).props('showBusyIndicator')).toBe(false);
      });
    });

    describe('when the board is not sorted manually', () => {
      const columnNodes = [buildWorkItemNode(1), buildWorkItemNode(2), buildWorkItemNode(3)];

      beforeEach(async () => {
        readWorkItemsFromColumn.mockReturnValue(columnNodes);
        createComponent({ props: { queryVariables: { ...queryVariables, sort: 'CREATED_DESC' } } });
        await waitForPromises();
      });

      it('does not persist a same-column reorder', () => {
        emitCardMove(dragEvent({ to: fromStatus, oldIndex: 0, newIndex: 2 }));

        expect(updateMutationHandler).not.toHaveBeenCalled();
      });

      it('persists the status change without relative position on a cross-column move', async () => {
        emitCardMove(dragEvent({ newIndex: 1 }));
        await waitForPromises();

        expect(updateMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            input: { id: movedNode.id, statusWidget: { status: toStatus.id } },
          }),
        );
      });

      it('withholds the card actions menu, since a position could never be persisted', () => {
        expect(findBoardColumns().at(0).props('canReorderCards')).toBe(false);
      });
    });

    it('shows a toast and captures the error when the mutation returns errors', async () => {
      updateMutationHandler.mockResolvedValue({
        data: { workItemUpdate: { workItem: null, errors: ['nope'] } },
      });

      emitCardMove(dragEvent());
      await waitForPromises();

      expect(toast.show).toHaveBeenCalledWith(
        'Something went wrong while updating the work item. Please try again.',
      );
      expect(Sentry.captureException).toHaveBeenCalled();
    });

    it('shows a toast and captures the error when the mutation rejects', async () => {
      updateMutationHandler.mockRejectedValue(new Error('network'));

      emitCardMove(dragEvent());
      await waitForPromises();

      expect(toast.show).toHaveBeenCalledWith(
        'Something went wrong while updating the work item. Please try again.',
      );
      expect(Sentry.captureException).toHaveBeenCalled();
    });

    describe('success toast', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('shows a success toast with the reference and target column name on a cross-column move', async () => {
        emitCardMove(dragEvent());
        await waitForPromises();

        expect(toast.show).toHaveBeenCalledWith(`Moved ${movedNode.reference} to ${toStatus.name}`);
      });

      it('does not show a success toast on a same-column reorder', async () => {
        emitCardMove(dragEvent({ to: fromStatus, oldIndex: 0, newIndex: 1 }));
        await waitForPromises();

        expect(toast.show).not.toHaveBeenCalled();
      });

      it('does not show a success toast when the mutation fails', async () => {
        updateMutationHandler.mockResolvedValue({
          data: { workItemUpdate: { workItem: null, errors: ['nope'] } },
        });

        emitCardMove(dragEvent());
        await waitForPromises();

        expect(toast.show).toHaveBeenCalledWith(
          'Something went wrong while updating the work item. Please try again.',
        );
        expect(toast.show).not.toHaveBeenCalledWith(
          expect.stringContaining(`Moved ${movedNode.reference}`),
        );
      });
    });

    describe('move announcement', () => {
      describe('when a card is dragged within its column', () => {
        beforeEach(async () => {
          readWorkItemsFromColumn.mockReturnValue([
            movedNode,
            buildWorkItemNode(2),
            buildWorkItemNode(3),
          ]);
          emitCardMove(dragEvent({ to: fromStatus, oldIndex: 0, newIndex: 1 }));
          await waitForPromises();
        });

        it('does not announce the reorder', () => {
          expect(findAnnouncement().text()).toBe('');
        });
      });

      describe('when a card is dragged to another column', () => {
        beforeEach(async () => {
          emitCardMove(dragEvent());
          await waitForPromises();
        });

        it('does not announce a cross-column move', () => {
          expect(findAnnouncement().text()).toBe('');
        });
      });
    });

    describe('tracking', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      it('tracks a cross-column move labelled as a column change', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMove(dragEvent());
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'move_card_on_work_item_board',
          { label: 'column', property: 'drag' },
          undefined,
        );
      });

      it('tracks a same-column reorder labelled as a position change', async () => {
        readWorkItemsFromColumn.mockReturnValue([
          buildWorkItemNode(1),
          buildWorkItemNode(2),
          buildWorkItemNode(3),
        ]);
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMove(dragEvent({ to: fromStatus, oldIndex: 0, newIndex: 2 }));
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'move_card_on_work_item_board',
          { label: 'position', property: 'drag' },
          undefined,
        );
      });

      it('tracks a failure and not a success when the mutation returns errors', async () => {
        updateMutationHandler.mockResolvedValue({
          data: { workItemUpdate: { workItem: null, errors: ['nope'] } },
        });
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMove(dragEvent());
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'fail_card_move_on_work_item_board',
          { label: 'column', property: 'drag' },
          undefined,
        );
        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'move_card_on_work_item_board',
          expect.anything(),
          undefined,
        );
      });

      it('tracks a failure when the mutation rejects', async () => {
        updateMutationHandler.mockRejectedValue(new Error('network'));
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMove(dragEvent());
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'fail_card_move_on_work_item_board',
          { label: 'column', property: 'drag' },
          undefined,
        );
      });

      it('tracks nothing when the card is dropped back in place', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMove(dragEvent({ to: fromStatus }));
        await waitForPromises();

        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'move_card_on_work_item_board',
          expect.anything(),
          undefined,
        );
        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'fail_card_move_on_work_item_board',
          expect.anything(),
          undefined,
        );
      });
    });

    describe('moving a card via the actions menu', () => {
      const columnNodes = [buildWorkItemNode(1), buildWorkItemNode(2), buildWorkItemNode(3)];
      const emitCardMoveToPosition = (event) =>
        findBoardColumns().at(0).vm.$emit('card-move-to-position', event);
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      beforeEach(() => {
        readWorkItemsFromColumn.mockReturnValue(columnNodes);
        readWorkItemFromColumn.mockReturnValue(buildWorkItemNode(1, { reference: 'full/path#1' }));
      });

      it('persists a move to the start of the column as moveAfterId on the current first card', async () => {
        emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
        await waitForPromises();

        expect(updateMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            input: { id: movedNode.id, moveAfterId: columnNodes[0].id },
          }),
        );
      });

      it('persists a move to the end of the column as moveBeforeId on the current last card', async () => {
        emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 0, newIndex: 2 });
        await waitForPromises();

        expect(updateMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            input: { id: movedNode.id, moveBeforeId: columnNodes[2].id },
          }),
        );
      });

      it('does nothing without a workItemId', () => {
        emitCardMoveToPosition({ workItemId: undefined, oldIndex: 0, newIndex: 2 });

        expect(updateMutationHandler).not.toHaveBeenCalled();
      });

      it('tracks the move labelled with the menu source, not drag', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 0, newIndex: 2 });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'move_card_on_work_item_board',
          { label: 'position', property: 'menu' },
          undefined,
        );
      });

      describe('when a move to the start succeeds', () => {
        beforeEach(async () => {
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await waitForPromises();
        });

        it('announces the reference and column', () => {
          expect(findAnnouncement().text()).toBe('Moved #1 to the start of To do');
        });

        it('does not show a toast', () => {
          expect(toast.show).not.toHaveBeenCalled();
        });
      });

      describe('when the moved card is rendered', () => {
        const findCardLink = () =>
          findBoardColumns().at(0).find('[data-testid="work-item-link"]').element;

        beforeEach(async () => {
          createComponent({
            stubs: {
              BoardColumn: stubComponent(BoardColumn, {
                template: `<div><div data-work-item-id="${movedNode.id}"><a data-testid="work-item-link" href="#">Card</a></div></div>`,
              }),
            },
            attachTo: document.body,
          });
          await waitForPromises();
        });

        afterEach(() => {
          resetHTMLFixture();
        });

        describe('when the move succeeds', () => {
          beforeEach(async () => {
            emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
            await waitForPromises();
          });

          it('moves focus to the card link', () => {
            expect(document.activeElement).toBe(findCardLink());
          });
        });

        describe('when the move fails', () => {
          beforeEach(async () => {
            updateMutationHandler.mockRejectedValue(new Error('network'));
            emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
            await waitForPromises();
          });

          it('moves focus to the card link', () => {
            expect(document.activeElement).toBe(findCardLink());
          });
        });
      });

      describe('when a move to the end succeeds', () => {
        beforeEach(async () => {
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 0, newIndex: 2 });
          await waitForPromises();
        });

        it('announces the reference and column', () => {
          expect(findAnnouncement().text()).toBe('Moved #1 to the end of To do');
        });
      });

      describe('when the card is from another project', () => {
        beforeEach(async () => {
          readWorkItemFromColumn.mockReturnValue(movedNode);
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await waitForPromises();
        });

        it('announces the full reference', () => {
          expect(findAnnouncement().text()).toBe('Moved group/project#1 to the start of To do');
        });
      });

      describe('while the move is saving', () => {
        let resolveMutation;

        beforeEach(async () => {
          updateMutationHandler.mockReturnValue(
            new Promise((resolve) => {
              resolveMutation = resolve;
            }),
          );
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await nextTick();
        });

        it('does not announce yet', () => {
          expect(findAnnouncement().text()).toBe('');
        });

        it('announces once the move succeeds', async () => {
          resolveMutation({
            data: { workItemUpdate: { workItem: buildWorkItemNode(1), errors: [] } },
          });
          await waitForPromises();

          expect(findAnnouncement().text()).toBe('Moved #1 to the start of To do');
        });
      });

      describe('when the mutation returns errors', () => {
        beforeEach(async () => {
          updateMutationHandler.mockResolvedValue({
            data: { workItemUpdate: { workItem: null, errors: ['nope'] } },
          });
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await waitForPromises();
        });

        it('shows the error toast instead of announcing the move', () => {
          expect(findAnnouncement().text()).toBe('');
          expect(toast.show).toHaveBeenCalledWith(
            'Something went wrong while updating the work item. Please try again.',
          );
        });
      });

      describe('when the mutation rejects', () => {
        beforeEach(async () => {
          updateMutationHandler.mockRejectedValue(new Error('network'));
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await waitForPromises();
        });

        it('shows the error toast instead of announcing the move', () => {
          expect(findAnnouncement().text()).toBe('');
          expect(toast.show).toHaveBeenCalledWith(
            'Something went wrong while updating the work item. Please try again.',
          );
        });
      });

      describe('when the next move starts', () => {
        beforeEach(async () => {
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await waitForPromises();
        });

        it('clears the previous announcement, so a repeat is read out again', async () => {
          expect(findAnnouncement().text()).toBe('Moved #1 to the start of To do');

          updateMutationHandler.mockReturnValue(new Promise(() => {}));
          emitCardMoveToPosition({ workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
          await nextTick();

          expect(findAnnouncement().text()).toBe('');
        });
      });
    });

    describe('moving a card to another list via the actions menu', () => {
      const columnNodes = [buildWorkItemNode(2), buildWorkItemNode(3)];
      const emitCardMoveToList = () =>
        findBoardColumns().at(0).vm.$emit('card-move-to-list', {
          workItemId: movedNode.id,
          oldIndex: 0,
          toValue: toStatus,
        });
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      beforeEach(() => {
        readWorkItemsFromColumn.mockReturnValue(columnNodes);
        readWorkItemFromColumn.mockReturnValue(buildWorkItemNode(1, { reference: 'full/path#1' }));
      });

      it('offers every expanded column as a move target', async () => {
        createComponent({ props: { collapsedGroups: [`status:${defaultStatuses[2].id}`] } });
        await waitForPromises();

        expect(findBoardColumns().at(0).props('moveTargets')).toEqual(
          findBoardColumns()
            .wrappers.slice(0, 2)
            .map((column) => column.props('value')),
        );
      });

      it('persists the move with the target status, at the top of the target column', async () => {
        emitCardMoveToList();
        await waitForPromises();

        expect(updateMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            input: {
              id: movedNode.id,
              statusWidget: { status: toStatus.id },
              moveAfterId: columnNodes[0].id,
            },
          }),
        );
        expect(addWorkItemToColumn).toHaveBeenCalledWith(
          expect.objectContaining({ variables: columnVariables(toStatus), index: 0 }),
        );
      });

      it('tracks a column move from the menu', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        emitCardMoveToList();
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'move_card_on_work_item_board',
          { label: 'column', property: 'menu' },
          undefined,
        );
      });

      describe('when the move succeeds', () => {
        beforeEach(async () => {
          emitCardMoveToList();
          await waitForPromises();
        });

        it('announces the reference and the target column', () => {
          expect(findAnnouncement().text()).toBe('Moved full/path#1 to In progress');
        });

        it('shows the same message in a toast', () => {
          expect(toast.show).toHaveBeenCalledWith('Moved full/path#1 to In progress');
        });
      });

      describe('while a move is saving', () => {
        beforeEach(async () => {
          updateMutationHandler.mockReturnValue(new Promise(() => {}));
          emitCardMoveToList();
          await nextTick();
        });

        it('ignores another move to a list', () => {
          emitCardMoveToList();

          expect(updateMutationHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('when the moved card is rendered', () => {
        beforeEach(async () => {
          createComponent({
            stubs: {
              BoardColumn: stubComponent(BoardColumn, {
                template: `<div><div data-work-item-id="${movedNode.id}"><a data-testid="work-item-link" href="#">Card</a></div></div>`,
              }),
            },
            attachTo: document.body,
          });
          await waitForPromises();
          emitCardMoveToList();
          await waitForPromises();
        });

        afterEach(() => {
          resetHTMLFixture();
        });

        it('moves focus to the card link', () => {
          expect(document.activeElement).toBe(
            findBoardColumns().at(0).find('[data-testid="work-item-link"]').element,
          );
        });
      });
    });
  });

  describe('when a card is moved via the actions menu in a column with an apostrophe', () => {
    const movedNode = buildWorkItemNode(1, { reference: 'full/path#1' });

    beforeEach(async () => {
      statusesQueryHandler.mockResolvedValue(
        buildNamespaceStatusesResponse([buildStatus(4, "Won't do", 'canceled')]),
      );
      readWorkItemFromColumn.mockReturnValue(movedNode);
      readWorkItemsFromColumn.mockReturnValue([
        buildWorkItemNode(2),
        buildWorkItemNode(3),
        movedNode,
      ]);
      createComponent();
      await waitForPromises();

      findBoardColumns()
        .at(0)
        .vm.$emit('card-move-to-position', { workItemId: movedNode.id, oldIndex: 2, newIndex: 0 });
      await waitForPromises();
    });

    it('does not HTML-escape the column name', () => {
      expect(findAnnouncement().text()).toBe("Moved #1 to the start of Won't do");
    });
  });

  describe('when an unfiltered board item is updated via side panel', () => {
    const fromStatus = defaultStatuses[0];
    const toStatus = defaultStatuses[1];
    const updatedNode = buildWorkItemNode(1, { widgets: [buildStatusWidget(toStatus)] });

    const mockCurrentColumn = (columnStatus) => {
      readWorkItemFromColumn.mockImplementation(({ variables }) =>
        variables.status?.name === columnStatus.name ? updatedNode : null,
      );
    };

    const updateItem = async (workItem) => {
      wrapper.setProps({ updatedWorkItem: workItem });
      await nextTick();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('moves the card from its current column to the one matching its new status', async () => {
      mockCurrentColumn(fromStatus);
      await updateItem(updatedNode);

      expect(removeWorkItemFromColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          variables: columnVariables(fromStatus),
          workItemId: updatedNode.id,
        }),
      );
      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          variables: columnVariables(toStatus),
          workItem: updatedNode,
          index: 0,
          patchCard: expect.any(Function),
        }),
      );
    });

    it('updates the source column and the target column counts', async () => {
      mockCurrentColumn(fromStatus);
      await updateItem(updatedNode);

      expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
        expect.objectContaining({ variables: columnCountVariables(fromStatus), delta: -1 }),
      );
      expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
        expect.objectContaining({ variables: columnCountVariables(toStatus), delta: 1 }),
      );
    });

    it('does nothing when the card is already in the column matching its status', async () => {
      mockCurrentColumn(toStatus);
      await updateItem(updatedNode);

      expect(removeWorkItemFromColumn).not.toHaveBeenCalled();
      expect(addWorkItemToColumn).not.toHaveBeenCalled();
      expect(adjustWorkItemCountInColumn).not.toHaveBeenCalled();
    });
  });

  describe('when a filtered board item is updated via side panel', () => {
    const fromStatus = defaultStatuses[0];
    const toStatus = defaultStatuses[1];
    const updatedNode = buildWorkItemNode(1, { widgets: [buildStatusWidget(toStatus)] });

    const mockCurrentColumn = (columnStatus) => {
      readWorkItemFromColumn.mockImplementation(({ variables }) =>
        columnStatus && variables.status?.name === columnStatus.name ? updatedNode : null,
      );
    };

    const mockMatchesFilters = (matches) => {
      boardWorkItemsQueryHandler.mockResolvedValue(
        buildBoardWorkItemsResponse(matches ? [updatedNode] : []),
      );
    };

    const updateItem = async (workItem) => {
      wrapper.setProps({ updatedWorkItem: workItem });
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent({ props: { hasActiveFilters: true } });
      await waitForPromises();
    });

    describe('when the item no longer matches the filters', () => {
      beforeEach(async () => {
        mockMatchesFilters(false);
        mockCurrentColumn(fromStatus);
        await updateItem(updatedNode);
      });

      it('removes the item from its current column', () => {
        expect(removeWorkItemFromColumn).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: columnVariables(fromStatus),
            workItemId: updatedNode.id,
          }),
        );
      });

      it('decrements the count of its current column', () => {
        expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
          expect.objectContaining({ variables: columnCountVariables(fromStatus), delta: -1 }),
        );
      });

      it('does not add the item to another column', () => {
        expect(addWorkItemToColumn).not.toHaveBeenCalled();
      });
    });

    describe('when the item was previously excluded but now matches the filters', () => {
      beforeEach(async () => {
        mockMatchesFilters(true);
        mockCurrentColumn(null);
        await updateItem(updatedNode);
      });

      it('adds the item to its matching column', () => {
        expect(addWorkItemToColumn).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: columnVariables(toStatus),
            workItem: updatedNode,
            index: 0,
          }),
        );
      });

      it('increments the count of the matching column', () => {
        expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
          expect.objectContaining({ variables: columnCountVariables(toStatus), delta: 1 }),
        );
      });

      it('does not remove the item from any column', () => {
        expect(removeWorkItemFromColumn).not.toHaveBeenCalled();
      });
    });

    describe('when the item still matches but belongs in a different column', () => {
      beforeEach(async () => {
        mockMatchesFilters(true);
        mockCurrentColumn(fromStatus);
        await updateItem(updatedNode);
      });

      it('removes the item from its current column', () => {
        expect(removeWorkItemFromColumn).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: columnVariables(fromStatus),
            workItemId: updatedNode.id,
          }),
        );
      });

      it('adds the item to its matching column', () => {
        expect(addWorkItemToColumn).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: columnVariables(toStatus),
            workItem: updatedNode,
            index: 0,
          }),
        );
      });

      it('decrements the count of its current column', () => {
        expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
          expect.objectContaining({ variables: columnCountVariables(fromStatus), delta: -1 }),
        );
      });

      it('increments the count of the matching column', () => {
        expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
          expect.objectContaining({ variables: columnCountVariables(toStatus), delta: 1 }),
        );
      });
    });

    describe('when the item matches and is already in the matching column', () => {
      beforeEach(async () => {
        mockMatchesFilters(true);
        mockCurrentColumn(toStatus);
        await updateItem(updatedNode);
      });

      it('does not remove the item from any column', () => {
        expect(removeWorkItemFromColumn).not.toHaveBeenCalled();
      });

      it('does not add the item to any column', () => {
        expect(addWorkItemToColumn).not.toHaveBeenCalled();
      });

      it('does not adjust any column count', () => {
        expect(adjustWorkItemCountInColumn).not.toHaveBeenCalled();
      });
    });

    describe('when the filter check request fails', () => {
      beforeEach(async () => {
        boardWorkItemsQueryHandler.mockRejectedValue(new Error('network error'));
        mockCurrentColumn(fromStatus);
        await updateItem(updatedNode);
      });

      it('does not remove the item from any column', () => {
        expect(removeWorkItemFromColumn).not.toHaveBeenCalled();
      });

      it('does not add the item to any column', () => {
        expect(addWorkItemToColumn).not.toHaveBeenCalled();
      });

      it('does not adjust any column count', () => {
        expect(adjustWorkItemCountInColumn).not.toHaveBeenCalled();
      });

      it('captures the error in Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });
  });

  describe('drag eligibility gate', () => {
    const workItem = {
      id: 'gid://gitlab/WorkItem/1',
      workItemType: { id: 'gid://gitlab/WorkItems::Type/1' },
    };

    const startDrag = (item = workItem) => findBoardColumns().at(0).vm.$emit('drag-start', item);

    it('fetches gate data via the strategy gate query', async () => {
      createComponent({ props: { rootPageFullPath: 'group/subgroup' } });
      await waitForPromises();

      expect(workItemTypesQueryHandler).toHaveBeenCalledWith({ fullPath: 'group/subgroup' });
    });

    it('disables only the columns the strategy reports the dragged item cannot enter', async () => {
      // Mock isDropAllowed directly here; the actual status-specific logic behind
      // it is covered in status_strategy_spec.
      jest
        .spyOn(statusStrategy, 'isDropAllowed')
        .mockImplementation(({ value }) => value.id === defaultStatuses[0].id);
      createComponent();
      await waitForPromises();

      startDrag();
      await nextTick();

      expect(findBoardColumns().at(0).props('dropDisabled')).toBe(false);
      expect(findBoardColumns().at(1).props('dropDisabled')).toBe(true);
    });

    it('clears the disabled columns once a card move ends', async () => {
      jest
        .spyOn(statusStrategy, 'isDropAllowed')
        .mockImplementation(({ value }) => value.id === defaultStatuses[0].id);
      createComponent();
      await waitForPromises();

      startDrag();
      await nextTick();
      findBoardColumns().at(0).vm.$emit('card-move', { oldIndex: 0, newIndex: 0 });
      await nextTick();

      expect(findBoardColumns().wrappers.every((c) => c.props('dropDisabled') === false)).toBe(
        true,
      );
    });

    it('passes the gate data to columns, so the card actions menu only offers allowed lists', async () => {
      createComponent();
      await waitForPromises();

      expect(findBoardColumns().at(0).props('gateData')).toEqual(
        expect.objectContaining({ allowedStatusesByTypeId: expect.any(Object) }),
      );
    });

    it('disables no columns when the type has no recorded status constraint', async () => {
      createComponent();
      await waitForPromises();

      startDrag();
      await nextTick();

      expect(findBoardColumns().wrappers.every((c) => c.props('dropDisabled') === false)).toBe(
        true,
      );
    });
  });

  describe('statuses query', () => {
    it('calls the statuses query with rootPageFullPath', async () => {
      createComponent({ props: { rootPageFullPath: 'group/subgroup' } });
      await nextTick();

      expect(statusesQueryHandler).toHaveBeenCalledWith({ fullPath: 'group/subgroup' });
    });
  });

  describe('when the statuses query errors', () => {
    const queryError = new Error('GraphQL failure');

    beforeEach(async () => {
      statusesQueryHandler.mockRejectedValue(queryError);
      createComponent();
      await waitForPromises();
    });

    it('captures the error in Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(queryError);
    });

    it('emits set-error with a user-facing message', () => {
      expect(wrapper.emitted('set-error')).toEqual([
        ['Something went wrong when fetching the board columns. Please try again.'],
      ]);
    });

    it('renders no BoardColumns', () => {
      expect(findBoardColumns()).toHaveLength(0);
    });

    it('hides the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });
  });
});
