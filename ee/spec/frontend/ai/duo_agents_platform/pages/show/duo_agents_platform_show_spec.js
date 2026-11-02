import { shallowMount } from '@vue/test-utils';
import Vue, { nextTick, reactive } from 'vue';
import VueApollo from 'vue-apollo';

import DuoAgentsPlatformShow from 'ee/ai/duo_agents_platform/pages/show/duo_agents_platform_show.vue';
import AgentFlowDetails from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_details.vue';
import AgentFlowCancelationModal from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_cancelation_modal.vue';
import {
  AGENT_PLATFORM_STATUS_FINISHED,
  DUO_AGENT_PLATFORM_POLLING_INTERVAL,
} from 'ee/ai/duo_agents_platform/constants';
import { DUO_WORKFLOW_STATUS_RUNNING } from 'ee/ai/constants';
import { getAgentFlow } from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow.query.graphql';
import getAgentFlowLinkedItems from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow_linked_items.query.graphql';
import { clearRouteState } from 'ee/ai/duo_agents_platform/utils/navigation_state';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';

import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';

import { createAlert } from '~/alert';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { cancelWorkflow, restartWorkflow } from 'ee/rest_api';
import * as aiGraphql from 'ee/ai/graphql';

import {
  mockGetAgentFlowResponse,
  mockGetAgentFlowLinkedItemsResponse,
  mockDuoMessages,
  mockUser1,
  mockWorkItemLinks,
  mockMergeRequestLinks,
  mockNoteLinks,
  mockPipelineLinks,
} from 'ee_jest/ai/mocks';

Vue.use(VueApollo);
jest.mock('~/alert');
jest.mock('ee/rest_api');
jest.mock('ee/ai/duo_agents_platform/utils/navigation_state', () => ({
  ...jest.requireActual('ee/ai/duo_agents_platform/utils/navigation_state'),
  clearRouteState: jest.fn(),
}));

describe('DuoAgentsPlatformShow', () => {
  let wrapper;
  let getAgentFlowHandler;
  let getLinkedItemsHandler;
  let routerPush;

  const agentFlowId = '1';
  const graphqlWorkflowId = convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, agentFlowId);
  const defaultMockRoute = {
    params: {
      id: agentFlowId,
    },
  };

  const createWrapper = (props = {}, mockRoute = defaultMockRoute, provide = {}) => {
    const handlers = [
      [getAgentFlow, getAgentFlowHandler],
      [getAgentFlowLinkedItems, getLinkedItemsHandler],
    ];

    wrapper = shallowMount(DuoAgentsPlatformShow, {
      apolloProvider: createMockApollo(handlers),
      propsData: {
        ...props,
      },
      mocks: {
        $route: mockRoute,
        $router: { push: routerPush },
      },
      provide: {
        ...provide,
      },
    });

    return waitForPromises();
  };

  const findAgentFlowDetails = () => wrapper.findComponent(AgentFlowDetails);
  const findCancelConfirmationModal = () => wrapper.findComponent(AgentFlowCancelationModal);

  beforeEach(() => {
    routerPush = jest.fn().mockResolvedValue();
    getAgentFlowHandler = jest.fn().mockResolvedValue(mockGetAgentFlowResponse);
    getLinkedItemsHandler = jest.fn().mockResolvedValue(mockGetAgentFlowLinkedItemsResponse);
  });

  describe('when component is mounted', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    it('renders the AgentFlowDetails component', () => {
      expect(findAgentFlowDetails().exists()).toBe(true);
    });

    it('passes correct props to AgentFlowDetails', () => {
      const workflowDetailsProps = findAgentFlowDetails().props();

      // Use toMatchObject instead of toEqual because Vue 3 passes through the :class binding
      // as a 'class' prop, while Vue 2 does not include it in component props
      expect(workflowDetailsProps).toMatchObject({
        isLoading: false,
        status: 'RUNNING',
        humanStatus: 'Running',
        title: 'Fix the login bug',
        allExecutorUrls: ['https://gitlab.com/gitlab-org/gitlab/-/jobs/456'],
        createdAt: expect.any(String),
        updatedAt: expect.any(String),
        agentFlowDefinition: 'Bug fixer',
        modelName: 'claude_sonnet_4_6',
        modelIdentifier: 'claude-sonnet-4-20250514',
        flowVersion: 'v1',
        aiCatalogItemPath: '/explore/ai-catalog/flows/1799',
        duoMessages: mockDuoMessages,
        project: mockGetAgentFlowResponse.data.duoWorkflowWorkflows.edges[0].node.project,
        canUpdateWorkflow: true,
        user: mockUser1,
        summary: '',
        workItem: null,
        mergeRequest: null,
        workItemLinks: mockWorkItemLinks,
        mergeRequestLinks: mockMergeRequestLinks,
        noteLinks: mockNoteLinks,
        pipelineLinks: mockPipelineLinks,
      });
    });
  });

  describe('when the session has no catalog item', () => {
    beforeEach(async () => {
      const [{ node }] = mockGetAgentFlowResponse.data.duoWorkflowWorkflows.edges;
      getAgentFlowHandler.mockResolvedValue({
        data: { duoWorkflowWorkflows: { edges: [{ node: { ...node, aiCatalogItem: null } }] } },
      });
      await createWrapper();
    });

    it('falls back to the humanized workflow definition without a link', () => {
      expect(findAgentFlowDetails().props()).toMatchObject({
        agentFlowDefinition: 'Software development',
        aiCatalogItemPath: '',
      });
    });
  });

  describe('Apollo queries', () => {
    describe('agentFlowEvents query', () => {
      describe('when loading', () => {
        beforeEach(() => {
          // A never-resolving promise keeps the query loading for the whole
          // test; a resolved one races Jest's hook microtask queue (see the
          // same pattern in panel/agent_session_inbox_spec.js).
          getAgentFlowHandler.mockReturnValue(new Promise(() => {}));
          createWrapper();
        });

        it('passes the loading state to the details component', () => {
          expect(findAgentFlowDetails().props().isLoading).toBe(true);
        });
      });

      describe('on successful response', () => {
        beforeEach(async () => {
          getAgentFlowHandler.mockResolvedValue(mockGetAgentFlowResponse);
          await createWrapper();
        });

        it('fetches workflow events data with correct variables', () => {
          expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);
          expect(getAgentFlowHandler).toHaveBeenCalledWith({
            workflowId: graphqlWorkflowId,
          });
        });

        it('does not show an error', () => {
          expect(createAlert).not.toHaveBeenCalled();
        });

        it('passes the loading state to the details component as false', () => {
          expect(findAgentFlowDetails().props().isLoading).toBe(false);
        });
      });

      describe('when agentFlowEvents query fails', () => {
        const errorMessage = 'Network error';

        beforeEach(async () => {
          getAgentFlowHandler.mockRejectedValue(new Error(errorMessage));
          await createWrapper();
        });

        it('calls createAlert with the error message', () => {
          expect(createAlert).toHaveBeenCalledWith({ message: errorMessage, captureError: true });
        });
      });

      describe('when error occurs without message', () => {
        beforeEach(async () => {
          getAgentFlowHandler.mockRejectedValue(new Error(''));
          await createWrapper();
        });

        it('calls createAlert with default error message', () => {
          expect(createAlert).toHaveBeenCalledWith({
            message: 'Something went wrong while fetching Agent Flows',
            captureError: true,
          });
        });
      });

      describe('polling', () => {
        beforeEach(async () => {
          jest.useFakeTimers();
          getAgentFlowHandler.mockResolvedValue(mockGetAgentFlowResponse);
          await createWrapper();
        });

        afterEach(() => {
          jest.useRealTimers();
        });

        it('polls after 10 seconds', async () => {
          expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);

          jest.advanceTimersByTime(3000);
          await waitForPromises();

          expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);

          jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
          await waitForPromises();

          expect(getAgentFlowHandler).toHaveBeenCalledTimes(2);

          jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
          await waitForPromises();

          expect(getAgentFlowHandler).toHaveBeenCalledTimes(3);
        });

        it.each(['FINISHED', 'STOPPED', 'FAILED'])(
          'stops polling once the workflow status reaches %s',
          async (status) => {
            const terminalResponse = {
              data: {
                duoWorkflowWorkflows: {
                  edges: [
                    {
                      node: {
                        ...mockGetAgentFlowResponse.data.duoWorkflowWorkflows.edges[0].node,
                        status,
                      },
                    },
                  ],
                },
              },
            };
            getAgentFlowHandler.mockResolvedValueOnce(terminalResponse);

            jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
            await waitForPromises();

            // Subsequent intervals should not trigger more requests.
            jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL * 5);
            await waitForPromises();

            expect(getAgentFlowHandler).toHaveBeenCalledTimes(2);
          },
        );
      });

      describe('when query errors', () => {
        let stopPollingSpy;

        const buildGraphQLError = (code) => {
          const err = new Error('some error');
          err.graphQLErrors = [{ extensions: { code } }];
          return err;
        };

        const mountWithError = async (err, provide = {}) => {
          getAgentFlowHandler.mockRejectedValue(err);
          const mountPromise = createWrapper({}, defaultMockRoute, provide);
          stopPollingSpy = jest.spyOn(wrapper.vm.$apollo.queries.agentFlow, 'stopPolling');
          await mountPromise;
        };

        beforeEach(() => {
          clearRouteState.mockClear();
        });

        it.each(['WORKFLOW_NOT_FOUND', 'NO_RESOURCE_PERMISSIONS'])(
          'stops polling and clears the saved side-panel route on %s',
          async (code) => {
            await mountWithError(buildGraphQLError(code), { isSidePanelView: true });

            expect(stopPollingSpy).toHaveBeenCalled();
            expect(clearRouteState).toHaveBeenCalledWith(
              'duo_agents_platform_last_route_side_panel',
            );
          },
        );

        it('keeps polling on transient errors so the view recovers when the network does', async () => {
          await mountWithError(new Error('Network error'));

          expect(stopPollingSpy).not.toHaveBeenCalled();
          expect(clearRouteState).not.toHaveBeenCalled();
        });

        it('does not stop polling or clear the saved route for unrelated error codes', async () => {
          await mountWithError(buildGraphQLError('SOME_OTHER_CODE'), { isSidePanelView: true });

          expect(stopPollingSpy).not.toHaveBeenCalled();
          expect(clearRouteState).not.toHaveBeenCalled();
        });

        it('stops polling but does not clear the saved route outside the side panel view', async () => {
          await mountWithError(buildGraphQLError('WORKFLOW_NOT_FOUND'), {
            isSidePanelView: false,
          });

          expect(stopPollingSpy).toHaveBeenCalled();
          expect(clearRouteState).not.toHaveBeenCalled();
        });
      });
    });
  });

  describe('pausing polling in hidden tabs', () => {
    let isDocumentHidden;

    const withFlag = { glFeatures: { dapSessionDetailsPolling: true } };

    const setDocumentHidden = (hidden) => {
      isDocumentHidden = hidden;
      document.dispatchEvent(new Event('visibilitychange'));
      return waitForPromises();
    };

    const advancePollingIntervals = async (count = 1) => {
      for (let i = 0; i < count; i += 1) {
        jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
        // eslint-disable-next-line no-await-in-loop
        await waitForPromises();
      }
    };

    const mockAgentFlowStatus = (status) => {
      const [{ node }] = mockGetAgentFlowResponse.data.duoWorkflowWorkflows.edges;
      getAgentFlowHandler.mockResolvedValue({
        data: { duoWorkflowWorkflows: { edges: [{ node: { ...node, status } }] } },
      });
    };

    const clearHandlerCalls = () => {
      getAgentFlowHandler.mockClear();
      getLinkedItemsHandler.mockClear();
    };

    beforeEach(() => {
      jest.useFakeTimers();
      isDocumentHidden = false;
      jest.spyOn(document, 'hidden', 'get').mockImplementation(() => isDocumentHidden);
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    describe('when the dapSessionDetailsPolling flag is enabled', () => {
      describe('when the tab is hidden', () => {
        beforeEach(async () => {
          await createWrapper({}, defaultMockRoute, withFlag);
          await setDocumentHidden(true);
          clearHandlerCalls();
        });

        it('stops polling the session and its linked items', async () => {
          await advancePollingIntervals(5);

          expect(getAgentFlowHandler).not.toHaveBeenCalled();
          expect(getLinkedItemsHandler).not.toHaveBeenCalled();
        });

        describe('when the tab is visible again', () => {
          beforeEach(async () => {
            await setDocumentHidden(false);
          });

          it('refetches the session and its linked items straight away', () => {
            expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);
            expect(getLinkedItemsHandler).toHaveBeenCalledTimes(1);
          });

          it('resumes polling', async () => {
            await advancePollingIntervals();

            expect(getAgentFlowHandler).toHaveBeenCalledTimes(2);
            expect(getLinkedItemsHandler).toHaveBeenCalledTimes(2);
          });
        });
      });

      describe('when the tab is hidden on load', () => {
        beforeEach(async () => {
          isDocumentHidden = true;
          await createWrapper({}, defaultMockRoute, withFlag);
          clearHandlerCalls();
        });

        it('does not poll', async () => {
          await advancePollingIntervals(5);

          expect(getAgentFlowHandler).not.toHaveBeenCalled();
          expect(getLinkedItemsHandler).not.toHaveBeenCalled();
        });
      });

      describe('when the session finishes while the tab is hidden', () => {
        beforeEach(async () => {
          await createWrapper({}, defaultMockRoute, withFlag);
          await setDocumentHidden(true);
          mockAgentFlowStatus(AGENT_PLATFORM_STATUS_FINISHED);
          await setDocumentHidden(false);
          clearHandlerCalls();
        });

        it('stops polling after refetching', async () => {
          await advancePollingIntervals(3);

          expect(getAgentFlowHandler).not.toHaveBeenCalled();
          expect(getLinkedItemsHandler).not.toHaveBeenCalled();
        });
      });

      describe('when the session has finished', () => {
        beforeEach(async () => {
          mockAgentFlowStatus(AGENT_PLATFORM_STATUS_FINISHED);
          await createWrapper({}, defaultMockRoute, withFlag);
        });

        describe('when the tab is hidden', () => {
          beforeEach(async () => {
            await setDocumentHidden(true);
          });

          describe('when the tab is visible again', () => {
            beforeEach(async () => {
              clearHandlerCalls();
              await setDocumentHidden(false);
            });

            it('does not refetch or resume polling', async () => {
              await advancePollingIntervals(5);

              expect(getAgentFlowHandler).not.toHaveBeenCalled();
              expect(getLinkedItemsHandler).not.toHaveBeenCalled();
            });
          });
        });
      });

      describe('when the session can no longer be found', () => {
        beforeEach(async () => {
          const error = new Error('Workflow not found');
          error.graphQLErrors = [{ extensions: { code: 'WORKFLOW_NOT_FOUND' } }];
          getAgentFlowHandler.mockRejectedValue(error);
          await createWrapper({}, defaultMockRoute, withFlag);
        });

        it('stops polling the linked items', async () => {
          clearHandlerCalls();
          await advancePollingIntervals(3);

          expect(getLinkedItemsHandler).not.toHaveBeenCalled();
        });

        describe('when the tab is hidden', () => {
          beforeEach(async () => {
            await setDocumentHidden(true);
            clearHandlerCalls();
          });

          it('stops polling the linked items', async () => {
            await advancePollingIntervals(3);

            expect(getLinkedItemsHandler).not.toHaveBeenCalled();
          });

          describe('when the tab is visible again', () => {
            beforeEach(async () => {
              await setDocumentHidden(false);
            });

            it('does not refetch or resume polling the session or its linked items', async () => {
              await advancePollingIntervals(5);

              expect(getAgentFlowHandler).not.toHaveBeenCalled();
              expect(getLinkedItemsHandler).not.toHaveBeenCalled();
            });
          });
        });
      });

      describe('when navigating to a new session while the tab is hidden', () => {
        beforeEach(async () => {
          const mockRoute = reactive({ params: { id: agentFlowId } });
          await createWrapper({}, mockRoute, withFlag);
          await setDocumentHidden(true);

          mockRoute.params = { id: '2' };
          await waitForPromises();
          clearHandlerCalls();
        });

        it('does not poll the new session', async () => {
          await advancePollingIntervals(3);

          expect(getAgentFlowHandler).not.toHaveBeenCalled();
          expect(getLinkedItemsHandler).not.toHaveBeenCalled();
        });

        describe('when the tab is visible again', () => {
          beforeEach(async () => {
            await setDocumentHidden(false);
          });

          it('refetches the new session', () => {
            expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);
            expect(getAgentFlowHandler).toHaveBeenCalledWith({
              workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, '2'),
            });
          });
        });
      });

      describe('when navigating to a new session after the previous one finished', () => {
        beforeEach(async () => {
          const mockRoute = reactive({ params: { id: agentFlowId } });
          mockAgentFlowStatus(AGENT_PLATFORM_STATUS_FINISHED);
          await createWrapper({}, mockRoute, withFlag);

          mockAgentFlowStatus(DUO_WORKFLOW_STATUS_RUNNING);
          mockRoute.params = { id: '2' };
          await waitForPromises();
        });

        describe('when the tab is hidden', () => {
          beforeEach(async () => {
            await setDocumentHidden(true);
            clearHandlerCalls();
          });

          it('stops polling', async () => {
            await advancePollingIntervals(3);

            expect(getAgentFlowHandler).not.toHaveBeenCalled();
          });

          describe('when the tab is visible again', () => {
            beforeEach(async () => {
              await setDocumentHidden(false);
            });

            it('refetches the new session', () => {
              expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);
              expect(getAgentFlowHandler).toHaveBeenCalledWith({
                workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, '2'),
              });
            });
          });
        });
      });

      describe('when the component is destroyed', () => {
        beforeEach(async () => {
          jest.spyOn(document, 'addEventListener');
          jest.spyOn(document, 'removeEventListener');
          await createWrapper({}, defaultMockRoute, withFlag);
          wrapper.destroy();
        });

        it('stops listening for visibility changes', () => {
          const [, onVisibilityChange] = document.addEventListener.mock.calls.find(
            ([event]) => event === 'visibilitychange',
          );

          expect(document.removeEventListener).toHaveBeenCalledWith(
            'visibilitychange',
            onVisibilityChange,
          );
        });
      });
    });

    describe('when the dapSessionDetailsPolling flag is disabled', () => {
      beforeEach(async () => {
        await createWrapper();
      });

      describe('when the tab is hidden', () => {
        beforeEach(async () => {
          await setDocumentHidden(true);
          clearHandlerCalls();
        });

        it('keeps polling the session and its linked items', async () => {
          await advancePollingIntervals();

          expect(getAgentFlowHandler).toHaveBeenCalledTimes(1);
          expect(getLinkedItemsHandler).toHaveBeenCalledTimes(1);
        });
      });
    });
  });

  describe('panel header state lifecycle', () => {
    it('updates the panel title and session status when the query resolves in the side panel', async () => {
      const setTitle = jest.spyOn(aiGraphql, 'setPanelTitle');
      const setStatus = jest.spyOn(aiGraphql, 'setAgentSessionStatus');

      await createWrapper({}, defaultMockRoute, { isSidePanelView: true });

      expect(setTitle).toHaveBeenCalledWith(
        mockGetAgentFlowResponse.data.duoWorkflowWorkflows.edges[0].node.title,
      );
      expect(setStatus).toHaveBeenCalledWith('RUNNING');
    });

    describe('when the flow has no title', () => {
      let setTitle;

      beforeEach(async () => {
        setTitle = jest.spyOn(aiGraphql, 'setPanelTitle');

        getAgentFlowHandler.mockResolvedValue({
          data: {
            duoWorkflowWorkflows: {
              edges: [
                {
                  node: {
                    ...mockGetAgentFlowResponse.data.duoWorkflowWorkflows.edges[0].node,
                    title: null,
                  },
                },
              ],
            },
          },
        });

        await createWrapper({}, defaultMockRoute, { isSidePanelView: true });
      });

      it('sets the panel title to the formatted agent definition', () => {
        expect(setTitle).toHaveBeenCalledWith('Software development');
      });
    });

    it('clears the panel title and session status on unmount in the side panel', async () => {
      const setTitle = jest.spyOn(aiGraphql, 'setPanelTitle');
      const setStatus = jest.spyOn(aiGraphql, 'setAgentSessionStatus');

      await createWrapper({}, defaultMockRoute, { isSidePanelView: true });

      setTitle.mockClear();
      setStatus.mockClear();

      wrapper.destroy();

      expect(setTitle).toHaveBeenCalledWith(null);
      expect(setStatus).toHaveBeenCalledWith(null);
    });

    it('does not clear the panel state on unmount outside the side panel', async () => {
      const setTitle = jest.spyOn(aiGraphql, 'setPanelTitle');
      const setStatus = jest.spyOn(aiGraphql, 'setAgentSessionStatus');

      await createWrapper();

      setTitle.mockClear();
      setStatus.mockClear();

      wrapper.destroy();

      expect(setTitle).not.toHaveBeenCalled();
      expect(setStatus).not.toHaveBeenCalled();
    });
  });

  describe('route parameter handling', () => {
    it('converts route id to GraphQL ID correctly', async () => {
      const customWorkflowId = '123';

      wrapper = createWrapper(
        {},
        {
          params: {
            id: customWorkflowId,
          },
        },
      );

      await waitForPromises();

      expect(getAgentFlowHandler).toHaveBeenCalledWith({
        workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, customWorkflowId),
      });
    });

    describe('when the route switches to another session', () => {
      beforeEach(async () => {
        // eslint-disable-next-line no-restricted-properties
        const mockRoute = Vue.observable({ params: { id: agentFlowId } });
        await createWrapper({}, mockRoute);

        getAgentFlowHandler.mockReturnValue(new Promise(() => {}));
        mockRoute.params = { id: '2' };
        await waitForPromises();
      });

      it('shows the loading state until the new session loads', () => {
        expect(findAgentFlowDetails().props('isLoading')).toBe(true);
      });
    });
  });

  describe('Cancel session functionality', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    describe('confirmation modal', () => {
      it('renders the cancel session confirmation modal', () => {
        expect(findCancelConfirmationModal().exists()).toBe(true);
        expect(findCancelConfirmationModal().props('visible')).toBe(false);
        expect(findCancelConfirmationModal().props('loading')).toBe(false);
      });

      it('shows modal when cancel-session event is emitted from AgentFlowDetails', async () => {
        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        expect(findCancelConfirmationModal().props('visible')).toBe(true);
      });

      it('hides modal when hide event is emitted', async () => {
        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        expect(findCancelConfirmationModal().props('visible')).toBe(true);

        findCancelConfirmationModal().vm.$emit('hide');
        await nextTick();

        expect(findCancelConfirmationModal().props('visible')).toBe(false);
      });
    });

    describe('session cancellation', () => {
      beforeEach(async () => {
        await createWrapper();
      });

      it('calls cancelWorkflow API when confirmed', async () => {
        cancelWorkflow.mockResolvedValue({});

        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        expect(findCancelConfirmationModal().props('visible')).toBe(true);

        findCancelConfirmationModal().vm.$emit('confirm');
        await waitForPromises();

        expect(cancelWorkflow).toHaveBeenCalledWith(agentFlowId);
        expect(findCancelConfirmationModal().props('visible')).toBe(false);
      });

      it('refetches the session so the status updates without waiting for the poll', async () => {
        cancelWorkflow.mockResolvedValue({});
        const callsBeforeCancel = getAgentFlowHandler.mock.calls.length;

        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        findCancelConfirmationModal().vm.$emit('confirm');
        await waitForPromises();

        expect(getAgentFlowHandler).toHaveBeenCalledTimes(callsBeforeCancel + 1);
      });

      it('keeps the session details visible while refetching', async () => {
        cancelWorkflow.mockResolvedValue({});
        getAgentFlowHandler.mockReturnValue(new Promise(() => {}));

        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        findCancelConfirmationModal().vm.$emit('confirm');
        await waitForPromises();

        expect(findAgentFlowDetails().props('isLoading')).toBe(false);
      });

      describe('when the refetch fails', () => {
        beforeEach(async () => {
          cancelWorkflow.mockResolvedValue({});
          getAgentFlowHandler.mockRejectedValue(new Error('Refetch failed'));

          findAgentFlowDetails().vm.$emit('cancel-session');
          await nextTick();

          findCancelConfirmationModal().vm.$emit('confirm');
          await waitForPromises();
        });

        it('shows the fetch error alert once', () => {
          expect(createAlert).toHaveBeenCalledTimes(2);
          expect(createAlert).toHaveBeenNthCalledWith(1, {
            message: 'Session has been canceled successfully.',
            variant: 'success',
          });
          expect(createAlert).toHaveBeenLastCalledWith({
            message: 'Refetch failed',
            captureError: true,
          });
        });
      });

      it('shows success alert on successful cancellation', async () => {
        cancelWorkflow.mockResolvedValue({});

        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        findCancelConfirmationModal().vm.$emit('confirm');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'Session has been canceled successfully.',
          variant: 'success',
        });
      });

      it('shows error alert on API failure', async () => {
        const errorMessage = 'Failed to cancel';
        const mockError = {
          response: {
            status: 422,
            data: { message: errorMessage },
          },
        };
        cancelWorkflow.mockRejectedValue(mockError);
        const callsBeforeCancel = getAgentFlowHandler.mock.calls.length;

        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        findCancelConfirmationModal().vm.$emit('confirm');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: errorMessage,
          captureError: true,
          error: mockError,
          variant: 'danger',
        });
        expect(getAgentFlowHandler).toHaveBeenCalledTimes(callsBeforeCancel);
      });

      it('shows loading state during cancellation', async () => {
        let resolveRequest;
        cancelWorkflow.mockImplementation(
          () =>
            new Promise((resolve) => {
              resolveRequest = resolve;
            }),
        );

        findAgentFlowDetails().vm.$emit('cancel-session');
        await nextTick();

        findCancelConfirmationModal().vm.$emit('confirm');
        await nextTick();

        expect(findCancelConfirmationModal().props('loading')).toBe(true);

        // Resolve the promise to clean up
        resolveRequest({});
        await waitForPromises();
      });
    });
  });

  describe('Retry session functionality', () => {
    beforeEach(async () => {
      await createWrapper();
    });

    it('passes the restart permission down to AgentFlowDetails', () => {
      expect(findAgentFlowDetails().props('canRestartWorkflow')).toBe(true);
    });

    describe('when the session is retried', () => {
      beforeEach(async () => {
        restartWorkflow.mockResolvedValue({ data: { id: 42 } });

        findAgentFlowDetails().vm.$emit('retry-session');
        await waitForPromises();
      });

      it('calls restartWorkflow', () => {
        expect(restartWorkflow).toHaveBeenCalledWith(agentFlowId);
      });

      it('navigates to the newly created session', () => {
        expect(routerPush).toHaveBeenCalledWith({
          name: AGENTS_PLATFORM_SHOW_ROUTE,
          params: { id: '42' },
        });
      });

      it('shows a success alert', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Session has been restarted successfully.',
          variant: 'success',
        });
      });
    });

    describe('when navigating to the new session fails', () => {
      beforeEach(async () => {
        restartWorkflow.mockResolvedValue({ data: { id: 42 } });
        routerPush.mockRejectedValue(new Error('navigation failed'));

        findAgentFlowDetails().vm.$emit('retry-session');
        await waitForPromises();
      });

      it('does not claim the retry failed', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Session restarted, but the new session could not be opened.',
          variant: 'warning',
        });
      });
    });

    describe('when the request fails', () => {
      const errorMessage = 'Workflow is already being restarted';

      beforeEach(async () => {
        restartWorkflow.mockRejectedValue({
          response: { status: 409, data: { message: errorMessage } },
        });

        findAgentFlowDetails().vm.$emit('retry-session');
        await waitForPromises();
      });

      it('shows the server error', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: errorMessage,
          captureError: true,
          error: expect.anything(),
          variant: 'danger',
        });
      });

      it('does not navigate', () => {
        expect(routerPush).not.toHaveBeenCalled();
      });

      it('clears the loading state so the button can be used again', () => {
        expect(findAgentFlowDetails().props('isRetrying')).toBe(false);
      });
    });

    describe('while the request is in flight', () => {
      let resolveRequest;

      beforeEach(async () => {
        restartWorkflow.mockImplementation(
          () =>
            new Promise((resolve) => {
              resolveRequest = resolve;
            }),
        );

        findAgentFlowDetails().vm.$emit('retry-session');
        await nextTick();
      });

      it('reports the loading state', () => {
        expect(findAgentFlowDetails().props('isRetrying')).toBe(true);
      });

      it('clears the loading state once the request resolves', async () => {
        resolveRequest({ data: { id: 42 } });
        await waitForPromises();

        expect(findAgentFlowDetails().props('isRetrying')).toBe(false);
      });
    });
  });
});
