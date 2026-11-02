const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../../lib/gitlab/auth/vos/locale.js'), 'utf8');
const tick = () => new Promise((resolve) => setTimeout(resolve, 5));

async function setup({ locale = 'zh-CN', rendered = 'en', authenticated = true, delayedState = false, delayedPatch = false } = {}) {
  const calls = [];
  const listeners = {};
  let event;
  let resolveState;
  let resolvePatch;
  let reloaded = 0;
  let preference = rendered;
  let unsubscribed = false;
  const page = { documentElement: { lang: rendered }, querySelector: () => ({ content: 'native-csrf' }) };
  const frame = {
    dataset: { locales: JSON.stringify(['en', 'zh_CN', 'zh_TW', 'fr']), preferencesUrl: '/app/com.ictrek.gitlab/-/profile/preferences' },
    contentDocument: page,
    contentWindow: { gon: { current_user_id: authenticated ? 1 : null }, location: { reload: () => {
      reloaded += 1; page.documentElement.lang = preference; setTimeout(() => listeners.load(), 0);
    } } },
    addEventListener: (name, callback) => { listeners[name] = callback; },
  };
  const bridge = {
    getState: () => delayedState ? new Promise((resolve) => { resolveState = resolve; }) : Promise.resolve({ locale }),
    broadcast: { on: (name, callback) => { assert.equal(name, 'locale-change'); event = callback; return () => { unsubscribed = true; }; } },
  };
  const window = { vos_platform: bridge, addEventListener: (name, callback) => { listeners[name] = callback; } };
  vm.runInNewContext(source, {
    window, document: { getElementById: () => frame }, setTimeout, console,
    fetch: async (url, options) => {
      assert.equal(url, frame.dataset.preferencesUrl);
      assert.equal(options.method, 'PATCH');
      assert.equal(options.credentials, 'same-origin');
      assert.equal(options.headers['X-CSRF-Token'], 'native-csrf');
      preference = JSON.parse(options.body).user.preferred_language;
      calls.push(preference);
      if (delayedPatch && calls.length === 1) await new Promise((resolve) => { resolvePatch = resolve; });
      return { ok: true };
    },
  });
  await tick();
  return { calls, frame, listeners, change: (value) => event({ locale: value }), resolveState: (value) => resolveState(value),
    resolvePatch: () => resolvePatch(), reloaded: () => reloaded, unsubscribed: () => unsubscribed };
}

test('applies the initial VOS language through native CSRF-protected preferences', async () => {
  const state = await setup();
  assert.deepEqual(state.calls, ['zh_CN']);
  assert.equal(state.reloaded(), 1);
  await tick();
  assert.equal(state.reloaded(), 1);
});

test('follows live language changes and avoids updates when unchanged', async () => {
  const state = await setup({ locale: 'en-US' });
  assert.deepEqual(state.calls, []);
  state.change('zh-CN'); await tick();
  state.change('en-US'); await tick();
  assert.deepEqual(state.calls, ['zh_CN', 'en']);
  assert.equal(state.reloaded(), 2);
  state.listeners.pagehide();
  assert.equal(state.unsubscribed(), true);
});

test('waits until the inner GitLab session is authenticated', async () => {
  const state = await setup({ authenticated: false });
  assert.deepEqual(state.calls, []);
  state.frame.contentWindow.gon.current_user_id = 1;
  state.listeners.load(); await tick();
  assert.deepEqual(state.calls, ['zh_CN']);
});

test('a live language event takes precedence over a delayed initial snapshot', async () => {
  const state = await setup({ delayedState: true });
  state.change('zh-CN'); await tick();
  state.resolveState({ locale: 'en-US' }); await tick();
  assert.deepEqual(state.calls, ['zh_CN']);
});

test('serializes rapid changes and keeps the final selected language', async () => {
  const state = await setup({ delayedPatch: true });
  state.change('en-US'); state.resolvePatch(); await tick();
  assert.deepEqual(state.calls, ['zh_CN', 'en']);
  assert.equal(state.frame.contentDocument.documentElement.lang, 'en');
});
