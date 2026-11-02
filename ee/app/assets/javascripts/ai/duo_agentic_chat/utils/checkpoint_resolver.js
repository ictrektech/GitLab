import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import { isClarificationAnswerMessage } from './messages_utils';

/**
 * Deciding which checkpoint a send resumes from, kept out of the state manager so
 * it is exercised without mounting it. The Apollo reads and the component state
 * these work on stay in the caller; everything here is a pure function of the
 * transcript.
 */

// The nearest user message strictly before `fromIndex` that actually started a
// turn, skipping clarification answers the way `alternativesTransformer` does.
export function findPrecedingUserMessage(messages, fromIndex) {
  for (let i = fromIndex - 1; i >= 0; i -= 1) {
    const msg = messages[i];
    if (msg.role?.toLowerCase() !== GENIE_CHAT_MODEL_ROLES.user) continue;
    if (isClarificationAnswerMessage(msg)) continue;
    return msg;
  }
  return null;
}

/**
 * The alternative the user is currently looking at on the last turn, or null when
 * that is the canonical response (index 0), which needs no fork point.
 *
 * Only the last turn counts. `alternatives` stays stamped on every retried turn's
 * terminator for the life of the transcript, so searching the whole log for one
 * would pick up an older turn's pager selection and fork a later follow-up there,
 * silently dropping every turn since from what the agent resumes.
 */
export function resolveSelectedAlternative(messages, selectedAlternatives = {}) {
  const terminator = messages.findLast(
    (m) => m.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.assistant,
  );
  if (!terminator?.alternatives?.length) return null;

  const selectedIndex = selectedAlternatives[terminator.id] ?? 0;
  if (selectedIndex <= 0) return null;

  const userMessageId = terminator.alternatives[selectedIndex - 1]?.user_message?.message_id;
  if (!userMessageId) return null;

  return { terminator, userMessageId };
}
