/* Keep the VOS bridge alive while native GitLab pages navigate. */
(() => {
  const frame = document.getElementById('vos-gitlab');
  if (!frame) return;
  const locales = JSON.parse(frame.dataset.locales);
  const normalize = (value) => String(value || '').replace(/-/g, '_').toLowerCase();
  const language = (value) => locales.find((item) => normalize(item) === normalize(value))
    || locales.find((item) => normalize(item) === normalize(value).split('_')[0]) || 'en';
  let desired;
  let syncing = false;
  let revision = 0;
  let unsubscribe;

  async function synchronize() {
    if (!desired || syncing) return;
    syncing = true;
    try {
      const page = frame.contentDocument;
      if (!frame.contentWindow.gon?.current_user_id || !page) return;
      const csrf = page.querySelector('meta[name="csrf-token"]')?.content;
      if (!csrf) return;
      const rendered = language(page.documentElement.lang);
      let applied = rendered;
      while (applied !== desired) {
        const target = desired;
        const response = await fetch(frame.dataset.preferencesUrl, {
          method: 'PATCH', credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrf },
          body: JSON.stringify({ user: { preferred_language: target } }),
        });
        if (!response.ok) throw new Error('Language preference update failed');
        applied = target;
      }
      if (frame.contentDocument === page && rendered !== applied) frame.contentWindow.location.reload();
    } catch (_) {
      console.warn('VOS language synchronization failed');
    } finally {
      syncing = false;
    }
  }

  function apply(state) {
    if (!state?.locale) return;
    desired = language(state.locale);
    void synchronize();
  }

  frame.addEventListener('load', () => { void synchronize(); });
  window.addEventListener('pagehide', () => { unsubscribe?.(); });
  (async () => {
    for (let attempt = 0; attempt < 100; attempt += 1) {
      const bridge = window.vos_platform;
      if (bridge?.getState) {
        unsubscribe = bridge.broadcast?.on('locale-change', (state) => {
          revision += 1;
          apply(state);
        });
        const before = revision;
        const state = await bridge.getState();
        if (revision === before) apply(state);
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  })().catch(() => { console.warn('VOS language state is unavailable'); });
})();
