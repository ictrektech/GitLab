import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlLoadingIcon, GlTabs, GlFormCheckbox, GlSegmentedControl } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { ignoreConsoleMessages } from 'helpers/console_watcher';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import setWindowLocation from 'helpers/set_window_location_helper';
import { RENDER_ALL_SLOTS_TEMPLATE, stubComponent } from 'helpers/stub_component';
import TodosApp from '~/todos/components/todos_app.vue';
import TodoItem from '~/todos/components/todo_item.vue';
import TodosFilterBar from '~/todos/components/todos_filter_bar.vue';
import TodosBulkBar from '~/todos/components/todos_bulk_bar.vue';
import TodosGroup from '~/todos/components/todos_group.vue';
import TodosPagination, { CURSOR_CHANGED_EVENT } from '~/todos/components/todos_pagination.vue';
import getTodosQuery from '~/todos/components/queries/get_todos.query.graphql';
import {
  INSTRUMENT_TAB_LABELS,
  STATUS_BY_TAB,
  TABS_INDICES,
  TODO_WAIT_BEFORE_RELOAD,
} from '~/todos/constants';
import { mockTracking, unmockTracking } from 'jest/__helpers__/tracking_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import getPendingTodosCount from '~/todos/components/queries/get_pending_todos_count.query.graphql';
import {
  MR_BUILD_FAILED_TODO,
  MR_REVIEW_REQUEST_TODO,
  todosResponse,
  todosResponseEmptyLastPage,
  todosResponseNonFullFirstPage,
  getPendingTodosCountResponse,
} from '../mock_data';

Vue.use(VueApollo);

describe('TodosApp', () => {
  let wrapper;

  const todosQuerySuccessHandler = jest.fn().mockResolvedValue(todosResponse);
  const todosCountsQuerySuccessHandler = jest.fn().mockResolvedValue(getPendingTodosCountResponse);

  const createComponent = ({
    mountFn = shallowMountExtended,
    todosQueryHandler = todosQuerySuccessHandler,
    todosCountsQueryHandler = todosCountsQuerySuccessHandler,
    provide = {},
    stubs = {},
  } = {}) => {
    const mockApollo = createMockApollo();
    mockApollo.defaultClient.setRequestHandler(getTodosQuery, todosQueryHandler);
    mockApollo.defaultClient.setRequestHandler(getPendingTodosCount, todosCountsQueryHandler);

    wrapper = mountFn(TodosApp, {
      apolloProvider: mockApollo,
      provide,
      stubs,
    });
  };

  const findTodoItems = () => wrapper.findAllComponents(TodoItem);
  const findFirstTodoItem = () => wrapper.findComponent(TodoItem);
  const findGlTabs = () => wrapper.findComponent(GlTabs);
  const findFilterBar = () => wrapper.findComponent(TodosFilterBar);
  const findRefreshButton = () => wrapper.findComponentByTestId('refresh-todos');
  const findPendingTodosCount = () => wrapper.findByTestId('pending-todos-count');
  const findTodoItemListContainer = () => wrapper.findByTestId('todo-item-list-container');
  const findPagination = () => wrapper.findComponent(TodosPagination);

  ignoreConsoleMessages([/\[Vue warn\]: \(deprecation TRANSITION_GROUP_ROOT\)/]);

  it('renders gl-tab with correct href attributes', async () => {
    createComponent({ mountFn: mountExtended });
    await nextTick();

    const links = wrapper.findAll('.nav-link');

    expect(links.at(0).attributes('href')).toBe('/');
    expect(links.at(1).attributes('href')).toBe('?state=snoozed');
    expect(links.at(2).attributes('href')).toBe('?state=done');
  });

  it('should have a tracking event for each tab', () => {
    expect(STATUS_BY_TAB).toHaveLength(INSTRUMENT_TAB_LABELS.length);
  });

  it('shows a loading state while fetching todos', () => {
    createComponent();

    expect(findTodoItems()).toHaveLength(0);
    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
  });

  it('renders todo items once the query has resolved', async () => {
    createComponent();
    await waitForPromises();

    expect(findTodoItems()).toHaveLength(todosResponse.data.currentUser.todos.nodes.length);
    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(false);
  });

  it('shows pagination for the todos', async () => {
    createComponent();
    await waitForPromises();

    expect(findPagination().exists()).toBe(true);
  });

  it('fetches the todos when pagination changes', async () => {
    createComponent();
    await waitForPromises();

    const newCursor = { first: 50, after: 'cursor-1' };
    findPagination().vm.$emit(CURSOR_CHANGED_EVENT, newCursor);
    await waitForPromises();

    expect(todosQuerySuccessHandler).toHaveBeenLastCalledWith(
      expect.objectContaining({
        ...newCursor,
      }),
    );
  });

  it('resets cursor to "full last page" when seeing an empty list while not being on page 1', async () => {
    createComponent();

    const newCursor = { first: 20, after: 'id-39' };
    findPagination().vm.$emit(CURSOR_CHANGED_EVENT, newCursor);
    await waitForPromises();
    expect(wrapper.vm.cursor.after).toBe('id-39');

    todosQuerySuccessHandler.mockResolvedValueOnce(todosResponseEmptyLastPage);
    wrapper.vm.$apollo.queries.todos.refetch();
    await waitForPromises();

    expect(wrapper.vm.cursor).toEqual({
      first: null,
      last: 20,
      after: null,
      before: null,
    });
  });

  it('resets cursor to "full first page" when seeing a non-full list while being on page 1', async () => {
    createComponent();

    const newCursor = { last: 20, before: 'id-7' };
    findPagination().vm.$emit(CURSOR_CHANGED_EVENT, newCursor);
    await waitForPromises();
    expect(wrapper.vm.cursor.before).toBe('id-7');

    todosQuerySuccessHandler.mockResolvedValueOnce(todosResponseNonFullFirstPage);
    wrapper.vm.$apollo.queries.todos.refetch();
    await waitForPromises();

    expect(wrapper.vm.cursor).toEqual({
      first: 20,
      last: null,
      after: null,
      before: null,
    });
  });

  it('fetches the todos and counts when filters change', async () => {
    createComponent();

    const filters = {
      groupId: ['1'],
      projectId: ['2'],
      authorId: ['3'],
      type: ['4'],
      action: ['assigned'],
      sort: 'CREATED_DESC',
    };
    findFilterBar().vm.$emit('filters-changed', filters);
    await waitForPromises();

    expect(todosQuerySuccessHandler).toHaveBeenLastCalledWith({
      ...filters,
      state: ['pending'],
      first: 20,
      last: null,
      after: null,
      before: null,
    });
    expect(todosCountsQuerySuccessHandler).toHaveBeenLastCalledWith(filters);
  });

  it('resets the pagination when filters change', async () => {
    createComponent();

    const filters = {
      groupId: ['1'],
    };

    const newCursor = { first: 50, after: 'cursor-1' };
    findPagination().vm.$emit(CURSOR_CHANGED_EVENT, newCursor);
    await waitForPromises();

    expect(todosQuerySuccessHandler).toHaveBeenLastCalledWith(expect.objectContaining(newCursor));

    findFilterBar().vm.$emit('filters-changed', filters);
    await waitForPromises();

    expect(todosQuerySuccessHandler).toHaveBeenLastCalledWith({
      ...filters,
      state: ['pending'],
      first: newCursor.first,
      last: null,
      after: null,
      before: null,
    });
    expect(todosCountsQuerySuccessHandler).toHaveBeenLastCalledWith(filters);
  });

  it('refreshes count and list', async () => {
    createComponent();
    await waitForPromises();

    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);

    findRefreshButton().vm.$emit('click', new Event('click'));

    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(2);
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(2);
  });

  it('shows the pending todos count once it has been fetched', async () => {
    createComponent();

    expect(findPendingTodosCount().text()).toBe('-');

    await waitForPromises();

    expect(findPendingTodosCount().text()).toBe(
      String(getPendingTodosCountResponse.data.currentUser.todos.count),
    );
  });

  it('refetches todos when page becomes visible again', async () => {
    createComponent();

    // Wait and account for initial query
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);

    // Make sure we don't refetch when document became hidden
    jest.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    document.dispatchEvent(new Event('visibilitychange'));
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);

    // Expect refetch when document becomes visible
    jest.spyOn(document, 'hidden', 'get').mockReturnValue(false);
    document.dispatchEvent(new Event('visibilitychange'));
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(2);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(2);
  });

  it('refetches todos one second after the cursor leaves the list of todos', async () => {
    createComponent();

    // Wait and account for initial query
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);

    // Simulate interacting with a todo item then mousing out of the list zone
    findFirstTodoItem().vm.$emit('change');
    const list = findTodoItemListContainer();
    list.trigger('mouseleave');

    // Should refresh the count, but not the list
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(2);

    // Run out the clock
    jest.advanceTimersByTime(TODO_WAIT_BEFORE_RELOAD + 50); // 1s + some jitter

    // Refreshes the count and the list
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(2);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(3);
  });

  it('does not refresh todos after the cursor leaves the list of todos if nothing changed', async () => {
    createComponent();

    // Wait and account for initial query
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);

    // Simulate NOT interacting with a todo item then mousing out of the list zone
    const list = findTodoItemListContainer();
    list.trigger('mouseleave');

    // Should not update anything
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);

    // Run out the clock
    jest.advanceTimersByTime(TODO_WAIT_BEFORE_RELOAD + 50); // 1s + some jitter

    // Should not update anything
    await waitForPromises();
    expect(todosQuerySuccessHandler).toHaveBeenCalledTimes(1);
    expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);
  });

  it('passes the default status to the filter bar', () => {
    createComponent();

    expect(findFilterBar().props('todosStatus')).toEqual(['pending']);
  });

  it.each`
    tabIndex | status                 | label
    ${0}     | ${['pending']}         | ${'status_pending'}
    ${1}     | ${['pending']}         | ${'status_snoozed'}
    ${2}     | ${['done']}            | ${'status_done'}
    ${3}     | ${['pending', 'done']} | ${'status_all'}
  `(
    'sets the filter bar status to $status and tracks the event $label when the tab changes to index #$tabIndex',
    async ({ tabIndex, status, label }) => {
      createComponent();

      // Navigate to another tab that isn't the target
      findGlTabs().vm.$emit('input', tabIndex === 0 ? 1 : tabIndex - 1);
      await nextTick();

      const trackingSpy = mockTracking(undefined, wrapper.element, jest.spyOn);
      findGlTabs().vm.$emit('input', tabIndex);
      await nextTick();

      expect(trackingSpy).toHaveBeenCalledWith(undefined, 'filter_todo_list', {
        label,
      });
      expect(findFilterBar().props('todosStatus')).toEqual(status);
      unmockTracking();
    },
  );

  it('syncs tab change to URL while leaving other params unchanged', () => {
    setWindowLocation('?group_id=123');
    createComponent();
    expect(window.location.search).toBe('?group_id=123');

    findGlTabs().vm.$emit('input', 1);
    expect(window.location.search).toBe('?group_id=123&state=snoozed');

    findGlTabs().vm.$emit('input', 2);
    expect(window.location.search).toBe('?group_id=123&state=done');

    findGlTabs().vm.$emit('input', 3);
    expect(window.location.search).toBe('?group_id=123&state=all');

    findGlTabs().vm.$emit('input', 0);
    expect(window.location.search).toBe('?group_id=123');
  });

  describe('reading `state` param from URL', () => {
    beforeEach(() => {
      setWindowLocation('?state=done');
    });

    it('activates correct tab', () => {
      createComponent();
      expect(findGlTabs().props('value')).toBe(2);
    });
  });

  describe('bulk selection', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    const findSelectedTodoItems = () => findTodoItems().filter((item) => item.props('selected'));
    const findSelectAllCheckbox = () => wrapper.findComponent(GlFormCheckbox);
    const findTodosBulkBarContainer = () => wrapper.findByTestId('todos-bulk-bar-container');
    const findBulkBar = () => wrapper.findComponent(TodosBulkBar);

    describe('select all checkbox', () => {
      it('is not visible on "All" tab', async () => {
        findGlTabs().vm.$emit('input', 3); // All tab
        await nextTick();

        expect(findSelectAllCheckbox().isVisible()).toBe(false);
      });

      it('is visible on other tabs', () => {
        expect(findSelectAllCheckbox().isVisible()).toBe(true);
      });

      it('becomes indeterminate when some but not all items are selected', async () => {
        findFirstTodoItem().vm.$emit(
          'select-change',
          todosResponse.data.currentUser.todos.nodes[0].id,
          true,
        );
        await nextTick();

        expect(findSelectAllCheckbox().attributes()).toMatchObject({
          indeterminate: 'true',
        });
      });

      it('becomes sticky when items are selected', async () => {
        const classIsSticky = 'is-sticky';

        expect(findTodosBulkBarContainer().classes()).not.toContain(classIsSticky);

        findFirstTodoItem().vm.$emit(
          'select-change',
          todosResponse.data.currentUser.todos.nodes[0].id,
          true,
        );
        await nextTick();

        expect(findTodosBulkBarContainer().classes()).toContain(classIsSticky);
      });
    });

    describe('selection state', () => {
      it('clears selection when changing tabs', async () => {
        // Select an item
        findFirstTodoItem().vm.$emit(
          'select-change',
          todosResponse.data.currentUser.todos.nodes[0].id,
          true,
        );
        await nextTick();
        expect(findSelectedTodoItems()).toHaveLength(1);

        // Change tab
        findGlTabs().vm.$emit('input', 2);
        await nextTick();

        expect(findSelectedTodoItems()).toHaveLength(0);
      });

      it('updates selected prop when selecting items', async () => {
        const todoId = todosResponse.data.currentUser.todos.nodes[0].id;
        findFirstTodoItem().vm.$emit('select-change', todoId, true);
        await nextTick();

        // Check that exactly one item is selected
        expect(findSelectedTodoItems()).toHaveLength(1);

        // Check that the correct item is selected
        const selectedItem = findTodoItems().at(0); // Since we selected the first item
        expect(selectedItem.props('selected')).toBe(true);
      });

      it('enables "select all" state when all items are selected indivudually', async () => {
        // Select todo items one by one
        const allTodoIds = todosResponse.data.currentUser.todos.nodes.map((todo) => todo.id);
        allTodoIds.forEach((id) => {
          findFirstTodoItem().vm.$emit('select-change', id, true);
        });
        await nextTick();

        expect(findSelectAllCheckbox().attributes('checked')).toBe('true');
      });

      it('clears "select all" state when last item is deselected', async () => {
        // First select all
        findSelectAllCheckbox().vm.$emit('change', true);
        await nextTick();
        expect(findSelectAllCheckbox().attributes('checked')).toBe('true');

        // Then deselect one by one
        for (const todo of todosResponse.data.currentUser.todos.nodes) {
          findFirstTodoItem().vm.$emit('select-change', todo.id, false);
        }
        await nextTick();

        expect(findSelectAllCheckbox().attributes('checked')).toBeUndefined();
      });
    });

    describe('bulk actions', () => {
      it('renders TodoItems with `selectable` prop', () => {
        expect(findFirstTodoItem().props('selectable')).toBe(true);
      });

      it('shows bulk bar when items are selected', async () => {
        expect(findBulkBar().isVisible()).toBe(false);

        findFirstTodoItem().vm.$emit(
          'select-change',
          todosResponse.data.currentUser.todos.nodes[0].id,
          true,
        );
        await nextTick();

        expect(findBulkBar().isVisible()).toBe(true);
      });

      it('clears selection and refreshes after bulk action', async () => {
        findFirstTodoItem().vm.$emit(
          'select-change',
          todosResponse.data.currentUser.todos.nodes[0].id,
          true,
        );
        await nextTick();

        findBulkBar().vm.$emit('change');
        await nextTick();

        expect(findSelectedTodoItems()).toHaveLength(0);
        expect(todosQuerySuccessHandler).toHaveBeenCalled();
      });
    });
  });

  describe('provide/inject', () => {
    it('provides the correct values to child components', () => {
      createComponent();

      const provided = wrapper.vm.$options.provide.call(wrapper.vm);

      expect(provided.currentTab.value).toBe(TABS_INDICES.pending);
      expect(provided.currentTime.value).toBeInstanceOf(Date);
      expect(provided.currentUserId).toBeDefined();
    });

    it('provides reactive currentUserId after query resolves', async () => {
      createComponent();

      const provided = wrapper.vm.$options.provide.call(wrapper.vm);
      expect(provided.currentUserId.value).toBeNull();

      await waitForPromises();

      expect(provided.currentUserId.value).toBe(todosResponse.data.currentUser.id);
    });
  });

  describe('grouped view', () => {
    const SECOND_REVIEW_TODO = { ...MR_REVIEW_REQUEST_TODO, id: 'gid://gitlab/Todo/30' };
    const groupableTodos = [MR_REVIEW_REQUEST_TODO, MR_BUILD_FAILED_TODO, SECOND_REVIEW_TODO];

    const responseWith = (pageInfo = {}, nodes = groupableTodos) => ({
      data: {
        currentUser: {
          ...todosResponse.data.currentUser,
          todos: {
            ...todosResponse.data.currentUser.todos,
            nodes,
            pageInfo: { ...todosResponse.data.currentUser.todos.pageInfo, ...pageInfo },
          },
        },
      },
    });

    const findViewToggle = () => wrapper.findComponent(GlSegmentedControl);
    const findTodoGroups = () => wrapper.findAllComponents(TodosGroup);
    const findPaginationNotice = () => wrapper.findByTestId('todos-grouped-view-pagination-notice');

    const createGroupedComponent = ({
      todosGroupedView = true,
      pageInfo,
      todosQueryHandler = jest.fn().mockResolvedValue(responseWith(pageInfo)),
    } = {}) =>
      createComponent({
        todosQueryHandler,
        provide: { glFeatures: { todosGroupedView } },
        stubs: {
          TodosFilterBar: stubComponent(TodosFilterBar, { template: RENDER_ALL_SLOTS_TEMPLATE }),
        },
      });

    const selectGroupedView = async () => {
      findViewToggle().vm.$emit('input', 'grouped');
      await nextTick();
    };

    beforeEach(() => {
      localStorage.clear();
    });

    describe('when the feature flag is disabled', () => {
      beforeEach(async () => {
        localStorage.setItem('todos-view', JSON.stringify('grouped'));
        createGroupedComponent({ todosGroupedView: false });
        await waitForPromises();
      });

      it('does not render the view toggle', () => {
        expect(findViewToggle().exists()).toBe(false);
      });

      it('renders the list view even if the grouped view was saved', () => {
        expect(findTodoGroups()).toHaveLength(0);
        expect(findTodoItems()).toHaveLength(3);
      });
    });

    describe('when the feature flag is enabled', () => {
      beforeEach(async () => {
        createGroupedComponent();
        await waitForPromises();
      });

      it('renders the view toggle with the list view selected by default', () => {
        expect(findViewToggle().props('value')).toBe('list');
        expect(findViewToggle().attributes('aria-label')).toBe('View');
        expect(findViewToggle().props('options')).toEqual([
          { value: 'list', text: 'List', props: { 'aria-pressed': 'true' } },
          { value: 'grouped', text: 'Grouped', props: { 'aria-pressed': 'false' } },
        ]);
        expect(findTodoItems()).toHaveLength(3);
        expect(findTodoGroups()).toHaveLength(0);
      });

      describe('when selecting the grouped view', () => {
        beforeEach(async () => {
          await selectGroupedView();
        });

        it('groups the to-dos by target in the server order', () => {
          expect(findTodoGroups()).toHaveLength(2);
          expect(findTodoGroups().at(0).props('todos')).toEqual([
            MR_REVIEW_REQUEST_TODO,
            SECOND_REVIEW_TODO,
          ]);
          expect(findTodoGroups().at(1).props('todos')).toEqual([MR_BUILD_FAILED_TODO]);
        });

        it('saves the selected view', () => {
          expect(JSON.parse(localStorage.getItem('todos-view'))).toBe('grouped');
        });

        it('marks the grouped option as pressed', () => {
          expect(
            findViewToggle()
              .props('options')
              .map(({ props }) => props['aria-pressed']),
          ).toEqual(['false', 'true']);
        });

        it('selects the to-dos of all groups with select all', async () => {
          wrapper.findComponent(GlFormCheckbox).vm.$emit('change', true);
          await nextTick();

          expect(findTodoGroups().at(0).props('selectedIds')).toEqual(
            groupableTodos.map(({ id }) => id),
          );
          expect(wrapper.findComponent(TodosBulkBar).props('ids')).toEqual(
            groupableTodos.map(({ id }) => id),
          );
        });

        it('shows the grouped view again when going back to the To Do tab', async () => {
          findGlTabs().vm.$emit('input', 2);
          await waitForPromises();
          findGlTabs().vm.$emit('input', 0);
          await waitForPromises();

          expect(findViewToggle().props('value')).toBe('grouped');
          expect(findTodoGroups()).toHaveLength(2);
        });

        it('does not show the pagination notice when there is a single page', () => {
          expect(findPaginationNotice().exists()).toBe(false);
        });

        it('refreshes the counts when a to-do in a group changes', async () => {
          todosCountsQuerySuccessHandler.mockClear();
          findTodoGroups().at(0).vm.$emit('change');
          await waitForPromises();

          expect(todosCountsQuerySuccessHandler).toHaveBeenCalledTimes(1);
        });

        it('passes the selected to-dos to the groups', async () => {
          findTodoGroups().at(0).vm.$emit('select-change', SECOND_REVIEW_TODO.id, true);
          await nextTick();

          expect(findTodoGroups().at(0).props('selectedIds')).toEqual([SECOND_REVIEW_TODO.id]);
        });

        it.each([
          ['snoozed', 1],
          ['done', 2],
        ])('renders the list view without the toggle on the %s tab', async (_tab, tabIndex) => {
          findGlTabs().vm.$emit('input', tabIndex);
          await waitForPromises();

          expect(findViewToggle().exists()).toBe(false);
          expect(findTodoGroups()).toHaveLength(0);
        });
      });
    });

    describe('when the to-dos are fetched again in a different order', () => {
      const reorderedTodos = [MR_BUILD_FAILED_TODO, MR_REVIEW_REQUEST_TODO, SECOND_REVIEW_TODO];
      const keptOrder = [MR_REVIEW_REQUEST_TODO, MR_BUILD_FAILED_TODO];
      const serverOrder = [MR_BUILD_FAILED_TODO, MR_REVIEW_REQUEST_TODO];

      const findFirstTodoOfEachGroup = () =>
        findTodoGroups().wrappers.map((group) => group.props('todos')[0]);

      // Answers each query in turn with `responses`, then with the reordered to-dos
      const createStickyComponent = async ({
        savedView = 'grouped',
        responses = [responseWith()],
        nextPageInfo = {},
      } = {}) => {
        const todosQueryHandler = responses.reduce(
          (handler, response) => handler.mockResolvedValueOnce(response),
          jest.fn(),
        );
        todosQueryHandler.mockResolvedValue(responseWith(nextPageInfo, reorderedTodos));
        localStorage.setItem('todos-view', JSON.stringify(savedView));
        createGroupedComponent({ todosQueryHandler });
        await waitForPromises();

        return todosQueryHandler;
      };

      const showPageAgain = async () => {
        jest.spyOn(document, 'hidden', 'get').mockReturnValue(false);
        document.dispatchEvent(new Event('visibilitychange'));
        await waitForPromises();
      };

      describe('when the grouped view was saved', () => {
        beforeEach(async () => {
          await createStickyComponent();
        });

        describe('when the page becomes visible again', () => {
          beforeEach(async () => {
            await showPageAgain();
          });

          it('keeps the cards in place', () => {
            expect(findFirstTodoOfEachGroup()).toEqual(keptOrder);
          });

          describe('when clicking refresh', () => {
            beforeEach(async () => {
              findRefreshButton().vm.$emit('click', new Event('click'));
              await waitForPromises();
            });

            it('shows the cards in the server order', () => {
              expect(findFirstTodoOfEachGroup()).toEqual(serverOrder);
            });
          });

          describe('when the sort changes', () => {
            beforeEach(async () => {
              findFilterBar().vm.$emit('filters-changed', { sort: 'CREATED_ASC' });
              await waitForPromises();
            });

            it('shows the cards in the server order', () => {
              expect(findFirstTodoOfEachGroup()).toEqual(serverOrder);
            });
          });

          describe('when the page changes', () => {
            beforeEach(async () => {
              findPagination().vm.$emit(CURSOR_CHANGED_EVENT, { first: 20, after: 'cursor-1' });
              await waitForPromises();
            });

            it('shows the cards in the server order', () => {
              expect(findFirstTodoOfEachGroup()).toEqual(serverOrder);
            });
          });
        });
      });

      describe('when switching from the list view', () => {
        beforeEach(async () => {
          await createStickyComponent({ savedView: 'list' });
          await selectGroupedView();
          await showPageAgain();
        });

        it('keeps the cards in place', () => {
          expect(findFirstTodoOfEachGroup()).toEqual(keptOrder);
        });
      });

      describe('when a refresh changed nothing', () => {
        beforeEach(async () => {
          await createStickyComponent({ responses: [responseWith(), responseWith()] });
          findRefreshButton().vm.$emit('click', new Event('click'));
          await waitForPromises();
          await showPageAgain();
        });

        it('keeps the cards in place', () => {
          expect(findFirstTodoOfEachGroup()).toEqual(keptOrder);
        });
      });

      describe('when the first page is topped up', () => {
        let todosQueryHandler;

        beforeEach(async () => {
          todosQueryHandler = await createStickyComponent({
            responses: [responseWith(), responseWith()],
            nextPageInfo: { hasNextPage: true },
          });
          findPagination().vm.$emit(CURSOR_CHANGED_EVENT, { last: 20, before: 'cursor-1' });
          await waitForPromises();
          await showPageAgain();
        });

        it('loads a full first page', () => {
          expect(todosQueryHandler).toHaveBeenLastCalledWith(
            expect.objectContaining({ first: 20, last: null, before: null }),
          );
        });

        it('keeps the cards in place', () => {
          expect(findFirstTodoOfEachGroup()).toEqual(keptOrder);
        });
      });
    });

    describe('tracking', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      beforeEach(async () => {
        createGroupedComponent();
        await waitForPromises();
      });

      it('tracks a click on each option when it changes the view', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        await selectGroupedView();
        findViewToggle().vm.$emit('input', 'list');

        expect(trackEventSpy).toHaveBeenCalledTimes(2);
        expect(trackEventSpy).toHaveBeenNthCalledWith(
          1,
          'click_todo_grouped_view_toggle',
          {},
          undefined,
        );
        expect(trackEventSpy).toHaveBeenNthCalledWith(
          2,
          'click_todo_list_view_toggle',
          {},
          undefined,
        );
      });

      it('does not track a click on the option that is already selected', () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findViewToggle().vm.$emit('input', 'list');

        expect(trackEventSpy).not.toHaveBeenCalled();
      });
    });

    describe('when the grouped view was saved', () => {
      beforeEach(async () => {
        localStorage.setItem('todos-view', JSON.stringify('grouped'));
        createGroupedComponent();
        await waitForPromises();
      });

      it('renders the grouped view', () => {
        expect(findViewToggle().props('value')).toBe('grouped');
        expect(findTodoGroups()).toHaveLength(2);
      });
    });

    describe.each([
      ['a next page', { hasNextPage: true }],
      ['a previous page', { hasPreviousPage: true }],
    ])('when there is %s', (_description, pageInfo) => {
      beforeEach(async () => {
        createGroupedComponent({ pageInfo });
        await waitForPromises();
      });

      it('does not show the pagination notice in the list view', () => {
        expect(findPaginationNotice().exists()).toBe(false);
      });

      it('shows the pagination notice in the grouped view', async () => {
        await selectGroupedView();

        expect(findPaginationNotice().text()).toBe(
          'Only to-dos on this page are grouped. Other pages might have more to-dos for the same item.',
        );
      });
    });
  });
});
