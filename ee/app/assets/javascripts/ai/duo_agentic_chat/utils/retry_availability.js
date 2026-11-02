import { ATTACHMENTS_CATEGORY } from './attachment_utils';
import {
  isClarificationAnswerMessage,
  isCompactionMessage,
  isNoopCompaction,
  isSlashCommandMessage,
  isUserMessage,
} from './messages_utils';

/**
 * Deciding whether the last response can be retried, kept out of the state manager so
 * the rules are exercised without mounting it. Every rule here is a pure function of the
 * raw message log, deliberately not of the transformed one: `dropCompactPrompt` deletes
 * the `/compact` prompt a rule below has to see, and the transformers a plugin
 * contributes are only in the pipeline while that plugin is registered.
 */

/**
 * A compaction summarizes away the history a retry would fork from, so retrying the last
 * response would replay against the compacted prompt. A new prompt re-enables it.
 *
 * @param {Object[]} messages
 * @returns {boolean}
 */
export const wasCompactedSinceLastPrompt = (messages) => {
  const log = messages ?? [];

  for (let i = log.length - 1; i >= 0; i -= 1) {
    const message = log[i];
    // A compaction that summarized nothing left the fork point where it was.
    if (isCompactionMessage(message)) {
      if (!isNoopCompaction(message)) return true;
    } else if (isUserMessage(message) && !isClarificationAnswerMessage(message)) {
      return false;
    }
  }

  return false;
};

const findLastPrompt = (messages) =>
  (messages ?? []).findLast(
    (message) => isUserMessage(message) && !isClarificationAnswerMessage(message),
  );

/**
 * A slash command asks for one specific piece of work -- compact the conversation, start
 * a flow -- rather than for a response the agent could plausibly produce differently, so
 * a retry has nothing to do.
 *
 * @param {Object[]} messages
 * @returns {boolean}
 */
export const wasLastPromptSlashCommand = (messages) =>
  isSlashCommandMessage(findLastPrompt(messages));

/**
 * Attachments are not stored with the turn, so a retry would resend the prompt without
 * them. The category is lower case live and upper case after a reload.
 *
 * @param {Object[]} messages
 * @returns {boolean}
 */
export const didLastPromptCarryAttachments = (messages) =>
  Boolean(
    findLastPrompt(messages)?.additional_context?.some(
      (item) => item.category?.toLowerCase() === ATTACHMENTS_CATEGORY,
    ),
  );

/**
 * @param {Object[]} messages
 * @returns {boolean}
 */
export const isRetryAvailable = (messages) =>
  !wasCompactedSinceLastPrompt(messages) && !wasLastPromptSlashCommand(messages);
