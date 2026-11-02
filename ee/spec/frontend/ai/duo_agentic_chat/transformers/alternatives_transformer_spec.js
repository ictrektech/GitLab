import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import { MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER } from 'ee/ai/duo_agentic_chat/constants';
import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';
import {
  transformBranchesToAlternatives,
  alternativesTransformer,
  withSelectedUserMessages,
} from 'ee/ai/duo_agentic_chat/transformers/alternatives_transformer';

jest.mock('ee/ai/duo_agentic_chat/utils/workflow_utils', () => ({
  WorkflowUtils: {
    transformChatMessages: jest.fn(),
    normalizeDuoMessages: jest.fn(),
  },
}));

const userMessage = (id, content, extra = {}) => ({
  id,
  role: GENIE_CHAT_MODEL_ROLES.user,
  message_type: 'user',
  content,
  ...extra,
});

const assistantMessage = (id, content, extra = {}) => ({
  id,
  role: GENIE_CHAT_MODEL_ROLES.assistant,
  message_type: 'agent',
  content,
  ...extra,
});

describe('alternatives_transformer', () => {
  beforeEach(() => {
    // By default, mirror WorkflowUtils.transformChatMessages' pass-through behavior
    // closely enough for these tests: identity on normalize, and id/requestId
    // derived from message_id on transform.
    WorkflowUtils.normalizeDuoMessages.mockImplementation((messages) => messages);
    WorkflowUtils.transformChatMessages.mockImplementation((messages) =>
      messages.map((m) => ({ ...m, id: m.message_id, requestId: m.message_id })),
    );
  });

  describe('transformBranchesToAlternatives', () => {
    it('returns an empty array for no branches', () => {
      expect(transformBranchesToAlternatives(undefined)).toEqual([]);
      expect(transformBranchesToAlternatives([])).toEqual([]);
    });

    it('splits each branch into a user_message and agent_responses', () => {
      const branches = [
        {
          forkThreadTs: 'ts-fork-1',
          messages: [
            { message_id: 'alt-user-1', content: 'What is GitLab?' },
            { message_id: 'alt-agent-1', content: 'First answer' },
          ],
        },
      ];

      const result = transformBranchesToAlternatives(branches);

      expect(result).toEqual([
        {
          user_message: expect.objectContaining({ id: 'alt-user-1', content: 'What is GitLab?' }),
          agent_responses: [
            expect.objectContaining({ id: 'alt-agent-1', content: 'First answer' }),
          ],
        },
      ]);
    });

    it('normalizes and transforms each branch through WorkflowUtils', () => {
      const branches = [{ messages: [{ message_id: 'm-1' }] }];

      transformBranchesToAlternatives(branches);

      expect(WorkflowUtils.normalizeDuoMessages).toHaveBeenCalledWith(branches[0].messages);
      expect(WorkflowUtils.transformChatMessages).toHaveBeenCalled();
    });
  });

  describe('alternativesTransformer', () => {
    const transformMessages = (messages, options) => alternativesTransformer(options)(messages);

    it('returns the input unchanged for an empty or missing array', () => {
      expect(transformMessages([])).toEqual([]);
      expect(transformMessages(undefined)).toBeUndefined();
    });

    it('does not add alternatives when there is a single turn with no alternative_count', () => {
      const messages = [userMessage('user-1', 'Hi'), assistantMessage('assistant-1', 'Hello')];

      const result = transformMessages(messages);

      expect(result).toEqual(messages);
      expect(result[1].alternatives).toBeUndefined();
    });

    it('attaches placeholder alternatives sized to alternative_count when branches are not yet fetched', () => {
      const messages = [
        userMessage('user-1', 'Hi', { alternative_count: 2, thread_ts: 'ts-1' }),
        assistantMessage('assistant-1', 'Hello'),
      ];

      const result = transformMessages(messages, { branchesByThreadTs: {} });

      expect(result[1].alternatives).toEqual([
        { user_message: null, agent_responses: [] },
        { user_message: null, agent_responses: [] },
      ]);
      expect(result[1].alternativesThreadTs).toBe('ts-1');
    });

    it('replaces placeholders with the real content once branches are fetched', () => {
      const messages = [
        userMessage('user-1', 'Hi', { alternative_count: 1, thread_ts: 'ts-1' }),
        assistantMessage('assistant-1', 'Hello'),
      ];
      const branches = [{ messages: [{ message_id: 'alt-user' }, { message_id: 'alt-agent' }] }];

      const result = transformMessages(messages, {
        branchesByThreadTs: { 'ts-1': branches },
      });

      expect(result[1].alternatives).toEqual([
        {
          user_message: expect.objectContaining({ id: 'alt-user' }),
          agent_responses: [expect.objectContaining({ id: 'alt-agent' })],
        },
      ]);
    });

    it('collapses a live retry turn into the turn it retried, with the older one as a local alternative', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First (failed) answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
      ];

      const result = transformMessages(messages);

      // The older turn's messages are dropped; only the latest turn remains.
      expect(result).toHaveLength(2);
      expect(result[0].id).toBe('user-2');
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[0], agent_responses: [messages[1]] },
      ]);
    });

    it('combines local same-session retries with historical (fetched) alternatives, local first (newest to oldest), historical last', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?', { alternative_count: 1, thread_ts: 'ts-1' }),
        assistantMessage('assistant-1', 'First (failed) answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
      ];
      const branches = [{ messages: [{ message_id: 'hist-user' }, { message_id: 'hist-agent' }] }];

      const result = transformMessages(messages, {
        branchesByThreadTs: { 'ts-1': branches },
      });

      expect(result).toHaveLength(2);
      expect(result[1].alternatives).toEqual([
        { user_message: messages[0], agent_responses: [messages[1]] },
        {
          user_message: expect.objectContaining({ id: 'hist-user' }),
          agent_responses: [expect.objectContaining({ id: 'hist-agent' })],
        },
      ]);
      expect(result[1].alternativesThreadTs).toBe('ts-1');
    });

    it('orders local same-session retries from most recent to oldest', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First (failed) answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second (failed) answer'),
        userMessage('user-3', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-3', 'Third answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-3');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[2], agent_responses: [messages[3]] },
        { user_message: messages[0], agent_responses: [messages[1]] },
      ]);
    });

    it('keeps the previous turn visible while a retry is in flight (no reply yet)', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
      ];

      const result = transformMessages(messages);

      expect(result).toEqual([messages[0], messages[1]]);
    });

    it('keeps the previous turn (with its own alternatives) visible while a second retry is in flight', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?', { alternative_count: 1, thread_ts: 'ts-1' }),
        assistantMessage('assistant-1', 'First (failed) answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
        userMessage('user-3', 'What is GitLab?', { is_retry: true }),
      ];

      const result = transformMessages(messages, { branchesByThreadTs: {} });

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      // 1 local alternative (user-1/assistant-1) + 1 historical placeholder (alternative_count).
      expect(result[1].alternatives).toHaveLength(2);
    });

    it('keeps the previous turn visible while the retry turn is still streaming (isTurnInFlight)', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answ', { status: 'streaming' }),
      ];

      const result = transformMessages(messages, { isTurnInFlight: true });

      expect(result).toEqual([messages[0], messages[1]]);
    });

    it('collapses the retry once the turn settles (isTurnInFlight cleared)', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
      ];

      const result = transformMessages(messages, { isTurnInFlight: false });

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[0], agent_responses: [messages[1]] },
      ]);
    });

    it('only defers the group at the transcript tail while a turn is in flight', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First (failed) answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
        userMessage('user-3', 'What is Duo?'),
        assistantMessage('assistant-3', 'GitLab', { status: 'streaming' }),
      ];

      const result = transformMessages(messages, { isTurnInFlight: true });

      // The completed retry group still collapses; only the (unrelated) tail
      // turn is exempt, and with no prior same-question turn it renders as-is.
      expect(result.map((m) => m.id)).toEqual(['user-2', 'assistant-2', 'user-3', 'assistant-3']);
      expect(result[1].alternatives).toHaveLength(1);
    });

    it('displays the newest attempt by timestamp when a replay appends an older attempt after it', () => {
      const messages = [
        userMessage('user-2', 'What is GitLab?', {
          is_retry: true,
          timestamp: '2026-05-19T10:00:02.000Z',
        }),
        assistantMessage('assistant-2', 'Newest answer'),
        // The replayed canonical attempt carries no `is_retry` stamp, but does
        // carry the server lineage a reconstructed message always has.
        userMessage('user-1', 'What is GitLab?', {
          timestamp: '2026-05-19T10:00:01.000Z',
          thread_ts: 'ts-1',
        }),
        assistantMessage('assistant-1', 'Canonical first answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[2], agent_responses: [messages[3]] },
      ]);
    });

    it('orders alternatives newest first by timestamp regardless of array position', () => {
      const messages = [
        userMessage('user-3', 'What is GitLab?', {
          is_retry: true,
          timestamp: '2026-05-19T10:00:03.000Z',
        }),
        assistantMessage('assistant-3', 'Newest answer'),
        userMessage('user-1', 'What is GitLab?', {
          timestamp: '2026-05-19T10:00:01.000Z',
          thread_ts: 'ts-1',
        }),
        assistantMessage('assistant-1', 'Oldest answer'),
        userMessage('user-2', 'What is GitLab?', {
          timestamp: '2026-05-19T10:00:02.000Z',
          thread_ts: 'ts-1',
        }),
        assistantMessage('assistant-2', 'Middle answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-3');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[4], agent_responses: [messages[5]] },
        { user_message: messages[2], agent_responses: [messages[3]] },
      ]);
    });

    it('falls back to array order (later turn wins) when a turn is missing a timestamp', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?', { timestamp: '2026-05-19T10:00:01.000Z' }),
        assistantMessage('assistant-1', 'First answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[0], agent_responses: [messages[1]] },
      ]);
    });

    it('does not treat a clarification-answer message as a new turn', () => {
      const clarificationAnswer = userMessage(
        'user-2',
        JSON.stringify({ message_sub_type: MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER }),
      );
      const messages = [
        userMessage('user-1', 'Original question'),
        assistantMessage('assistant-1', 'Which option?'),
        clarificationAnswer,
        assistantMessage('assistant-2', 'Final answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toEqual(messages);
    });

    it('attaches alternatives to the final answer, not a mid-turn clarification question', () => {
      const clarificationAnswer = userMessage(
        'user-2',
        JSON.stringify({ message_sub_type: MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER }),
      );
      const messages = [
        userMessage('user-1', 'Original question', { alternative_count: 1, thread_ts: 'ts-1' }),
        assistantMessage('assistant-1', 'Which option?'),
        clarificationAnswer,
        assistantMessage('assistant-2', 'Final answer'),
      ];

      const result = transformMessages(messages);

      expect(result[1].alternatives).toBeUndefined();
      expect(result[3].id).toBe('assistant-2');
      expect(result[3].alternatives).toHaveLength(1);
    });

    it('does not treat turns with different question content as retries of each other', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'A DevSecOps platform.'),
        userMessage('user-2', 'What is Duo?'),
        assistantMessage('assistant-2', "GitLab's AI assistant."),
      ];

      const result = transformMessages(messages);

      expect(result).toEqual(messages);
    });

    // Regression test: the user re-asking the same question verbatim ("hi" ...
    // "hi") is a new turn, not another attempt at the previous one. Only a
    // resent prompt stamped `is_retry` may collapse into the previous turn.
    it('does not collapse a repeated identical prompt that is not a retry', () => {
      const messages = [
        userMessage('user-1', 'hi'),
        assistantMessage('assistant-1', 'Hello!'),
        userMessage('user-2', 'hi'),
        assistantMessage('assistant-2', 'Hello again!'),
      ];

      const result = transformMessages(messages);

      expect(result).toEqual(messages);
    });

    it('keeps a repeated identical prompt visible while it is in flight', () => {
      const messages = [
        userMessage('user-1', 'hi'),
        assistantMessage('assistant-1', 'Hello!'),
        userMessage('user-2', 'hi'),
      ];

      const result = transformMessages(messages);

      expect(result).toEqual(messages);
    });

    it('keeps a repeated identical prompt separate even after the turn was retried', () => {
      const messages = [
        userMessage('user-1', 'What is GitLab?'),
        assistantMessage('assistant-1', 'First answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Second answer'),
        // Typed by the user, not replayed: no server lineage, so it starts a turn.
        userMessage('user-3', 'What is GitLab?'),
        assistantMessage('assistant-3', 'Third answer'),
      ];

      const result = transformMessages(messages);

      expect(result.map((m) => m.id)).toEqual(['user-2', 'assistant-2', 'user-3', 'assistant-3']);
      expect(result[1].alternatives).toHaveLength(1);
      expect(result[3].alternatives).toBeUndefined();
    });

    it('displays the live retry over a replayed attempt that carries a timestamp it lacks', () => {
      const messages = [
        // Appended by this session's send, so no timestamp (`ADD_MESSAGE` sets none).
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Retry answer'),
        userMessage('user-1', 'What is GitLab?', {
          timestamp: '2026-05-19T10:00:01.000Z',
          thread_ts: 'ts-1',
        }),
        assistantMessage('assistant-1', 'Canonical answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives).toEqual([
        { user_message: messages[2], agent_responses: [messages[3]] },
      ]);
    });

    it('does not promote a server-loaded turn with no timestamp over a dated attempt', () => {
      // `timestamp` is nullable on DuoMessageType, so a reconstructed attempt can
      // arrive without one. Only a turn with no server lineage can be this
      // session's own send, and so the newest.
      const messages = [
        userMessage('user-1', 'What is GitLab?', {
          timestamp: '2026-05-19T10:00:01.000Z',
          thread_ts: 'ts-1',
        }),
        assistantMessage('assistant-1', 'Dated answer'),
        userMessage('user-2', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-2', 'Live retry answer'),
        userMessage('user-3', 'What is GitLab?', { thread_ts: 'ts-1' }),
        assistantMessage('assistant-3', 'Undated server answer'),
      ];

      const result = transformMessages(messages);

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives.map((alt) => alt.user_message.id)).toEqual([
        'user-1',
        'user-3',
      ]);
    });

    it('orders the pager the same way regardless of the order attempts sit in the array', () => {
      const attempt = (n, extra = {}) => [
        userMessage(`user-${n}`, 'What is GitLab?', {
          timestamp: `2026-05-19T10:00:0${n}.000Z`,
          thread_ts: 'ts-1',
          ...extra,
        }),
        assistantMessage(`assistant-${n}`, `Answer ${n}`),
      ];
      // An untimestamped live retry between two timestamped attempts is what made
      // the previous comparator non-transitive: `sort` skipped the direct
      // comparison between the two it could order, so the result flipped with the
      // input order.
      const live = [
        userMessage('user-live', 'What is GitLab?', { is_retry: true }),
        assistantMessage('assistant-live', 'Live answer'),
      ];
      const pagerOrder = (messages) =>
        transformMessages(messages)[1].alternatives.map((alt) => alt.user_message.id);

      expect(pagerOrder([...attempt(1), ...live, ...attempt(3)])).toEqual(['user-3', 'user-1']);
      expect(pagerOrder([...attempt(3), ...live, ...attempt(1)])).toEqual(['user-3', 'user-1']);
    });

    it('keeps the pager while a turn is in flight and a replay put the older attempt last', () => {
      const messages = [
        userMessage('user-2', 'What is GitLab?', {
          is_retry: true,
          timestamp: '2026-05-19T10:00:02.000Z',
        }),
        assistantMessage('assistant-2', 'Newest answer'),
        userMessage('user-1', 'What is GitLab?', {
          timestamp: '2026-05-19T10:00:01.000Z',
          thread_ts: 'ts-1',
        }),
        assistantMessage('assistant-1', 'Canonical answer'),
      ];

      // The newest attempt is not the array-last turn, so nothing of it is
      // streaming: it stays displayed, with its pager.
      const result = transformMessages(messages, { isTurnInFlight: true });

      expect(result).toHaveLength(2);
      expect(result[1].id).toBe('assistant-2');
      expect(result[1].alternatives).toHaveLength(1);
    });

    it("keeps a lone turn's server-side pager while an unrelated turn is in flight", () => {
      // `adoptRunningStream` sets isWaitingOnPrompt right after loading a thread,
      // and a clarification answer leaves the tail turn in flight without starting
      // a new one. Neither is a retry, so the pager must survive.
      const messages = [
        userMessage('user-1', 'What is GitLab?', { alternative_count: 2, thread_ts: 'ts-1' }),
        assistantMessage('assistant-1', 'Answer'),
      ];

      const result = transformMessages(messages, { isTurnInFlight: true });

      expect(result).toHaveLength(2);
      expect(result[1].alternatives).toHaveLength(2);
      expect(result[1].alternativesThreadTs).toBe('ts-1');
    });
  });

  describe('withSelectedUserMessages', () => {
    const olderUser = userMessage('user-old', 'What is GitLab?', {
      extras: { contextItems: [{ id: 'old-context' }] },
    });
    const messages = [
      userMessage('user-new', 'What is GitLab?', {
        extras: { contextItems: [{ id: 'new-context' }] },
      }),
      assistantMessage('assistant-new', 'New answer', {
        alternatives: [
          { user_message: olderUser, agent_responses: [] },
          { user_message: null, agent_responses: [] },
        ],
      }),
    ];

    it.each([
      ['no alternative is selected', {}],
      ['the displayed attempt is selected', { 'assistant-new': 0 }],
      ['a not-yet-fetched alternative is selected', { 'assistant-new': 2 }],
    ])('keeps the displayed user message when %s', (_, selectedAlternatives) => {
      expect(withSelectedUserMessages(messages, selectedAlternatives)).toEqual(messages);
    });

    it("shows the selected alternative's user message above its response", () => {
      expect(withSelectedUserMessages(messages, { 'assistant-new': 1 })).toEqual([
        olderUser,
        messages[1],
      ]);
    });

    it('skips a clarification answer to reach the user message that started the turn', () => {
      const withAnswer = [
        messages[0],
        assistantMessage('question', 'Which one?'),
        userMessage(
          'answer',
          JSON.stringify({ message_sub_type: MESSAGE_SUB_TYPE_CLARIFICATION_ANSWER }),
        ),
        messages[1],
      ];

      expect(withSelectedUserMessages(withAnswer, { 'assistant-new': 1 })).toEqual([
        olderUser,
        ...withAnswer.slice(1),
      ]);
    });
  });
});
