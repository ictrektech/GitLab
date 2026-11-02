const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');
const source = fs.readFileSync(path.resolve(__dirname, '../../lib/gitlab/auth/vos/fastpath.js'), 'utf8');

async function run({ mode = 'callback', mismatch = false, bridge = true, secure = true } = {}) {
  let submitted = 0;
  let exchanged = 0;
  let authorization;
  const form = {
    dataset: { mode, state: 'csrf-state', clientId: 'com.ictrek.gitlab' },
    elements: { access_token: { value: '' } }, submit: () => { submitted += 1; },
  };
  const status = { textContent: '', dataset: { errorMessage: 'Authentication failed: Please try again' }, setAttribute: () => {} };
  const oauth2 = {
    authorize: async (params) => {
      authorization = params;
      return { code: 'code', state: mismatch ? 'attacker-state' : params.state };
    },
    token: async (params) => {
      exchanged += 1;
      assert.equal(params.client_id, 'com.ictrek.gitlab');
      assert.ok(params.code_verifier.length >= 43);
      return { access_token: 'test-access-token', refresh_token: 'must-not-be-stored' };
    },
  };
  const window = { crypto: secure ? webcrypto : undefined };
  window.parent = window;
  if (bridge === true) window.vos_platform = { api: { v1000: { oauth2 } } };
  if (bridge === 'delayed') setTimeout(() => { window.vos_platform = { api: { v1000: { oauth2 } } }; }, 5);
  const document = { getElementById: (id) => id === 'vos-auth-form' ? form : status };
  vm.runInNewContext(source, { window, document, crypto: window.crypto, TextEncoder, Uint8Array, btoa,
    setTimeout: (callback) => setTimeout(callback, 1) });
  for (let attempt = 0; attempt < 200 && !submitted && !status.textContent; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  return { submitted, exchanged, form, status, authorization };
}

test('initiates login through the native CSRF-protected POST form', async () => {
  const result = await run({ mode: 'start' });
  assert.equal(result.submitted, 1);
  assert.equal(result.exchanged, 0);
});

test('uses PKCE and submits only the access token to the native callback', async () => {
  const result = await run();
  assert.equal(result.submitted, 1);
  assert.equal(result.form.elements.access_token.value, 'test-access-token');
  assert.equal(result.authorization.code_challenge_method, 'S256');
  assert.ok(result.authorization.code_challenge.length >= 43);
  assert.ok(!JSON.stringify(result.form).includes('must-not-be-stored'));
});

test('rejects mismatched authorization state before exchanging a code', async () => {
  const result = await run({ mismatch: true });
  assert.equal(result.submitted, 0);
  assert.equal(result.exchanged, 0);
  assert.match(result.status.textContent, /failed/);
});

test('fails closed without a VOS bridge', async () => {
  assert.equal((await run({ bridge: false })).submitted, 0);
});

test('waits for the bridge injected after the iframe loads', async () => {
  assert.equal((await run({ bridge: 'delayed' })).submitted, 1);
});

test('requires trusted HTTPS crypto support', async () => {
  assert.equal((await run({ secure: false })).exchanged, 0);
});
