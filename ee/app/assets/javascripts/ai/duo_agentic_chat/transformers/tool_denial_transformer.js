import { CHAT_MESSAGE_TYPES } from 'ee/ai/constants';
import { isToolApprovalRequest } from '../utils/messages_utils';

// Mirror the backend ToolStatus enum values consumed by duo-ui's MessageToolApproval card.
const TOOL_STATUS_CANCELLED = 'cancelled';
const TOOL_STATUS_PENDING = 'pending';

// A `pending` tool card is the placeholder streamed while the call is still being
// composed, so it says nothing about whether the user approved it.
const isExecutedTool = (msg) =>
  msg.message_type === CHAT_MESSAGE_TYPES.tool &&
  Boolean(msg.tool_info) &&
  msg.status !== TOOL_STATUS_PENDING;

/**
 * Determines the index where the trailing run of pending approval requests begins.
 * These are the consecutive request+tool_info messages at the very end of the log
 * that are still awaiting the user's decision. They must be left untouched so the
 * interactive approval widget keeps rendering (mirrors duo-ui's pendingToolApprovals).
 */
const pendingApprovalStartIndex = (messages) => {
  let index = messages.length;
  while (index > 0 && isToolApprovalRequest(messages[index - 1])) {
    index -= 1;
  }
  return index;
};

/**
 * Rewrites denied tool approval requests into finalized "cancelled" request cards.
 *
 * The backend never emits a tool message for a denied request, so without this the
 * chat log would only keep the "Tool X requires approval..." text and drop the card
 * entirely. An approved request, by contrast, is followed by an executed tool message.
 * Both entries carry the tool call id as their message_id, which is what ties them
 * together:
 *
 *   - pending  → request is in the trailing approval run       → leave as-is
 *   - approved → an executed tool message shares its message_id → leave as-is
 *   - denied   → neither of the above                          → set status to
 *                'cancelled' so duo-ui's MessageToolApproval renders the finalized card
 *
 * Since duo-ui routes request-type messages directly to MessageToolApproval (as of
 * @gitlab/duo-ui v15.41), the message_type stays 'request' — only the status changes.
 *
 * Matching on the id rather than on tool name and log order matters when a tool
 * message is missing or arrives out of order: with name matching, the neighbouring
 * request for the same tool would take its badge and both cards would read wrong.
 */
export const toolDenialTransformer = (messages) => {
  const pendingStart = pendingApprovalStartIndex(messages);
  const executedToolIds = new Set(
    messages
      .filter(isExecutedTool)
      .map((msg) => msg.message_id)
      .filter(Boolean),
  );

  return messages.map((msg, index) => {
    if (
      index >= pendingStart ||
      !isToolApprovalRequest(msg) ||
      executedToolIds.has(msg.message_id)
    ) {
      return msg;
    }

    return {
      ...msg,
      status: TOOL_STATUS_CANCELLED,
    };
  });
};
