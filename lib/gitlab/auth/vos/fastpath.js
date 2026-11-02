/* VOS Fastpath bootstrap. Tokens stay in memory until the same-origin POST callback. */
(() => {
  const form = document.getElementById('vos-auth-form');
  const status = document.getElementById('vos-status');
  const base64url = (bytes) => btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  async function oauthBridge() {
    // VOS injects its bridge on iframe load, after deferred scripts can run.
    for (let attempt = 0; attempt < 100; attempt += 1) {
      let bridge = window.vos_platform;
      if (!bridge && window.parent !== window) bridge = window.parent.vos_platform;
      const oauth = bridge?.api?.v1000?.oauth2;
      if (oauth?.authorize && oauth?.token) return oauth;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    throw new Error('Open GitLab inside VOS to sign in.');
  }

  async function signIn() {
    if (!form) return;
    if (form.dataset.mode === 'start') {
      form.submit();
      return;
    }
    if (!window.crypto?.subtle) throw new Error('VOS sign-in requires a trusted HTTPS connection.');
    const oauth = await oauthBridge();
    const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
    const challenge = base64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
    const state = form.dataset.state;
    const authorization = await oauth.authorize({
      client_id: form.dataset.clientId,
      response_type: 'code', scope: 'openid profile email', state,
      code_challenge: challenge, code_challenge_method: 'S256',
    });
    if (!authorization?.code || authorization.state !== state) throw new Error('VOS authorization state mismatch.');
    const tokens = await oauth.token({
      client_id: form.dataset.clientId, grant_type: 'authorization_code',
      code: authorization.code, code_verifier: verifier,
    });
    if (typeof tokens?.access_token !== 'string' || !tokens.access_token) throw new Error('VOS did not return an access token.');
    form.elements.access_token.value = tokens.access_token;
    form.submit();
  }
  signIn().catch(() => {
    status.textContent = status.dataset.errorMessage;
    status.setAttribute('role', 'alert');
  });
})();
