import { parseGid } from '~/graphql_shared/utils';
import {
  DUO_WORKFLOW_CHAT_DEFINITION,
  DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
  DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
  DUO_WORKFLOW_STATUS_FINISHED,
  DUO_WORKFLOW_STATUS_FAILED,
  DUO_WORKFLOW_STATUS_STOPPED,
} from 'ee/ai/constants';
import { WorkflowStream } from '../websocket/workflow_stream';
import { buildWebsocketUrl, buildStartRequest } from '../websocket/workflow_utils';
import { createUserPrompt } from './user_prompt';

/**
 * How a chat turn settled. Callers decide what each one means for them; this
 * module only reports what the run did.
 */
export const CHAT_TURN_OUTCOME = Object.freeze({
  // The agent answered and handed the turn back to the user.
  AWAITING_USER: 'awaiting_user',
  // The run reached a terminal status without ever asking the user anything.
  RUN_ENDED: 'run_ended',
  DISCONNECTED: 'disconnected',
  STREAM_ERROR: 'stream_error',
  TIMED_OUT: 'timed_out',
});

const AWAITING_USER_STATUSES = [
  DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
  DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
];

const ENDED_STATUSES = [
  DUO_WORKFLOW_STATUS_FINISHED,
  DUO_WORKFLOW_STATUS_FAILED,
  DUO_WORKFLOW_STATUS_STOPPED,
];

// Any other status (RUNNING, PLAN_APPROVAL_REQUIRED) is mid-run: keep listening.
function outcomeForStatus(status) {
  if (AWAITING_USER_STATUSES.includes(status)) return CHAT_TURN_OUTCOME.AWAITING_USER;
  if (ENDED_STATUSES.includes(status)) return CHAT_TURN_OUTCOME.RUN_ENDED;
  return null;
}

function lastFailureMessage(checkpoint) {
  const uiChatLog = checkpoint?.channel_values?.ui_chat_log ?? [];

  // Reversed so we grab the most recent failure, not the first one in the run.
  return [...uiChatLog].reverse().find((entry) => entry.status === 'failure')?.content ?? null;
}

// A one-shot turn, so it runs its own WorkflowStream instead of going through
// workflowStreamFactory, which is for sharing and retrying a connection.
export function runChatTurn({ namespaceId, workflowId, text, timeoutMs = null }) {
  const stream = new WorkflowStream();
  const id = parseGid(workflowId)?.id;

  let subscriptions = [];
  let timeoutId = null;
  let connectionOpened = false;
  let settled = false;
  let settle;

  const teardown = () => {
    clearTimeout(timeoutId);
    subscriptions.forEach((subscription) => subscription.dispose());
    subscriptions = [];
    stream.terminate();
  };

  const outcome = new Promise((resolve) => {
    settle = (result) => {
      if (settled) return;
      settled = true;
      teardown();
      resolve({ connectionOpened, ...result });
    };
  });

  subscriptions = [
    stream.subscribe('open', () => {
      connectionOpened = true;
    }),
    stream.subscribe('message', (event) => {
      const { status, checkpoint } = event?.data?.newCheckpoint ?? {};
      const type = outcomeForStatus(status);

      if (!type) return;

      const errorMessage =
        type === CHAT_TURN_OUTCOME.RUN_ENDED ? lastFailureMessage(checkpoint) : null;

      settle({ type, status, errorMessage });
    }),
    stream.subscribe('close', ({ code, reason, category }) => {
      settle({ type: CHAT_TURN_OUTCOME.DISCONNECTED, close: { code, reason, category } });
    }),
    stream.subscribe('error', (event) => {
      settle({
        type: CHAT_TURN_OUTCOME.STREAM_ERROR,
        errorMessage: event?.message ?? event?.name ?? '',
      });
    }),
  ];

  if (timeoutMs) {
    timeoutId = setTimeout(() => settle({ type: CHAT_TURN_OUTCOME.TIMED_OUT }), timeoutMs);
  }

  stream.connect(
    buildWebsocketUrl({
      namespaceId,
      workflowDefinition: DUO_WORKFLOW_CHAT_DEFINITION,
      workflowId: id,
    }),
    buildStartRequest({
      workflowId: id,
      workflowDefinition: DUO_WORKFLOW_CHAT_DEFINITION,
      userPrompt: createUserPrompt({ text }),
    }),
  );

  return {
    outcome,
    cancel: () => {
      if (settled) return;
      settled = true;
      teardown();
    },
  };
}
