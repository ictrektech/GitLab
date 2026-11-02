import waitForPromises from 'helpers/wait_for_promises';
import { runChatTurn, CHAT_TURN_OUTCOME } from 'ee/ai/duo_agentic_chat/services/chat_turn_run';
import { WorkflowStream } from 'ee/ai/duo_agentic_chat/websocket/workflow_stream';
import {
  DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
  DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
  DUO_WORKFLOW_STATUS_RUNNING,
  DUO_WORKFLOW_STATUS_FAILED,
  DUO_WORKFLOW_STATUS_FINISHED,
} from 'ee/ai/constants';

jest.mock('ee/ai/duo_agentic_chat/websocket/workflow_stream');

describe('runChatTurn', () => {
  let streamInstance;
  let subscribers;
  let disposeMocks;

  const namespaceId = 'gid://gitlab/Group/1';
  const workflowId = 'gid://gitlab/Ai::DuoWorkflows::Workflow/7';

  const startTurn = (options = {}) =>
    runChatTurn({ namespaceId, workflowId, text: 'How do I create a project?', ...options });

  const emit = (eventType, payload) => subscribers[eventType](payload);

  // The outcome of a turn that is not expected to settle: caught so the assertion is
  // "never called", rather than a promise the linter thinks is unhandled.
  const trackSettlement = (outcome) => {
    const settled = jest.fn();
    outcome.then(settled).catch(() => {});
    return settled;
  };

  const checkpointMessage = (status, checkpoint) => ({
    data: { newCheckpoint: { status, checkpoint } },
  });

  beforeEach(() => {
    subscribers = {};
    disposeMocks = [];
    streamInstance = {
      connect: jest.fn(),
      terminate: jest.fn(),
      subscribe: jest.fn((eventType, callback) => {
        subscribers[eventType] = callback;
        const dispose = jest.fn();
        disposeMocks.push(dispose);
        return { dispose };
      }),
    };
    WorkflowStream.mockImplementation(() => streamInstance);
  });

  it('opens a single stream and sends the prompt as the start request', () => {
    startTurn();

    expect(WorkflowStream).toHaveBeenCalledTimes(1);
    expect(streamInstance.connect).toHaveBeenCalledTimes(1);

    const [url, startRequest] = streamInstance.connect.mock.calls[0];

    expect(url).toContain('workflow_id=7');
    expect(url).toContain('namespace_id=1');
    expect(url).toContain('workflow_definition=chat');
    expect(startRequest.startRequest).toMatchObject({
      workflowID: '7',
      workflowDefinition: 'chat',
      goal: 'How do I create a project?',
    });
  });

  it.each([DUO_WORKFLOW_STATUS_INPUT_REQUIRED, DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED])(
    'settles as awaiting_user on %s',
    async (status) => {
      const { outcome } = startTurn();

      emit('open', {});
      emit('message', checkpointMessage(status));

      await expect(outcome).resolves.toMatchObject({
        type: CHAT_TURN_OUTCOME.AWAITING_USER,
        status,
        connectionOpened: true,
      });
    },
  );

  it('settles as run_ended with the last failure entry from the chat log', async () => {
    const { outcome } = startTurn();

    emit(
      'message',
      checkpointMessage(DUO_WORKFLOW_STATUS_FAILED, {
        channel_values: {
          ui_chat_log: [
            { status: 'success', content: 'earlier step' },
            { status: 'failure', content: 'model not found' },
          ],
        },
      }),
    );

    await expect(outcome).resolves.toMatchObject({
      type: CHAT_TURN_OUTCOME.RUN_ENDED,
      errorMessage: 'model not found',
    });
  });

  it('settles as run_ended with no message when the chat log holds no failure', async () => {
    const { outcome } = startTurn();

    emit('message', checkpointMessage(DUO_WORKFLOW_STATUS_FINISHED));

    await expect(outcome).resolves.toMatchObject({
      type: CHAT_TURN_OUTCOME.RUN_ENDED,
      errorMessage: null,
    });
  });

  it('keeps listening through non-terminal statuses', async () => {
    const { outcome } = startTurn();
    const settled = trackSettlement(outcome);

    emit('message', checkpointMessage(DUO_WORKFLOW_STATUS_RUNNING));
    emit('message', checkpointMessage(undefined));
    await waitForPromises();

    expect(settled).not.toHaveBeenCalled();
    expect(streamInstance.terminate).not.toHaveBeenCalled();
  });

  it('settles as disconnected, reporting whether the connection ever opened', async () => {
    const { outcome } = startTurn();

    emit('close', { code: 1006, reason: '', category: 'error' });

    await expect(outcome).resolves.toEqual({
      type: CHAT_TURN_OUTCOME.DISCONNECTED,
      connectionOpened: false,
      close: { code: 1006, reason: '', category: 'error' },
    });
  });

  it('settles as stream_error', async () => {
    const { outcome } = startTurn();

    emit('error', { message: 'decode failed' });

    await expect(outcome).resolves.toMatchObject({
      type: CHAT_TURN_OUTCOME.STREAM_ERROR,
      errorMessage: 'decode failed',
    });
  });

  it('settles as timed_out when nothing else settles the turn in time', async () => {
    jest.useFakeTimers();

    const { outcome } = startTurn({ timeoutMs: 100 });

    jest.runAllTimers();

    await expect(outcome).resolves.toMatchObject({
      type: CHAT_TURN_OUTCOME.TIMED_OUT,
      connectionOpened: false,
    });

    jest.useRealTimers();
  });

  it('never times out when no timeout is given', async () => {
    jest.useFakeTimers();

    const settled = trackSettlement(startTurn().outcome);

    jest.runAllTimers();
    await waitForPromises();

    expect(settled).not.toHaveBeenCalled();

    jest.useRealTimers();
  });

  it('tears the stream down once, on the first outcome', async () => {
    const { outcome } = startTurn({ timeoutMs: 100 });

    emit('message', checkpointMessage(DUO_WORKFLOW_STATUS_INPUT_REQUIRED));
    emit('close', { code: 1000, reason: '', category: 'normal' });

    await expect(outcome).resolves.toMatchObject({ type: CHAT_TURN_OUTCOME.AWAITING_USER });
    expect(streamInstance.terminate).toHaveBeenCalledTimes(1);
    disposeMocks.forEach((dispose) => expect(dispose).toHaveBeenCalledTimes(1));
  });

  describe('cancel', () => {
    it('tears the stream down', () => {
      startTurn().cancel();

      expect(streamInstance.terminate).toHaveBeenCalledTimes(1);
      disposeMocks.forEach((dispose) => expect(dispose).toHaveBeenCalledTimes(1));
    });

    it('leaves the outcome unsettled, and ignores later stream events', async () => {
      const { outcome, cancel } = startTurn();
      const settled = trackSettlement(outcome);

      cancel();
      emit('message', checkpointMessage(DUO_WORKFLOW_STATUS_INPUT_REQUIRED));
      await waitForPromises();

      expect(settled).not.toHaveBeenCalled();
    });

    it('is a no-op once the turn has settled', async () => {
      const { outcome, cancel } = startTurn();

      emit('message', checkpointMessage(DUO_WORKFLOW_STATUS_INPUT_REQUIRED));
      await outcome;
      cancel();

      expect(streamInstance.terminate).toHaveBeenCalledTimes(1);
    });
  });
});
