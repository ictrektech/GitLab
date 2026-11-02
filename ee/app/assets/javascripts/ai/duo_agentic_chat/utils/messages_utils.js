import escapeRegExp from 'lodash-es/escapeRegExp';
import { CHAT_MESSAGE_TYPES, GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import { COMPACT_COMMAND, GOAL_COMMAND, MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER } from '../constants';
import { ATTACHMENTS_CATEGORY } from './attachment_utils';

// Loaded messages carry `id`, streamed ones only `message_id`, and a locally added
// prompt only `requestId`; all three derive from the same executor-assigned id.
const messageKey = (message) => message?.id ?? message?.message_id ?? message?.requestId ?? null;

/**
 * Ids of the messages a retry replaces: the resubmitted user message and everything
 * after it. Retrying the same turn again adds the next attempt's ids, so an
 * accumulated set describes every attempt the forked run leaves behind.
 */
export const collectSupersededAttemptIds = (messages = [], promptMessage) => {
  const key = messageKey(promptMessage);
  if (!key) return [];

  const attemptStart = messages.findIndex((msg) => messageKey(msg) === key);
  if (attemptStart === -1) return [];

  return messages.slice(attemptStart).map(messageKey).filter(Boolean);
};

/**
 * The conversation the resumed run actually replays: the flat message log minus
 * the attempts a retry superseded.
 */
export const excludeSupersededMessages = (messages = [], supersededIds) => {
  if (!supersededIds?.size) return messages;

  return messages.filter((msg) => !supersededIds.has(messageKey(msg)));
};

export const getMessagesToProcess = (messages, lastProcessedMessageId) => {
  if (!messages || messages.length === 0) {
    return {
      toProcess: [],
      lastProcessedMessageId: null,
    };
  }

  // First run or log shrank (truncate / reset): process everything.
  const isFirstRunOrReset = lastProcessedMessageId === null;
  let startIndex;
  if (isFirstRunOrReset) {
    startIndex = 0;
  } else {
    startIndex = messages.findIndex((msg) => msg.message_id === lastProcessedMessageId);
    if (startIndex === -1) {
      startIndex = 0;
    }
  }

  const toProcess = messages.slice(startIndex);

  return {
    toProcess,
    lastProcessedMessageId: messages.at(-1).message_id,
  };
};

// Mirrors duo-ui's own isUserMessage, down to the lowercasing, which the package does
// not export: a caller that disagrees with duo-ui about which messages are the user's
// silently fails to override the bubble duo-ui renders for them.
export const isUserMessage = (message) =>
  message?.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user ||
  message?.message_type?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user;

// A clarification answer is user-authored but continues the turn that asked the
// question rather than starting a new one.
export const isClarificationAnswerMessage = (message) => {
  if (typeof message?.content !== 'string') return false;
  try {
    return JSON.parse(message.content)?.message_sub_type === MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER;
  } catch {
    return false;
  }
};

// A tool call the agent has put to the user, which duo-ui routes to its
// MessageToolApproval card. Whether the card is still actionable depends on where
// the message sits in the log, so that part is left to the caller.
export const isToolApprovalRequest = (message) =>
  message?.message_type === CHAT_MESSAGE_TYPES.request && Boolean(message?.tool_info);

// Anchored so `/compaction of the log` is not `/compact`, and cased the way `commandsIn`
// in `services/user_prompt/user_prompt_builder.js` matches the same token.
const invocationOf = (command) => new RegExp(`^${escapeRegExp(command)}(\\s|$)`, 'i');

const COMPACT_PROMPT = invocationOf(COMPACT_COMMAND);

/**
 * The prompt that asks for a compaction. Shared by the compact plugin, which renders a
 * loading indicator in its place and drops it once it has settled, and by the state
 * manager, which hides duo-ui's generic response loader while it is on screen.
 *
 * @param {Object} message
 * @returns {boolean}
 */
export const isCompactPromptMessage = (message) =>
  isUserMessage(message) &&
  typeof message.content === 'string' &&
  COMPACT_PROMPT.test(message.content.trim());

/**
 * A compaction message, whether or not anything was actually summarized. Shared by the
 * widget that renders the divider, the transformer that drops the no-op ones and the
 * retry rules, so none of them can drift apart on what counts as a compaction.
 *
 * @param {Object} message
 * @returns {boolean}
 */
export const isCompactionMessage = (message) => message?.message_sub_type === 'compaction';

/**
 * A compaction that summarized nothing marks no boundary, so the divider would announce a
 * change that never happened. A missing count is read the same as zero: the question is
 * whether anything was summarized.
 *
 * @param {Object} message
 * @returns {boolean}
 */
export const isNoopCompaction = (message) =>
  isCompactionMessage(message) && !(message.tool_info?.args?.messages_summarized > 0);

const GOAL_PROMPT = invocationOf(GOAL_COMMAND);

export const isGoalPromptMessage = (message) =>
  isUserMessage(message) &&
  typeof message.content === 'string' &&
  GOAL_PROMPT.test(message.content.trim());

export const goalIn = (content) => (content ?? '').trim().replace(GOAL_PROMPT, '').trimStart();

// Any command rather than a particular one, so there is nothing to build with
// `invocationOf`: `:` and `-` cover `/flow:<slug>`, whose slug may be hyphenated, and the
// `(\s|$)` tail a bare command as well as one with arguments.
const SLASH_COMMAND = /^\/[\w:-]+(\s|$)/;

/**
 * A prompt that invokes a slash command instead of asking the agent for a response.
 * Anchored at the start, so a prompt merely mentioning a command is not one.
 *
 * @param {Object} message
 * @returns {boolean}
 */
export const isSlashCommandMessage = (message) =>
  isUserMessage(message) &&
  typeof message.content === 'string' &&
  SLASH_COMMAND.test(message.content.trim());

// Compared case-insensitively: the websocket delivers the category as the flow service
// wrote it, while the checkpoint query delivers it as a GraphQL enum, in upper case.
export const isAttachmentReference = (context) =>
  context?.category?.toLowerCase() === ATTACHMENTS_CATEGORY;

/**
 * The files sent with a user turn. A pending turn has only what the composer sent. Once
 * the flow service echoes the turn, its references lead (name and type, never the bytes)
 * and the local previews pair up by position, since the service numbers them in the
 * order they were sent. After a reload only the references are left.
 *
 * @param {Object} message
 * @returns {{ id: string, filename: string, mimeType: string, byteSize?: number, previewUrl?: string }[]}
 */
export const attachmentsIn = (message) => {
  const sent = message?.attachments ?? [];
  const references = (message?.additional_context ?? []).filter(isAttachmentReference);

  if (!references.length) return sent;

  return references.map(({ id, metadata }, index) => ({
    id,
    filename: metadata?.title,
    mimeType: metadata?.secondaryText,
    byteSize: sent[index]?.byteSize,
    previewUrl: sent[index]?.previewUrl,
  }));
};

export const hasAttachments = (message) =>
  isUserMessage(message) && attachmentsIn(message).length > 0;
