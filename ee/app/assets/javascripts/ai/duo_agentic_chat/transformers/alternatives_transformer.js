import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import { findPrecedingUserMessage } from '../utils/checkpoint_resolver';
import { isClarificationAnswerMessage } from '../utils/messages_utils';
import { WorkflowUtils } from '../utils/workflow_utils';

const isUserMessage = (message) => message?.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.user;
const isAssistantMessage = (message) =>
  message?.role?.toLowerCase() === GENIE_CHAT_MODEL_ROLES.assistant;

// The turn's terminator is the last assistant-role message before the next user
// message (or the end of the transcript), mirroring how duo-ui itself picks the
// message it attaches the action bar/pager to.
function findTurnTerminatorIndex(messages, userMessageIndex) {
  let terminatorIndex = -1;

  for (let i = userMessageIndex + 1; i < messages.length; i += 1) {
    const msg = messages[i];
    if (isUserMessage(msg) && !isClarificationAnswerMessage(msg)) break;
    if (isAssistantMessage(msg)) terminatorIndex = i;
  }

  return terminatorIndex;
}

/**
 * Transforms `DuoWorkflowBranch[]` (from the `duoWorkflowBranches` query) into the
 * `{ user_message, agent_responses }[]` shape duo-ui's pager/message components
 * already expect (see duo-ui's duo_chat_message.vue `selectedAlternativeContent`).
 * A branch's `messages` are oldest-first: the first is the resent user message,
 * the rest are its agent response(s).
 */
export function transformBranchesToAlternatives(branches) {
  if (!branches?.length) return [];

  return branches.map((branch) => {
    const [userMessage, ...agentResponses] = WorkflowUtils.transformChatMessages(
      WorkflowUtils.normalizeDuoMessages(branch.messages || []),
    );

    return {
      user_message: userMessage ?? null,
      agent_responses: agentResponses,
    };
  });
}

// Splits `messages` into turns: each turn starts at a non-clarification-answer user
// message and runs up to (excluding) the next one. Any leading messages before the
// first such user message (not expected in practice) are not part of any turn.
function splitIntoTurns(messages) {
  const starts = [];

  messages.forEach((msg, index) => {
    if (isUserMessage(msg) && !isClarificationAnswerMessage(msg)) {
      starts.push(index);
    }
  });

  return starts.map((start, i) => {
    const end = starts[i + 1] ?? messages.length;
    const terminatorIndex = findTurnTerminatorIndex(messages, start);

    return { start, end, userMessage: messages[start], terminatorIndex };
  });
}

// Server lineage is stamped only on a turn a reload or replay reconstructed; a
// prompt this session appended locally carries none until it round-trips.
const isServerLoadedTurn = (turn) =>
  Boolean(turn.userMessage.thread_ts || turn.userMessage.alternative_count);

// Groups a retry turn with the turn it retries. The resent prompt is stamped
// `is_retry` when the send appends it, and a retry can only ever be appended
// immediately after the turn it retries (retrying is only offered on the latest
// turn, and a new prompt cannot be sent while one is in flight). Content equality
// alone would not be enough: a user re-asking the same question verbatim starts a
// new turn, not another attempt at the previous one.
//
// A checkpoint replay can also append the retried turn's other attempts, which
// carry no `is_retry` stamp (only the locally resent prompt does). Server lineage
// is what identifies one, so requiring it keeps a verbatim re-ask (typed locally,
// no lineage yet) a turn of its own next to a group that already holds a retry.
function groupConsecutiveRetries(turns) {
  const groups = [];

  turns.forEach((turn) => {
    const previousGroup = groups[groups.length - 1];
    const previousTurn = previousGroup?.[previousGroup.length - 1];
    const isAnotherAttempt =
      turn.userMessage.is_retry ||
      (isServerLoadedTurn(turn) && previousGroup?.some((t) => t.userMessage.is_retry));

    if (
      previousTurn &&
      isAnotherAttempt &&
      turn.userMessage.content &&
      turn.userMessage.content === previousTurn.userMessage.content
    ) {
      previousGroup.push(turn);
    } else {
      groups.push([turn]);
    }
  });

  return groups;
}

// Newest first: index 0 is the displayed attempt, higher indices are further in
// the past (the pager's paging direction). Attempts are appended in real time, so
// array order usually reflects recency, but a checkpoint replay or thread reload
// can reorder the log, so a timestamp wins when one is available.
//
// Every turn is ranked on the same key rather than special-casing a missing
// timestamp pairwise: a comparator that calls such a pair "equal" is not
// transitive, and since `sort` does not compare every pair, the result would
// otherwise depend on the input order.
function sortTurnsNewestFirst(turns) {
  return turns
    .map((turn, index) => {
      const ts = Date.parse(turn.userMessage.timestamp);
      if (!Number.isNaN(ts)) return { turn, index, ts };

      // No timestamp and no server lineage means a send this session appended
      // (`addDuoChatMessage` sets none), so it ranks newest. `timestamp` is
      // nullable server-side too, and a reconstructed turn missing one must not
      // outrank a dated attempt, so it falls to the far end instead.
      return { turn, index, ts: isServerLoadedTurn(turn) ? -Infinity : Infinity };
    })
    .sort((a, b) => {
      if (a.ts !== b.ts) return a.ts > b.ts ? -1 : 1;
      // Same instant, or neither datable: the later append is the newer.
      return b.index - a.index;
    })
    .map(({ turn }) => turn);
}

function buildAlternativesForGroup(messages, group, { branchesByThreadTs, isTurnInFlight }) {
  // The displayed turn is the newest attempt, not necessarily the last one in
  // the array: a checkpoint replay/reload can append the canonical (first)
  // attempt after a live retry, which must not demote that retry. `olderTurns`
  // is filtered rather than taken from the sorted result so it stays in array
  // order, which is what the index tiebreak below means by "later append".
  const [displayedTurn] = sortTurnsNewestFirst(group);
  const olderTurns = group.filter((turn) => turn !== displayedTurn);

  // A retry's turn is appended before any reply arrives, and its reply then
  // streams in over several messages. Collapsing while it is in flight would
  // drop the previous attempt with no settled terminator to reattach it to as
  // an `alternative` -- hiding the very message that `retryingMessageId`/
  // `retryFailedMessageId` target for the pending/failed retry-state badge,
  // and with it the action bar and pager the user was just looking at.
  // Treat the retry's own turn as not part of the group yet, so the previous
  // attempt (with its badge, action bar and pager) keeps rendering until the
  // turn settles. Only a locally sent retry sitting at the transcript tail
  // qualifies: an unrelated turn in flight -- a run adopted on reopening the
  // thread, or one a clarification answer continues -- keeps its own pager.
  const retryInFlight =
    isTurnInFlight &&
    Boolean(displayedTurn.userMessage.is_retry) &&
    displayedTurn.end === messages.length;

  if (olderTurns.length && (displayedTurn.terminatorIndex === -1 || retryInFlight)) {
    return buildAlternativesForGroup(messages, olderTurns, { branchesByThreadTs, isTurnInFlight });
  }

  // duo-ui renders the pager on a turn's terminator, so a turn with no assistant
  // message yet has nowhere to carry alternatives.
  if (displayedTurn.terminatorIndex === -1) {
    return messages.slice(displayedTurn.start, displayedTurn.end);
  }

  // Only the turn a GraphQL reload actually loaded carries
  // `alternative_count`/`thread_ts`; live retry turns never do.
  const anchorTurn = group.find(isServerLoadedTurn) ?? group[0];

  // Alternatives from attempts made before this session (or before the last reload):
  // only a count is known until `duoWorkflowBranches` has been fetched for this turn.
  const serverCount = anchorTurn.userMessage.alternative_count ?? 0;
  const fetchedBranches = anchorTurn.userMessage.thread_ts
    ? branchesByThreadTs[anchorTurn.userMessage.thread_ts]
    : undefined;
  const historicalAlternatives = fetchedBranches
    ? transformBranchesToAlternatives(fetchedBranches)
    : Array.from({ length: serverCount }, () => ({ user_message: null, agent_responses: [] }));

  // Alternatives from retries made in this live session: their full content is
  // already in `messages`, so no fetch is needed for these. Ordered newest
  // first, matching the pager's paging direction (index 0 is the displayed
  // response, higher indices are further in the past).
  const localAlternatives = sortTurnsNewestFirst(olderTurns).map((turn) => ({
    user_message: turn.userMessage,
    agent_responses: messages.slice(turn.start + 1, turn.end),
  }));

  // Historical alternatives predate every local turn, so they belong at the
  // end (furthest from the displayed response).
  const alternatives = [...localAlternatives, ...historicalAlternatives];
  const displayedMessages = messages.slice(displayedTurn.start, displayedTurn.end);

  if (!alternatives.length) {
    return displayedMessages;
  }

  // Stamped on the terminator so `onSelectAlternative` can fetch the right
  // branches without having to re-derive the anchor: the turn remaining in
  // `messages` after a live retry is `displayedTurn`, but the thread_ts a
  // historical placeholder needs belongs to `anchorTurn`.
  const alternativesThreadTs = anchorTurn.userMessage.thread_ts;
  const relativeTerminatorIndex = displayedTurn.terminatorIndex - displayedTurn.start;
  return displayedMessages.map((msg, i) =>
    i === relativeTerminatorIndex ? { ...msg, alternatives, alternativesThreadTs } : msg,
  );
}

/**
 * Collapses same-question retry turns and attaches an `alternatives` array (in the
 * shape duo-ui already renders) to the terminator message of the turn that remains,
 * so a manual retry's previous attempts become pager entries instead of separate,
 * stacked turns. See the two alternative sources above: `branchesByThreadTs`
 * (lazily fetched, pre-session/pre-reload attempts) and turns already present in
 * `messages` (retries made in the current live session).
 *
 * `isTurnInFlight` is the host's "a turn is currently streaming" signal
 * (`isWaitingOnPrompt`). While set, a streaming retry at the transcript tail is
 * kept out of its group so the previous attempt -- and its action bar/pager --
 * stays rendered until the new response fully lands, instead of being swapped
 * for a still-streaming terminator that duo-ui renders without an action bar.
 *
 * A factory rather than a bare transformer because the fetched branches and the
 * in-flight flag live in the host's state; it must also run last in the pipeline,
 * since finding each turn's terminator requires the log every other transformer
 * has already rewritten.
 */
export const alternativesTransformer =
  ({ branchesByThreadTs = {}, isTurnInFlight = false } = {}) =>
  (messages) => {
    if (!messages?.length) return messages;

    const turns = splitIntoTurns(messages);
    if (!turns.length) return messages;

    const prefix = messages.slice(0, turns[0].start);
    const groups = groupConsecutiveRetries(turns);
    const body = groups.flatMap((group) =>
      buildAlternativesForGroup(messages, group, { branchesByThreadTs, isTurnInFlight }),
    );

    return [...prefix, ...body];
  };

// duo-ui's pager swaps only the response, so show the selected attempt's user message
// (and its included references) above it too. Display-only: fork-point lookups on
// `transformedMessages` need the displayed turn's own user message.
export function withSelectedUserMessages(messages, selectedAlternatives = {}) {
  const result = [...messages];

  messages.forEach((message, index) => {
    const selectedIndex = selectedAlternatives[message.id] ?? 0;
    const selectedUserMessage =
      selectedIndex > 0 && message.alternatives?.[selectedIndex - 1]?.user_message;
    if (!selectedUserMessage) return;

    const userIndex = messages.indexOf(findPrecedingUserMessage(messages, index));
    if (userIndex >= 0) result[userIndex] = selectedUserMessage;
  });

  return result;
}
