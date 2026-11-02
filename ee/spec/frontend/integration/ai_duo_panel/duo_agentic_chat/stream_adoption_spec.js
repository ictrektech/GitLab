import { waitFor } from '@testing-library/vue';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import {
  conversationText,
  getConfiguredAgents,
  getUserWorkflowsTwoThreads,
  getWorkflowLatestCheckpointFirstThread,
  getWorkflowLatestCheckpointSecondThread,
  userWorkflowsVariants,
  workflowLatestCheckpointVariants,
  installDuoAIPanelHandlers,
} from '../test_support/api_handlers';
import {
  buildChatConfiguration,
  findAgentItem,
  findChatMessages,
  findEmptyState,
  findHistoryToggle,
  findSubmitButton,
  findThreadBoxWithText,
  findThreadBoxes,
  mountAISidebar,
  openAgentDropdown,
  openHistoryTab,
  sendPrompt,
  setupDuoChatTest,
  teardownDuoChatTest,
} from '../test_support/test_setup';
import {
  agentLogEntry,
  getCloseCount,
  getSockets,
  pushCheckpoint,
  userLogEntry,
  waitForSocket,
} from '../test_support/websocket_mock';

// Adoption used to key off connection status alone, so every history navigation
// had to close the socket first -- which Workhorse turns into stopWorkflow,
// killing the reply the user was waiting on (the INC-13926 reproduction).

const OLDER_CONVERSATION = getWorkflowLatestCheckpointFirstThread;
const NEWER_CONVERSATION = getWorkflowLatestCheckpointSecondThread;

const { question: OLDER_QUESTION, answer: OLDER_ANSWER } = conversationText(OLDER_CONVERSATION);
const { question: NEWER_QUESTION, answer: NEWER_ANSWER } = conversationText(NEWER_CONVERSATION);

const FOLLOW_UP = 'follow-up question';
const FOLLOW_UP_ANSWER = 'follow-up answer';

// The streamed checkpoints must repeat the hydrated conversation with the same
// message ids, the way the real service replays the full ui_chat_log, so the
// client's dedup marker lines up with what hydration loaded.
const hydratedLog = () =>
  OLDER_CONVERSATION.messages().map(({ messageId, content, role }) =>
    role === 'user'
      ? userLogEntry({ id: messageId, content })
      : agentLogEntry({ id: messageId, content }),
  );

const midTurnLog = () => [
  ...hydratedLog(),
  userLogEntry({ id: 'followup-user', content: FOLLOW_UP }),
];

const finishedLog = () => [
  ...midTurnLog(),
  agentLogEntry({ id: 'followup-agent', content: FOLLOW_UP_ANSWER }),
];

describe('Duo Agentic Chat | an in-flight turn survives history navigation', () => {
  const openHistoryAndWaitForThreads = async () => {
    openHistoryTab();

    await waitFor(() => {
      expect(findThreadBoxes()).toHaveLength(getUserWorkflowsTwoThreads.threads().length);
    });
  };

  const openThread = async (title, answer) => {
    findThreadBoxWithText(title).click();

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(answer);
    });
  };

  // Hydrates the older thread and leaves a reply to it streaming: the follow-up
  // opened a socket, the service acknowledged the turn with a RUNNING
  // checkpoint, and no INPUT_REQUIRED has arrived yet.
  const startStreamingTurnOnOlderThread = async () => {
    setQueryVariant(userWorkflowsVariants).twoThreads();
    setQueryVariant(workflowLatestCheckpointVariants).firstThread();

    mountAISidebar({ chatConfiguration: buildChatConfiguration() });

    await waitFor(() => {
      expect(findHistoryToggle()).not.toBe(null);
    });

    await openHistoryAndWaitForThreads();
    await openThread(OLDER_QUESTION, OLDER_ANSWER);

    await waitFor(() => {
      expect(findSubmitButton().disabled).toBe(false);
    });

    sendPrompt(FOLLOW_UP);
    await waitForSocket();
    await pushCheckpoint(midTurnLog(), { status: 'RUNNING', goal: OLDER_QUESTION });

    expect(getSockets()).toHaveLength(1);
    expect(getCloseCount()).toBe(0);
  };

  beforeEach(async () => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
    await startStreamingTurnOnOlderThread();
  });

  afterEach(() => teardownDuoChatTest());

  it('does not close the socket when the user opens a blank chat', async () => {
    await openHistoryAndWaitForThreads();

    // The rail's new-chat control routes to the new-chat route the same way the
    // history view's own button does. The default selection is the first
    // foundational agent, so any configured one re-routes.
    openAgentDropdown();

    const agentItem = await waitForElement(() =>
      findAgentItem(getConfiguredAgents.agents()[0].item.id),
    );
    agentItem.click();

    await waitFor(() => {
      expect(findEmptyState()).not.toBe(null);
    });

    // The turn keeps running server-side: nothing closed the socket and no
    // replacement socket was opened.
    expect(getCloseCount()).toBe(0);
    expect(getSockets()).toHaveLength(1);
  });

  it('does not close the socket on a round trip through another thread', async () => {
    await openHistoryAndWaitForThreads();

    setQueryVariant(workflowLatestCheckpointVariants).secondThread();
    await openThread(NEWER_QUESTION, NEWER_ANSWER);

    expect(getText(findChatMessages())).not.toContain(OLDER_ANSWER);
    expect(getCloseCount()).toBe(0);
    expect(getSockets()).toHaveLength(1);

    // Back on the streaming thread the socket is its own again, so the
    // buffered follow-up replays and the turn finishes on that same socket.
    await openHistoryAndWaitForThreads();
    setQueryVariant(workflowLatestCheckpointVariants).firstThread();
    await openThread(OLDER_QUESTION, OLDER_ANSWER);

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FOLLOW_UP);
    });

    await pushCheckpoint(finishedLog(), { goal: OLDER_QUESTION });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FOLLOW_UP_ANSWER);
    });

    expect(getCloseCount()).toBe(0);
    expect(getSockets()).toHaveLength(1);
  });

  // Hydration reconnects a thread whose checkpoint says RUNNING, and
  // reconnecting means closing whatever socket is open. Opening such a thread
  // is not the user asking for that, so the other thread's turn must survive.
  it('does not reconnect for a second running thread, so the first turn survives', async () => {
    await openHistoryAndWaitForThreads();

    setQueryVariant(workflowLatestCheckpointVariants).secondThreadRunning();
    await openThread(NEWER_QUESTION, NEWER_ANSWER);

    expect(getCloseCount()).toBe(0);
    expect(getSockets()).toHaveLength(1);

    // And the first thread's own turn still finishes on that socket.
    await openHistoryAndWaitForThreads();
    setQueryVariant(workflowLatestCheckpointVariants).firstThread();
    await openThread(OLDER_QUESTION, OLDER_ANSWER);

    await pushCheckpoint(finishedLog(), { goal: OLDER_QUESTION });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FOLLOW_UP_ANSWER);
    });

    expect(getCloseCount()).toBe(0);
  });

  it('adopts the still-open socket and resumes live chunks when the user returns to the streaming thread', async () => {
    await openHistoryAndWaitForThreads();
    await openThread(OLDER_QUESTION, OLDER_ANSWER);

    // The buffered mid-turn checkpoint is replayed on adoption, so the
    // follow-up the user sent before navigating away is already back.
    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FOLLOW_UP);
    });

    // The turn then finishes on the same socket -- no reconnect, no close.
    await pushCheckpoint(finishedLog(), { goal: OLDER_QUESTION });

    await waitFor(() => {
      expect(getText(findChatMessages())).toContain(FOLLOW_UP_ANSWER);
    });

    expect(getCloseCount()).toBe(0);
    expect(getSockets()).toHaveLength(1);
  });

  it('stops the in-flight turn only when the user starts a turn of their own elsewhere', async () => {
    await openHistoryAndWaitForThreads();

    setQueryVariant(workflowLatestCheckpointVariants).secondThread();
    await openThread(NEWER_QUESTION, NEWER_ANSWER);

    await waitFor(() => {
      expect(findSubmitButton().disabled).toBe(false);
    });

    // A user-initiated turn on another thread is the one legitimate place the
    // previous socket may be closed: the single-socket stream reconnects for
    // the new workflow.
    sendPrompt('a question for the other thread');

    await waitFor(() => {
      expect(getCloseCount()).toBe(1);
    });

    await waitFor(() => {
      expect(getSockets()).toHaveLength(2);
    });
  });
});
