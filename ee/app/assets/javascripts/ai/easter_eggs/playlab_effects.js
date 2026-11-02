/* eslint-disable @gitlab/require-i18n-strings -- easter egg replies, intentionally untranslated */
import { confetti, matrix } from '@gitlab/ui/src/utils';
import { sample, uniqueId } from 'lodash-es';
import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';

const MATRIX = {
  play: matrix,
  replies: ["You're in.", 'Access granted.', 'Welcome to the mainframe.'],
};

const CONFETTI = {
  play: confetti,
  replies: ['[throws confetti]', '🎉', '🥳'],
};

const TRIGGERS = [
  [/^(i['’]?m|i am|we['’]?re|we are) in$/, MATRIX],
  [/^(it['’]s|it is|today['’]s|today is) my birth ?day$/, CONFETTI],
  [/^happy birthday$/, CONFETTI],
  [/^congrats$/, CONFETTI],
  [/^congratulations$/, CONFETTI],
  [/^confetti$/, CONFETTI],
  [/^let['’]s celebrate$/, CONFETTI],
  [/^woohoo$/, CONFETTI],
];

/**
 * Play the effect for the prompt when it is one of the trigger phrases. Users who
 * prefer reduced motion get a canned chat reply instead, added locally.
 * @param {string} prompt - A chat prompt.
 * @param {Function} addMessage - The chat store's `addDuoChatMessage` action.
 * @returns {boolean} Whether the prompt was a trigger, i.e. whether the caller
 *   should treat it as handled and not send it to the backend.
 */
export const maybePlayEffect = (prompt, addMessage) => {
  const normalized = prompt
    ?.trim()
    .toLowerCase()
    .replace(/[.!]+$/, '');
  const trigger = normalized && TRIGGERS.find(([pattern]) => pattern.test(normalized));
  if (!trigger) return false;

  const [, { play, replies }] = trigger;

  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
    const requestId = uniqueId('playlab-effect-');
    addMessage({ role: GENIE_CHAT_MODEL_ROLES.user, content: prompt, requestId });
    addMessage({ role: GENIE_CHAT_MODEL_ROLES.assistant, content: sample(replies), requestId });
  } else {
    play();
  }

  return true;
};
