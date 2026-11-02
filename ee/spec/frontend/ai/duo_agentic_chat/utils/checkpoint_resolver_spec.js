import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';
import {
  findPrecedingUserMessage,
  resolveSelectedAlternative,
} from 'ee/ai/duo_agentic_chat/utils/checkpoint_resolver';

const userMessage = (id, content = 'What is GitLab?', extra = {}) => ({
  id,
  message_id: id,
  role: GENIE_CHAT_MODEL_ROLES.user,
  content,
  ...extra,
});

const assistantMessage = (id, extra = {}) => ({
  id,
  message_id: id,
  role: GENIE_CHAT_MODEL_ROLES.assistant,
  content: 'An answer',
  ...extra,
});

const alternativesOf = (...userMessageIds) =>
  userMessageIds.map((messageId) => ({ user_message: { message_id: messageId } }));

describe('checkpoint_resolver', () => {
  describe('findPrecedingUserMessage', () => {
    it('skips clarification answers, which continue a turn rather than start one', () => {
      const messages = [
        userMessage('user-1'),
        assistantMessage('assistant-1'),
        userMessage('clarification', JSON.stringify({ message_sub_type: 'clarification_answer' })),
        assistantMessage('assistant-2'),
      ];

      expect(findPrecedingUserMessage(messages, 3).id).toBe('user-1');
    });

    it('returns null when no user message precedes the index', () => {
      expect(findPrecedingUserMessage([assistantMessage('assistant-1')], 1)).toBeNull();
    });
  });

  describe('resolveSelectedAlternative', () => {
    it('returns the selected alternative of the last turn', () => {
      const messages = [
        userMessage('user-1'),
        assistantMessage('assistant-1', { alternatives: alternativesOf('user-0') }),
      ];

      expect(resolveSelectedAlternative(messages, { 'assistant-1': 1 })).toEqual({
        terminator: messages[1],
        userMessageId: 'user-0',
      });
    });

    it('returns null when the canonical response (index 0) is selected', () => {
      const messages = [
        userMessage('user-1'),
        assistantMessage('assistant-1', { alternatives: alternativesOf('user-0') }),
      ];

      expect(resolveSelectedAlternative(messages, {})).toBeNull();
      expect(resolveSelectedAlternative(messages, { 'assistant-1': 0 })).toBeNull();
    });

    // Regression: `alternatives` stays stamped on a retried turn's terminator for
    // good, so scanning the whole log picked up turn 1's stale pager selection and
    // forked a later follow-up there, dropping every turn since.
    it('ignores a stale selection on an earlier turn once a later turn has happened', () => {
      const messages = [
        userMessage('user-1'),
        assistantMessage('assistant-1', { alternatives: alternativesOf('user-0') }),
        userMessage('user-2', 'Something else'),
        assistantMessage('assistant-2'),
      ];

      expect(resolveSelectedAlternative(messages, { 'assistant-1': 1 })).toBeNull();
    });

    it('returns null when the selected alternative has no user message to fork from', () => {
      const messages = [
        userMessage('user-1'),
        assistantMessage('assistant-1', { alternatives: [{ user_message: null }] }),
      ];

      expect(resolveSelectedAlternative(messages, { 'assistant-1': 1 })).toBeNull();
    });
  });
});
