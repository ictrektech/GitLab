import { confetti, matrix } from '@gitlab/ui/src/utils';
import { maybePlayEffect } from 'ee/ai/easter_eggs/playlab_effects';

jest.mock('@gitlab/ui/src/utils', () => ({ confetti: jest.fn(), matrix: jest.fn() }));

describe('playlab_effects easter egg', () => {
  const addMessage = jest.fn();

  it.each(["I'm in", 'i’m in', 'Im in', '  I AM IN  ', "We're in", 'we are in.'])(
    'plays matrix for %p',
    (prompt) => {
      expect(maybePlayEffect(prompt, addMessage)).toBe(true);
      expect(matrix).toHaveBeenCalledTimes(1);
      expect(confetti).not.toHaveBeenCalled();
    },
  );

  it.each([
    "It's my birthday",
    "it's my birth day",
    'It is my birthday',
    'it is my birth day',
    "Today's my birthday",
    'Today is my birthday',
    'today is my birth day',
    'CONFETTI',
    "Let's celebrate",
    'Woohoo',
    'woohoo!!!',
    "It's my birthday!",
    'Happy birthday!!',
    'Congrats!',
    'Congratulations',
  ])('plays confetti for %p', (prompt) => {
    expect(maybePlayEffect(prompt, addMessage)).toBe(true);
    expect(confetti).toHaveBeenCalledTimes(1);
    expect(matrix).not.toHaveBeenCalled();
  });

  it.each([
    "I'm in trouble",
    'I know kung fu',
    'Take the red pill',
    'what is confetti',
    'woohoo?',
    'congrats on the release, can you summarize it',
    'do a barrel roll',
    '',
    null,
    undefined,
  ])('plays nothing for %p', (prompt) => {
    expect(maybePlayEffect(prompt, addMessage)).toBe(false);
    expect(addMessage).not.toHaveBeenCalled();
    expect(matrix).not.toHaveBeenCalled();
    expect(confetti).not.toHaveBeenCalled();
  });

  describe('when the user prefers reduced motion', () => {
    beforeEach(() => {
      jest.spyOn(window, 'matchMedia').mockReturnValue({ matches: true });
    });

    it.each([
      ["I'm in", matrix],
      ['confetti', confetti],
    ])('replies in chat for %p instead of playing the effect', (prompt, effect) => {
      expect(maybePlayEffect(prompt, addMessage)).toBe(true);
      expect(effect).not.toHaveBeenCalled();
      expect(addMessage.mock.calls).toEqual([
        [expect.objectContaining({ role: 'user', content: prompt })],
        [expect.objectContaining({ role: 'assistant', content: expect.any(String) })],
      ]);
    });
  });
});
