import {
  didLastPromptCarryAttachments,
  isRetryAvailable,
  wasCompactedSinceLastPrompt,
  wasLastPromptSlashCommand,
} from 'ee/ai/duo_agentic_chat/utils/retry_availability';

const userMessage = (content = 'What is GitLab?', extra = {}) => ({
  role: 'user',
  content,
  ...extra,
});

const assistantMessage = (extra = {}) => ({
  role: 'assistant',
  content: 'An answer',
  ...extra,
});

const compactionMessage = (messagesSummarized = 2) => ({
  role: 'tool',
  message_type: 'tool',
  message_sub_type: 'compaction',
  content: 'Summarized 2 messages',
  tool_info: { args: { messages_summarized: messagesSummarized } },
});

const clarificationAnswer = () => ({
  role: 'user',
  content: JSON.stringify({ message_sub_type: 'clarification_answer', content: 'Yes' }),
});

describe('retry_availability', () => {
  describe('wasCompactedSinceLastPrompt', () => {
    it.each([
      ['there are no messages', []],
      ['nothing was passed', undefined],
      ['no compaction ever ran', [userMessage(), assistantMessage()]],
      [
        'a new prompt follows the compaction',
        [userMessage(), compactionMessage(), userMessage('A new prompt'), assistantMessage()],
      ],
      [
        'the compaction summarized nothing',
        [userMessage(), assistantMessage(), compactionMessage(0)],
      ],
      [
        'the compaction reports no count at all',
        [userMessage(), assistantMessage(), { message_sub_type: 'compaction' }],
      ],
    ])('is false when %s', (_, messages) => {
      expect(wasCompactedSinceLastPrompt(messages)).toBe(false);
    });

    it('is true when a compaction closes the log', () => {
      expect(
        wasCompactedSinceLastPrompt([userMessage(), assistantMessage(), compactionMessage()]),
      ).toBe(true);
    });

    it('looks past a compaction that summarized nothing to an earlier real one', () => {
      expect(
        wasCompactedSinceLastPrompt([
          userMessage(),
          assistantMessage(),
          compactionMessage(),
          compactionMessage(0),
        ]),
      ).toBe(true);
    });

    it('is true when the compaction ran mid-turn, between the prompt and the response', () => {
      expect(
        wasCompactedSinceLastPrompt([userMessage(), compactionMessage(), assistantMessage()]),
      ).toBe(true);
    });

    it('does not treat a clarification answer as a new prompt', () => {
      expect(
        wasCompactedSinceLastPrompt([userMessage(), compactionMessage(), clarificationAnswer()]),
      ).toBe(true);
    });
  });

  describe('wasLastPromptSlashCommand', () => {
    it.each([
      ['there are no messages', []],
      ['nothing was passed', undefined],
      ['the log holds no user message', [assistantMessage()]],
    ])('is false when %s', (_, messages) => {
      expect(wasLastPromptSlashCommand(messages)).toBe(false);
    });

    it('is true when the last prompt invoked a command', () => {
      expect(wasLastPromptSlashCommand([userMessage('/compact'), assistantMessage()])).toBe(true);
    });

    it('reads the last prompt rather than an earlier one', () => {
      expect(
        wasLastPromptSlashCommand([
          userMessage('/compact'),
          assistantMessage(),
          userMessage('What is GitLab?'),
          assistantMessage(),
        ]),
      ).toBe(false);
    });

    it('looks past a clarification answer to the prompt that started the turn', () => {
      expect(wasLastPromptSlashCommand([userMessage('/goal ship it'), clarificationAnswer()])).toBe(
        true,
      );
    });
  });

  describe('didLastPromptCarryAttachments', () => {
    const withContext = (...categories) =>
      userMessage('What is in this image?', {
        additional_context: categories.map((category) => ({ category })),
      });

    it.each([
      ['there are no messages', []],
      ['nothing was passed', undefined],
      ['the last prompt has no additional context', [userMessage(), assistantMessage()]],
      ['the last prompt has only other context', [withContext('repository'), assistantMessage()]],
      [
        'an earlier prompt had attachments but the last one did not',
        [withContext('attachments'), assistantMessage(), userMessage(), assistantMessage()],
      ],
    ])('is false when %s', (_, messages) => {
      expect(didLastPromptCarryAttachments(messages)).toBe(false);
    });

    it.each([
      ['streamed live', 'attachments'],
      ['reloaded from a checkpoint', 'ATTACHMENTS'],
    ])('is true when the last prompt carried attachments %s', (_, category) => {
      expect(
        didLastPromptCarryAttachments([withContext('repository', category), assistantMessage()]),
      ).toBe(true);
    });

    it('looks past a clarification answer to the prompt that started the turn', () => {
      expect(
        didLastPromptCarryAttachments([withContext('attachments'), clarificationAnswer()]),
      ).toBe(true);
    });
  });

  describe('isRetryAvailable', () => {
    it('is true when neither rule applies', () => {
      expect(isRetryAvailable([userMessage(), assistantMessage()])).toBe(true);
    });

    it('is false when the log was compacted since the last prompt', () => {
      expect(isRetryAvailable([userMessage(), assistantMessage(), compactionMessage()])).toBe(
        false,
      );
    });

    it('is false when the log ends on a slash command turn', () => {
      expect(isRetryAvailable([userMessage(), assistantMessage(), userMessage('/compact')])).toBe(
        false,
      );
    });

    it('is true when nothing was passed', () => {
      expect(isRetryAvailable()).toBe(true);
    });
  });
});
