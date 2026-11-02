import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';

import ScimToken from './components/scim_token.vue';

export function initScimTokenApp() {
  const el = document.getElementById('js-scim-token-app');

  if (!el) return null;

  const { endpointUrl, generateTokenPath, samlProviderEnabled } = el.dataset;

  return initVueApp({
    el,
    name: 'ScimTokenRoot',
    provide: {
      initialEndpointUrl: endpointUrl,
      generateTokenPath,
      samlProviderEnabled: parseBoolean(samlProviderEnabled),
    },
    component: ScimToken,
  });
}
