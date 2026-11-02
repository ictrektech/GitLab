import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { createMockSubscription } from 'mock-apollo-client';
import { GlAnimatedLoaderIcon, GlLink, GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import TodoChecklist from 'ee/ai/duo_agents_platform/components/common/todo_checklist.vue';
import MessageToolStartFlow from 'ee/ai/duo_agentic_chat/plugins/start_flow/components/message_tool_start_flow.vue';
import getWorkflowLatestCheckpointQuery from 'ee/ai/graphql/get_workflow_latest_checkpoint.query.graphql';
import getWorkflowStatusQuery from 'ee/ai/graphql/get_workflow_status.query.graphql';
import workflowActivityUpdatedSubscription from 'ee/ai/graphql/workflow_activity_updated.subscription.graphql';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { EventsTracker } from 'ee/ai/duo_agentic_chat/observability/events_tracker';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import {
  MOCK_START_FLOW_TOOL_MESSAGE,
  MOCK_LATEST_CHECKPOINT_WITH_TODO,
  MOCK_LATEST_CHECKPOINT,
  MOCK_LATEST_CHECKPOINT_WITH_GENERATED_TITLE,
  MOCK_LATEST_CHECKPOINT_FINISHED,
  MOCK_LATEST_CHECKPOINT_EMPTY,
  MOCK_LATEST_CHECKPOINT_FINISHED_WITH_TODO,
} from 'ee_jest/ai/duo_agentic_chat/components/mock_data';

jest.mock('ee/ai/duo_agentic_chat/observability/events_tracker');
jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

Vue.use(VueApollo);

const toStatusResponse = ({ data }) => {
  const { id, status, title, workflowDefinition, latestCheckpoint } =
    data.duoWorkflowWorkflows.nodes[0];

  return {
    data: {
      duoWorkflowWorkflows: {
        nodes: [
          {
            id,
            status,
            title,
            workflowDefinition,
            latestCheckpoint: { lastDuoMessage: latestCheckpoint.duoMessages.at(-1) ?? null },
          },
        ],
      },
    },
  };
};

const toEvent = ({ data }) => {
  const { status, latestCheckpoint } = data.duoWorkflowWorkflows.nodes[0];

  return {
    data: {
      workflowEventsUpdated: {
        workflowStatus: status,
        lastDuoMessage: latestCheckpoint.duoMessages.at(-1) ?? null,
      },
    },
  };
};

describe('MessageToolStartFlow', () => {
  let wrapper;
  let flowPlanHandler;
  let statusHandler;
  let eventsSubscription;
  let eventsSubscriptionHandler;

  const mockCheckpoint = (response) => {
    flowPlanHandler.mockResolvedValue(response);
    statusHandler.mockResolvedValue(toStatusResponse(response));
  };

  beforeEach(() => {
    flowPlanHandler = jest.fn();
    statusHandler = jest.fn();
    eventsSubscriptionHandler = jest.fn(() => {
      eventsSubscription = createMockSubscription();
      return eventsSubscription;
    });
    mockCheckpoint(MOCK_LATEST_CHECKPOINT);
  });

  const createComponent = (props = {}) => {
    const apolloProvider = createMockApollo();
    apolloProvider.defaultClient.setRequestHandler(
      getWorkflowLatestCheckpointQuery,
      flowPlanHandler,
    );
    apolloProvider.defaultClient.setRequestHandler(getWorkflowStatusQuery, statusHandler);
    apolloProvider.defaultClient.setRequestHandler(
      workflowActivityUpdatedSubscription,
      eventsSubscriptionHandler,
    );

    wrapper = shallowMountExtended(MessageToolStartFlow, {
      propsData: { message: MOCK_START_FLOW_TOOL_MESSAGE, ...props },
      apolloProvider,
    });
  };

  const createMessageWithToolResponse = (content) => ({
    ...MOCK_START_FLOW_TOOL_MESSAGE,
    tool_info: {
      ...MOCK_START_FLOW_TOOL_MESSAGE.tool_info,
      tool_response: {
        ...MOCK_START_FLOW_TOOL_MESSAGE.tool_info.tool_response,
        content,
      },
    },
  });

  const messageWithoutSessionUrl = () =>
    createMessageWithToolResponse(
      JSON.stringify({ status: 'started', workflow_id: 326, flow_name: 'fix_pipeline/v1' }),
    );
  const messageWithoutWorkflowId = () =>
    createMessageWithToolResponse(
      JSON.stringify({
        status: 'started',
        session_url: 'https://example.com/gitlab-duo/test/-/automate/agent-sessions/326',
        flow_name: 'fix_pipeline/v1',
      }),
    );

  const findLink = () => wrapper.findComponent(GlLink);
  const findStatusIcon = () => wrapper.findComponent(AgentStatusIcon);
  const findCard = () => wrapper.findByTestId('start-flow-message');
  const findLoadingIndicator = () => wrapper.findByTestId('start-flow-loading');
  const findTodoChecklist = () => wrapper.findComponent(TodoChecklist);
  const findLatestActivity = () => wrapper.findByTestId('latest-activity');
  const findLatestActivityDetail = () => wrapper.findByTestId('latest-activity-detail');
  const findLatestActivityToolName = () => wrapper.findByTestId('latest-activity-tool-name');
  const findAnimatedLoader = () => wrapper.findComponent(GlAnimatedLoaderIcon);

  describe('loading state', () => {
    it('shows a loading indicator while the query is in flight', () => {
      createComponent();

      expect(findLoadingIndicator().exists()).toBe(true);
      expect(findLoadingIndicator().findComponent(GlLoadingIcon).exists()).toBe(true);
      expect(findCard().exists()).toBe(false);
    });

    it('applies pill classes to the loading indicator', () => {
      createComponent();

      expect(findLoadingIndicator().classes()).toContain('gl-inline-flex');
    });

    it('hides the loading indicator once workflowStatus resolves', async () => {
      createComponent();
      await waitForPromises();

      expect(findLoadingIndicator().exists()).toBe(false);
      expect(findCard().exists()).toBe(true);
    });

    it('does not show a loading indicator when workflowId is absent', () => {
      createComponent({
        message: createMessageWithToolResponse(
          JSON.stringify({ status: 'started', flow_name: 'fix_pipeline/v1' }),
        ),
      });

      expect(findLoadingIndicator().exists()).toBe(false);
      expect(findCard().exists()).toBe(true);
    });
  });

  describe('session title', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('displays the flow name and ID while the title is still the workflow definition', () => {
      expect(findCard().text()).toContain('Fix pipeline/v1 #326');
    });
  });

  describe('when the session title has been generated', () => {
    beforeEach(async () => {
      mockCheckpoint(MOCK_LATEST_CHECKPOINT_WITH_GENERATED_TITLE);
      createComponent();
      await waitForPromises();
    });

    it('displays the generated title and ID', () => {
      expect(findCard().text()).toContain('Fix flaky pipeline spec #326');
    });
  });

  describe('status', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('displays the status returned by the query', () => {
      expect(findStatusIcon().props('status')).toBe('RUNNING');
    });

    it('displays the human-readable status', () => {
      expect(findStatusIcon().props('humanStatus')).toBe('running');
      expect(wrapper.text()).toContain('running');
    });
  });

  describe('accessibility', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('marks the status icon wrapper as aria-hidden', () => {
      expect(findStatusIcon().element.parentElement.getAttribute('aria-hidden')).toBe('true');
    });
  });

  describe('session link', () => {
    const sessionUrl = 'https://example.com/gitlab-duo/test/-/automate/agent-sessions/326';
    const clickLink = (event = {}) => {
      const clickEvent = { preventDefault: jest.fn(), ...event };
      findLink().vm.$emit('click', clickEvent);
      return clickEvent;
    };

    beforeEach(() => {
      jest.spyOn(eventHub, '$emit');
    });

    describe('when the tool response has a session_url', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('renders the card as a link to the session page', () => {
        expect(findCard().exists()).toBe(true);
        expect(findLink().exists()).toBe(true);
        expect(findLink().attributes('href')).toBe(sessionUrl);
        expect(findLink().attributes('type')).toBeUndefined();
        expect(findCard().text()).toContain('running');
      });

      it('keeps the card text colour and removes the link underline', () => {
        expect(findCard().classes()).toEqual(
          expect.arrayContaining(['!gl-text-default', '!gl-no-underline', 'gl-flex-col']),
        );
      });

      describe('when the link is clicked without a modifier key', () => {
        let clickEvent;

        beforeEach(() => {
          clickEvent = clickLink();
        });

        it('prevents the navigation and opens the session in the panel', () => {
          expect(clickEvent.preventDefault).toHaveBeenCalledTimes(1);
          expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 326 });
        });

        it('tracks the click via EventsTracker.trackClickThroughFlowWidget', () => {
          expect(EventsTracker.trackClickThroughFlowWidget).toHaveBeenCalledWith({
            toolName: 'start_flow',
          });
        });
      });

      describe.each(['metaKey', 'ctrlKey', 'shiftKey'])(
        'when the link is clicked with %s',
        (key) => {
          let clickEvent;

          beforeEach(() => {
            clickEvent = clickLink({ [key]: true });
          });

          it('tracks the click but leaves the navigation to the browser', () => {
            expect(EventsTracker.trackClickThroughFlowWidget).toHaveBeenCalledWith({
              toolName: 'start_flow',
            });
            expect(clickEvent.preventDefault).not.toHaveBeenCalled();
            expect(eventHub.$emit).not.toHaveBeenCalledWith(SHOW_SESSION, expect.anything());
          });
        },
      );
    });

    describe('when the tool response has a session_url but no workflow_id', () => {
      let clickEvent;

      beforeEach(async () => {
        createComponent({ message: messageWithoutWorkflowId() });
        await waitForPromises();
        clickEvent = clickLink();
      });

      it('renders a link and lets the browser follow it', () => {
        expect(findLink().attributes('href')).toBe(sessionUrl);
        expect(clickEvent.preventDefault).not.toHaveBeenCalled();
        expect(eventHub.$emit).not.toHaveBeenCalledWith(SHOW_SESSION, expect.anything());
      });
    });

    describe('when the tool response has no session_url', () => {
      beforeEach(async () => {
        createComponent({ message: messageWithoutSessionUrl() });
        await waitForPromises();
      });

      it('renders the card as a button without a link', () => {
        expect(findLink().exists()).toBe(false);
        expect(findCard().element.tagName).toBe('BUTTON');
        expect(findCard().attributes('type')).toBe('button');
        expect(findCard().attributes('href')).toBeUndefined();
      });

      it('does not apply the link-only classes', () => {
        expect(findCard().classes()).not.toContain('!gl-text-default');
        expect(findCard().classes()).not.toContain('!gl-no-underline');
      });

      it('opens the session in the panel and tracks the click on a plain click', async () => {
        await findCard().trigger('click');

        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 326 });
        expect(EventsTracker.trackClickThroughFlowWidget).toHaveBeenCalledWith({
          toolName: 'start_flow',
        });
      });

      it('opens the session in the panel and tracks the click on a modifier click', async () => {
        await findCard().trigger('click', { metaKey: true });

        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 326 });
        expect(EventsTracker.trackClickThroughFlowWidget).toHaveBeenCalledWith({
          toolName: 'start_flow',
        });
      });
    });
  });

  describe('polling', () => {
    it('displays the status returned by the query', async () => {
      createComponent();
      await waitForPromises();

      expect(findStatusIcon().props('status')).toBe('RUNNING');
      expect(findStatusIcon().props('humanStatus')).toBe('running');
    });

    describe('when a terminal status is reached', () => {
      beforeEach(async () => {
        mockCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED);

        createComponent();
        await waitForPromises();
      });

      it('displays the terminal status', () => {
        expect(findStatusIcon().props('status')).toBe('FINISHED');
        expect(findStatusIcon().props('humanStatus')).toBe('finished');
      });
    });
  });

  describe('plan rendering', () => {
    const expectedToolInfo = {
      name: 'todo_write',
      args: {
        todos: [
          { status: 'completed', description: 'Read pipeline logs' },
          { status: 'in_progress', description: 'Identify failing job' },
          { status: 'pending', description: 'Apply fix' },
        ],
      },
    };

    it('fetches the latest checkpoint using the workflow GraphQL ID', async () => {
      createComponent();
      await waitForPromises();

      expect(flowPlanHandler).toHaveBeenCalledWith({
        workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, 326),
      });
    });

    describe('when the latest checkpoint has no todo_write message', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('does not render the plan', () => {
        expect(findTodoChecklist().exists()).toBe(false);
      });

      it('switches to the expanded card layout', () => {
        expect(findCard().classes()).toContain('gl-flex-col');
        expect(findCard().classes()).not.toContain('gl-inline-flex');
      });

      it('shows the activity title, tool name and content with an animated loader', () => {
        expect(findLatestActivity().text()).toContain('Read file');
        expect(findLatestActivityToolName().text()).toBe('read_file');
        expect(findLatestActivityDetail().text()).toContain('Reading file');
        expect(findAnimatedLoader().exists()).toBe(true);
      });
    });

    describe('when the session has no messages yet', () => {
      beforeEach(async () => {
        mockCheckpoint(MOCK_LATEST_CHECKPOINT_EMPTY);

        createComponent();
        await waitForPromises();
      });

      it('falls back to the starting message with no detail', () => {
        expect(findLatestActivity().text()).toBe('Starting the session. Please wait');
        expect(findLatestActivityDetail().exists()).toBe(false);
        expect(findAnimatedLoader().exists()).toBe(true);
      });
    });

    describe('when a todo_write message is present', () => {
      beforeEach(async () => {
        mockCheckpoint(MOCK_LATEST_CHECKPOINT_WITH_TODO);

        createComponent();
        await waitForPromises();
      });

      it('renders TodoChecklist with the parsed tool_info', () => {
        expect(findTodoChecklist().exists()).toBe(true);
        expect(findTodoChecklist().props('toolInfo')).toEqual(expectedToolInfo);
      });

      it('switches to the expanded card layout', () => {
        expect(findCard().classes()).toContain('gl-flex-col');
        expect(findCard().classes()).not.toContain('gl-inline-flex');
      });

      it('passes flowFinished as false while the flow is running', () => {
        expect(findTodoChecklist().props('flowFinished')).toBe(false);
      });
    });

    describe('when the flow is terminal and a plan is present', () => {
      beforeEach(async () => {
        mockCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED_WITH_TODO);

        createComponent();
        await waitForPromises();
      });

      it('passes flowFinished as true once the flow is terminal', () => {
        expect(findTodoChecklist().exists()).toBe(true);
        expect(findTodoChecklist().props('flowFinished')).toBe(true);
      });
    });

    describe('when workflowId is absent', () => {
      beforeEach(async () => {
        createComponent({
          message: createMessageWithToolResponse(
            JSON.stringify({ status: 'started', flow_name: 'fix_pipeline/v1' }),
          ),
        });
        await waitForPromises();
      });

      it('does not fetch the status or the plan', () => {
        expect(statusHandler).not.toHaveBeenCalled();
        expect(flowPlanHandler).not.toHaveBeenCalled();
      });

      it('does not subscribe to workflow events', () => {
        expect(eventsSubscriptionHandler).not.toHaveBeenCalled();
      });

      it('displays the flow name without an ID', () => {
        expect(findCard().text()).toContain('Fix pipeline/v1');
        expect(findCard().text()).not.toContain('#');
      });
    });

    describe('when a terminal status is reached', () => {
      beforeEach(async () => {
        mockCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED);

        createComponent();
        await waitForPromises();
      });

      it('does not show the latest activity', () => {
        expect(findLatestActivity().exists()).toBe(false);
      });

      it('keeps the pill layout', () => {
        expect(findCard().classes()).toContain('gl-inline-flex');
        expect(findCard().classes()).not.toContain('gl-flex-col');
      });
    });

    describe('when the latest polled message is a todo_write', () => {
      beforeEach(async () => {
        flowPlanHandler.mockResolvedValue(MOCK_LATEST_CHECKPOINT);
        statusHandler.mockResolvedValue(toStatusResponse(MOCK_LATEST_CHECKPOINT_WITH_TODO));

        createComponent();
        await waitForPromises();
      });

      it('renders the plan from the polled message', () => {
        expect(findTodoChecklist().props('toolInfo')).toEqual(expectedToolInfo);
      });
    });

    describe('status polling lifecycle', () => {
      const advancePoll = async (ms = 60000) => {
        jest.advanceTimersByTime(ms);
        await waitForPromises();
      };

      describe('while the flow is running', () => {
        beforeEach(async () => {
          createComponent();
          await waitForPromises();
          await advancePoll();
        });

        it('polls only the status query', () => {
          expect(statusHandler).toHaveBeenCalledTimes(2);
          expect(flowPlanHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('when a status poll reports a terminal status', () => {
        beforeEach(async () => {
          createComponent();
          await waitForPromises();

          statusHandler.mockResolvedValue(toStatusResponse(MOCK_LATEST_CHECKPOINT_FINISHED));
          await advancePoll();
        });

        it('reads the full checkpoint again', () => {
          expect(flowPlanHandler).toHaveBeenCalledTimes(2);
        });

        it('stops polling', async () => {
          await advancePoll();

          expect(statusHandler).toHaveBeenCalledTimes(2);
        });
      });

      describe('when the flow has already finished on load', () => {
        beforeEach(async () => {
          mockCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED);

          createComponent();
          await waitForPromises();
          await advancePoll();
        });

        it('does not poll', () => {
          expect(statusHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('when the document visibility changes', () => {
        const setHidden = async (hidden) => {
          Object.defineProperty(document, 'hidden', { configurable: true, value: hidden });
          document.dispatchEvent(new Event('visibilitychange'));
          // Lets the pollInterval watcher apply the change before timers advance.
          await nextTick();
        };

        afterEach(() => {
          delete document.hidden;
        });

        describe('when the tab is hidden', () => {
          beforeEach(async () => {
            createComponent();
            await waitForPromises();

            await setHidden(true);
            await advancePoll();
            await advancePoll();
          });

          it('sends no status requests', () => {
            expect(statusHandler).toHaveBeenCalledTimes(1);
          });

          describe('when the tab is visible again', () => {
            beforeEach(async () => {
              await setHidden(false);
              await waitForPromises();
            });

            it('refetches the status', () => {
              expect(statusHandler).toHaveBeenCalledTimes(2);
            });

            it('resumes polling', async () => {
              await advancePoll();

              expect(statusHandler).toHaveBeenCalledTimes(3);
            });
          });
        });

        describe('when mounted in a hidden tab', () => {
          beforeEach(async () => {
            Object.defineProperty(document, 'hidden', { configurable: true, value: true });

            createComponent();
            await waitForPromises();
            await advancePoll();
          });

          it('does not poll', () => {
            expect(statusHandler).toHaveBeenCalledTimes(1);
          });
        });
      });

      describe('when the websocket reconnects', () => {
        const reconnect = async () => {
          document.dispatchEvent(new CustomEvent('actioncable:reconnected'));
          await waitForPromises();
        };

        describe('while the flow is running', () => {
          beforeEach(async () => {
            createComponent();
            await waitForPromises();
            await reconnect();
          });

          it('refetches the status without waiting for the next poll', () => {
            expect(statusHandler).toHaveBeenCalledTimes(2);
          });
        });

        describe('after the flow has finished', () => {
          beforeEach(async () => {
            mockCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED);

            createComponent();
            await waitForPromises();
            await reconnect();
          });

          it('does not refetch the status', () => {
            expect(statusHandler).toHaveBeenCalledTimes(1);
          });
        });
      });

      describe('when destroyed', () => {
        const DOCUMENT_EVENTS = ['visibilitychange', 'actioncable:reconnected'];
        let addedListeners;
        let removeEventListenerSpy;

        beforeEach(() => {
          const addEventListenerSpy = jest.spyOn(document, 'addEventListener');
          removeEventListenerSpy = jest.spyOn(document, 'removeEventListener');

          createComponent();
          addedListeners = addEventListenerSpy.mock.calls.filter(([type]) =>
            DOCUMENT_EVENTS.includes(type),
          );
          wrapper.destroy();
        });

        it('removes the document listeners it added', () => {
          expect(addedListeners).toHaveLength(DOCUMENT_EVENTS.length);
          addedListeners.forEach((args) => {
            expect(removeEventListenerSpy).toHaveBeenCalledWith(...args);
          });
        });
      });

      describe('when the workflow is not found', () => {
        beforeEach(async () => {
          statusHandler.mockResolvedValue({ data: { duoWorkflowWorkflows: { nodes: [] } } });

          createComponent();
          await waitForPromises();
          await advancePoll();
        });

        it('reads the full checkpoint only once', () => {
          expect(statusHandler).toHaveBeenCalledTimes(2);
          expect(flowPlanHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('when the full checkpoint resolves after a newer polled plan', () => {
        beforeEach(async () => {
          let resolveCheckpoint;
          flowPlanHandler.mockReturnValue(
            new Promise((resolve) => {
              resolveCheckpoint = resolve;
            }),
          );

          createComponent();
          await waitForPromises();

          statusHandler.mockResolvedValue(toStatusResponse(MOCK_LATEST_CHECKPOINT_WITH_TODO));
          await advancePoll();

          resolveCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED_WITH_TODO);
          await waitForPromises();
        });

        it('keeps the newer plan', () => {
          expect(findTodoChecklist().props('toolInfo')).toEqual(expectedToolInfo);
        });
      });

      describe('when the first full checkpoint read fails', () => {
        beforeEach(async () => {
          flowPlanHandler
            .mockRejectedValueOnce(new Error('Network error'))
            .mockResolvedValue(MOCK_LATEST_CHECKPOINT_WITH_TODO);

          createComponent();
          await waitForPromises();
        });

        it('reports the failure', () => {
          expect(captureExceptionForDuoChat).toHaveBeenCalledWith(expect.any(Error));
          expect(findTodoChecklist().exists()).toBe(false);
        });

        it('retries it on the next poll', async () => {
          await advancePoll();

          expect(flowPlanHandler).toHaveBeenCalledTimes(2);
          expect(findTodoChecklist().props('toolInfo')).toEqual(expectedToolInfo);
        });
      });

      describe('when the final full checkpoint read fails', () => {
        beforeEach(() => {
          statusHandler.mockResolvedValue(toStatusResponse(MOCK_LATEST_CHECKPOINT_FINISHED));
        });

        it('retries it once', async () => {
          flowPlanHandler
            .mockRejectedValueOnce(new Error('Network error'))
            .mockResolvedValue(MOCK_LATEST_CHECKPOINT_FINISHED_WITH_TODO);

          createComponent();
          await waitForPromises();

          expect(flowPlanHandler).toHaveBeenCalledTimes(2);
          expect(findTodoChecklist().exists()).toBe(true);
        });

        it('does not retry it more than once', async () => {
          flowPlanHandler.mockRejectedValue(new Error('Network error'));

          createComponent();
          await waitForPromises();

          expect(flowPlanHandler).toHaveBeenCalledTimes(2);
          expect(captureExceptionForDuoChat).toHaveBeenCalledTimes(2);
        });
      });
    });

    describe('workflow events subscription', () => {
      const pushEvent = async (response) => {
        eventsSubscription.next(toEvent(response));
        await waitForPromises();
      };

      describe('before the first status loads', () => {
        beforeEach(() => {
          statusHandler.mockReturnValue(new Promise(() => {}));
          createComponent();
        });

        it('does not subscribe', () => {
          expect(eventsSubscriptionHandler).not.toHaveBeenCalled();
        });
      });

      describe('when the flow has already finished on load', () => {
        beforeEach(async () => {
          mockCheckpoint(MOCK_LATEST_CHECKPOINT_FINISHED);

          createComponent();
          await waitForPromises();
        });

        it('does not subscribe', () => {
          expect(eventsSubscriptionHandler).not.toHaveBeenCalled();
        });
      });

      describe('while the flow is running', () => {
        beforeEach(async () => {
          createComponent();
          await waitForPromises();
        });

        it('subscribes using the workflow GraphQL ID', () => {
          expect(eventsSubscriptionHandler).toHaveBeenCalledWith({
            workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, 326),
          });
        });

        it('updates the status and the latest activity from an event', async () => {
          await pushEvent({
            data: {
              duoWorkflowWorkflows: {
                nodes: [
                  {
                    ...MOCK_LATEST_CHECKPOINT.data.duoWorkflowWorkflows.nodes[0],
                    status: 'INPUT_REQUIRED',
                  },
                ],
              },
            },
          });

          expect(findStatusIcon().props('status')).toBe('INPUT_REQUIRED');
          expect(findLatestActivityToolName().text()).toBe('read_file');
        });

        it('renders the plan from an event that carries a todo_write', async () => {
          await pushEvent(MOCK_LATEST_CHECKPOINT_WITH_TODO);

          expect(findTodoChecklist().props('toolInfo')).toEqual(expectedToolInfo);
          expect(flowPlanHandler).toHaveBeenCalledTimes(1);
        });

        describe('when an event carries no message', () => {
          beforeEach(async () => {
            eventsSubscription.next({
              data: { workflowEventsUpdated: { workflowStatus: 'RUNNING', lastDuoMessage: null } },
            });
            await waitForPromises();
          });

          it('keeps the latest activity', () => {
            expect(findLatestActivityToolName().text()).toBe('read_file');
          });
        });

        describe('when an event reports a terminal status', () => {
          beforeEach(async () => {
            await pushEvent(MOCK_LATEST_CHECKPOINT_FINISHED_WITH_TODO);
          });

          it('reads the full checkpoint once more', () => {
            expect(flowPlanHandler).toHaveBeenCalledTimes(2);
            expect(findTodoChecklist().props('flowFinished')).toBe(true);
          });

          it('stops polling', async () => {
            jest.advanceTimersByTime(60000);
            await waitForPromises();

            expect(statusHandler).toHaveBeenCalledTimes(1);
          });

          it('unsubscribes from workflow events', () => {
            // Apollo closes the underlying link subscription on the next tick.
            jest.advanceTimersByTime(0);

            expect(eventsSubscription.closed).toBe(true);
          });
        });

        describe('when a poll result arrives after a terminal event', () => {
          beforeEach(async () => {
            let resolvePoll;
            statusHandler.mockReturnValue(
              new Promise((resolve) => {
                resolvePoll = resolve;
              }),
            );
            jest.advanceTimersByTime(60000);

            await pushEvent(MOCK_LATEST_CHECKPOINT_FINISHED);
            resolvePoll(toStatusResponse(MOCK_LATEST_CHECKPOINT));
            await waitForPromises();
          });

          it('keeps the terminal status', () => {
            expect(findStatusIcon().props('status')).toBe('FINISHED');
          });
        });

        describe('when the subscription fails', () => {
          const error = new Error('Subscription failed');

          beforeEach(async () => {
            eventsSubscription.error(error);
            await waitForPromises();
          });

          it('reports the error', () => {
            expect(captureExceptionForDuoChat).toHaveBeenCalledWith(error);
          });

          it('falls back to faster polling', async () => {
            jest.advanceTimersByTime(10000);
            await waitForPromises();

            expect(statusHandler).toHaveBeenCalledTimes(2);
          });

          it('leaves no subscription open', () => {
            jest.advanceTimersByTime(0);

            expect(eventsSubscription.closed).toBe(true);
          });
        });
      });
    });
  });
});
