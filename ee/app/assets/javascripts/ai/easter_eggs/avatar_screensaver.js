// Easter egg: on GitLab.com, opening a Duo Chat with "screensaver" dims the page
// and bounces the user's header avatar around the viewport like an idle DVD
// player logo.
// Kept self-contained so it can be removed in one change: delete this file and
// revert its handful of import sites (grep "avatar_screensaver").

/* eslint-disable @gitlab/require-i18n-strings -- easter egg reply, intentionally untranslated */
import { breakpoints } from '@gitlab/ui/src/utils';
import { uniqueId } from 'lodash-es';
import { GENIE_CHAT_MODEL_ROLES } from 'ee/ai/constants';

const SCREENSAVER_COMMAND = 'screensaver';
const UNAVAILABLE_REPLY =
  "I can't start the screensaver easter egg with your current display or accessibility settings.";
const FADE_IN_MS = 1500;
const PAUSE_BEFORE_MOTION_MS = 500;
const SPEED_PX_PER_S = 150;
const HUE_STEP_DEG = 60;
const MAX_FRAME_MS = 50;
const MAX_CORNER_CHANCE = 0.3;
const CORNER_CHANCE_RAMP_S = 10 * 60;
const MAX_CORNER_TILT_RAD = (10 * Math.PI) / 180;

const ACTIVITY_EVENTS = [
  'pointermove',
  'pointerdown',
  'keydown',
  'wheel',
  'touchstart',
  'scroll',
  'resize',
];

let screensaver = null;

// Chrome dispatches a zero-movement pointermove when an element appears under
// a resting cursor, which would dismiss the screensaver the moment it shows.
const isRealInput = (event) =>
  event.type !== 'pointermove' || event.movementX !== 0 || event.movementY !== 0;

const isUnsuited = () =>
  window.innerWidth < breakpoints.md ||
  window.matchMedia?.(
    '(prefers-reduced-motion: reduce), (forced-colors: active), (pointer: coarse)',
  ).matches;

const reflect = (position, velocity, max) => {
  if (position <= 0) return { position: 0, velocity: Math.abs(velocity) };
  if (position >= max) return { position: max, velocity: -Math.abs(velocity) };
  return { position, velocity };
};

const cornerVelocity = ({ x, y, vx, vy, maxX, maxY }) => {
  const dx = Math.abs((vx > 0 ? maxX : 0) - x);
  const dy = Math.abs((vy > 0 ? maxY : 0) - y);
  const angle = Math.atan2(dy, dx);
  if (Math.abs(angle - Math.PI / 4) > MAX_CORNER_TILT_RAD) return null;

  const speed = Math.hypot(vx, vy);
  return {
    vx: Math.sign(vx) * speed * Math.cos(angle),
    vy: Math.sign(vy) * speed * Math.sin(angle),
  };
};

const step = (now) => {
  const s = screensaver;
  const elapsedS = Math.min(now - (s.lastFrameAt ?? now), MAX_FRAME_MS) / 1000;
  s.lastFrameAt = now;
  s.movingForS += elapsedS;

  const x = reflect(s.x + s.vx * elapsedS, s.vx, s.maxX);
  const y = reflect(s.y + s.vy * elapsedS, s.vy, s.maxY);
  const bounced = x.velocity !== s.vx || y.velocity !== s.vy;

  s.x = x.position;
  s.y = y.position;
  s.vx = x.velocity;
  s.vy = y.velocity;

  if (bounced) {
    s.hue = (s.hue + HUE_STEP_DEG) % 360;
    s.avatar.style.filter = `hue-rotate(${s.hue}deg)`;
    if (Math.random() < MAX_CORNER_CHANCE * Math.min(s.movingForS / CORNER_CHANCE_RAMP_S, 1)) {
      Object.assign(s, cornerVelocity(s));
    }
  }

  s.avatar.style.transform = `translate3d(${s.x}px, ${s.y}px, 0)`;
  s.frame = requestAnimationFrame(step);
};

const stop = () => {
  screensaver.listeners.abort();
  screensaver.fadeIn.cancel();
  cancelAnimationFrame(screensaver.frame);
  screensaver.scrim.remove();
  screensaver.original.style.visibility = '';
  screensaver = null;
};

const onActivity = (event) => {
  if (isRealInput(event)) stop();
};

const start = () => {
  if (screensaver) return true;
  if (isUnsuited()) return false;

  const original = document.querySelector('[data-testid="user-avatar-content"]');
  const { left, top, width, height } = original?.getBoundingClientRect() ?? {};
  if (!width) return false;

  const scrim = document.createElement('div');
  scrim.className = 'gl-pointer-events-none gl-fixed gl-inset-0 gl-z-9999 gl-bg-overlay';
  scrim.setAttribute('aria-hidden', 'true');

  const avatar = original.cloneNode(true);
  delete avatar.dataset.testid;
  avatar.classList.add('gl-absolute', 'gl-will-change-transform');
  avatar.style.transform = `translate3d(${left}px, ${top}px, 0)`;

  scrim.appendChild(avatar);
  document.body.appendChild(scrim);

  avatar.animate({ opacity: [0, 1] }, { duration: FADE_IN_MS, easing: 'ease-in-out' });

  const fadeIn = scrim.animate(
    { backgroundColor: ['transparent', 'var(--gl-background-color-overlay)'] },
    { duration: FADE_IN_MS, endDelay: PAUSE_BEFORE_MOTION_MS, easing: 'ease-in-out' },
  );
  fadeIn.onfinish = () => {
    original.style.visibility = 'hidden';
    screensaver.frame = requestAnimationFrame(step);
  };

  const listeners = new AbortController();
  ACTIVITY_EVENTS.forEach((type) =>
    window.addEventListener(type, onActivity, {
      capture: true,
      passive: true,
      signal: listeners.signal,
    }),
  );

  screensaver = {
    scrim,
    avatar,
    original,
    x: left,
    y: top,
    maxX: window.innerWidth - width,
    maxY: window.innerHeight - height,
    vx: -SPEED_PX_PER_S,
    vy: SPEED_PX_PER_S,
    hue: 0,
    movingForS: 0,
    fadeIn,
    listeners,
  };
  return true;
};

/**
 * Start the screensaver when the prompt is the command. When the screensaver
 * can't run here, a canned chat reply says so instead, added locally.
 * @param {string} prompt - A chat prompt.
 * @param {Function} addMessage - The chat store's `addDuoChatMessage` action.
 * @returns {boolean} Whether the prompt was the command, i.e. whether the
 *   caller should treat it as handled and not send it to the backend.
 */
export const maybeStartScreensaver = (prompt, addMessage) => {
  if (!window.gon.dot_com || prompt?.trim().toLowerCase() !== SCREENSAVER_COMMAND) return false;

  if (!start()) {
    const requestId = uniqueId('avatar-screensaver-');
    addMessage({ role: GENIE_CHAT_MODEL_ROLES.user, content: prompt, requestId });
    addMessage({ role: GENIE_CHAT_MODEL_ROLES.assistant, content: UNAVAILABLE_REPLY, requestId });
  }

  return true;
};
