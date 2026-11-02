import { shallowMount } from '@vue/test-utils';
import Vue from 'vue';
import VueApollo from 'vue-apollo';

import { issueBoardListsQueryResponse } from 'jest/boards/mock_data';
import createMockApollo from 'helpers/mock_apollo_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import waitForPromises from 'helpers/wait_for_promises';
import BoardApp from '~/boards/components/board_app.vue';
import BoardTopBar from '~/boards/components/board_top_bar.vue';
import epicBoardListsQuery from 'ee_component/boards/graphql/epic_board_lists.query.graphql';
import epicListCountQuery from 'ee/boards/graphql/epic_board_lists_deferred.query.graphql';
import epicsSwimlanesQuery from 'ee/boards/graphql/epics_swimlanes.query.graphql';
import activeBoardItemQuery from 'ee_else_ce/boards/graphql/client/active_board_item.query.graphql';
import boardListsQuery from 'ee_else_ce/boards/graphql/board_lists.query.graphql';
import { rawIssue, epicBoardListsQueryResponse, mockEpicSwimlanesResponse } from '../mock_data';

describe('BoardApp', () => {
  let wrapper;
  const boardListQueryHandler = jest.fn().mockResolvedValue(issueBoardListsQueryResponse);
  const epicBoardListQueryHandler = jest.fn().mockResolvedValue(epicBoardListsQueryResponse);
  const mockApollo = createMockApollo([
    [boardListsQuery, boardListQueryHandler],
    [epicBoardListsQuery, epicBoardListQueryHandler],
  ]);

  Vue.use(VueApollo);

  const createComponent = ({
    issue = rawIssue,
    provide = {},
    apolloProvider = mockApollo,
  } = {}) => {
    apolloProvider.clients.defaultClient.cache.writeQuery({
      query: activeBoardItemQuery,
      data: {
        activeBoardItem: { ...issue, listId: 'gid://gitlab/List/1' },
      },
    });

    wrapper = shallowMount(BoardApp, {
      apolloProvider,
      provide: {
        fullPath: 'gitlab-org',
        initialBoardId: 'gid://gitlab/Board/1',
        initialFilterParams: {},
        issuableType: 'issue',
        boardType: 'group',
        isIssueBoard: true,
        isGroupBoard: true,
        hasCustomFieldsFeature: true,
        ...provide,
      },
      stubs: ['router-view'],
    });
  };

  it.each`
    issuableType | isIssueBoard | isEpicBoard | queryHandler                 | notCalledHandler
    ${'epic'}    | ${false}     | ${true}     | ${epicBoardListQueryHandler} | ${boardListQueryHandler}
    ${'issue'}   | ${true}      | ${false}    | ${boardListQueryHandler}     | ${epicBoardListQueryHandler}
  `(
    'fetches $issuableType lists',
    ({ issuableType, isIssueBoard, isEpicBoard, queryHandler, notCalledHandler }) => {
      createComponent({
        provide: { issuableType, isEpicBoard, isIssueBoard },
      });

      expect(queryHandler).toHaveBeenCalled();
      expect(notCalledHandler).not.toHaveBeenCalled();
    },
  );

  describe('when the top bar submits unchanged filters', () => {
    const epicListId = 'gid://gitlab/Boards::EpicList/2';
    const epicListCountQueryHandler = jest.fn().mockResolvedValue({
      data: {
        epicBoardList: {
          id: epicListId,
          metadata: { epicsCount: 10, totalWeight: 33, __typename: 'EpicListMetadata' },
          __typename: 'EpicList',
        },
      },
    });
    const { group } = mockEpicSwimlanesResponse().data;
    const epicsSwimlanesQueryHandler = jest.fn().mockResolvedValue({
      data: { group: { ...group, board: { ...group.board, __typename: 'Board' } } },
    });

    let apolloProvider;

    const watchQuery = async (query, variables) => {
      apolloProvider.clients.defaultClient.watchQuery({ query, variables }).subscribe(() => {});
      await waitForPromises();
    };

    const submitUnchangedFilters = async (filters = {}) => {
      boardListQueryHandler.mockClear();
      epicBoardListQueryHandler.mockClear();
      epicListCountQueryHandler.mockClear();
      epicsSwimlanesQueryHandler.mockClear();

      wrapper.findComponent(BoardTopBar).vm.$emit('submit-filters', filters);
      await waitForPromises();
    };

    beforeEach(() => {
      apolloProvider = createMockApollo([
        [boardListsQuery, boardListQueryHandler],
        [epicBoardListsQuery, epicBoardListQueryHandler],
        [epicListCountQuery, epicListCountQueryHandler],
        [epicsSwimlanesQuery, epicsSwimlanesQueryHandler],
      ]);
    });

    it('refetches epic lists and their counts on an epic board', async () => {
      createComponent({
        apolloProvider,
        provide: {
          initialBoardId: 'gid://gitlab/Boards::EpicBoard/1',
          issuableType: 'epic',
          isIssueBoard: false,
          isEpicBoard: true,
        },
      });
      await waitForPromises();
      await watchQuery(epicListCountQuery, { id: epicListId, filters: {} });

      await submitUnchangedFilters();

      expect(epicBoardListQueryHandler).toHaveBeenCalledTimes(1);
      expect(epicListCountQueryHandler).toHaveBeenCalledTimes(1);
    });

    describe('on an issue board', () => {
      const swimlanesVariables = {
        fullPath: 'gitlab-org',
        boardId: 'gid://gitlab/Board/1',
        issueFilters: { includeSubepics: false },
        sort: 'TITLE_ASC',
        isGroup: true,
        isProject: false,
      };

      it('refetches the swimlane epics when swimlanes are on', async () => {
        window.gon.licensed_features = { swimlanes: true };
        setWindowLocation('?group_by=epic');
        createComponent({ apolloProvider });
        await waitForPromises();
        await watchQuery(epicsSwimlanesQuery, swimlanesVariables);

        await submitUnchangedFilters({ groupBy: 'epic' });

        expect(boardListQueryHandler).toHaveBeenCalledTimes(1);
        expect(epicsSwimlanesQueryHandler).toHaveBeenCalledTimes(1);
      });

      it('leaves the swimlane epics alone when swimlanes are off', async () => {
        createComponent({ apolloProvider });
        await waitForPromises();
        await watchQuery(epicsSwimlanesQuery, swimlanesVariables);

        await submitUnchangedFilters();

        expect(boardListQueryHandler).toHaveBeenCalledTimes(1);
        expect(epicsSwimlanesQueryHandler).not.toHaveBeenCalled();
      });
    });
  });
});
