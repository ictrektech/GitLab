import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import GranularScopesPicker from './components/granular_scopes_picker.vue';

export const initOAuthApplicationGranularScopes = () => {
  const el = document.querySelector('#js-oauth-application-granular-scopes');

  if (!el) {
    return null;
  }

  Vue.use(VueApollo);

  const { allowedAccessLevels, groupFullPath, groupName, initialScopes } = el.dataset;

  return initVueApp({
    el,
    name: 'OAuthApplicationGranularScopesRoot',
    apolloProvider: new VueApollo({ defaultClient: createDefaultClient() }),
    component: GranularScopesPicker,
    props: {
      allowedAccessLevels: JSON.parse(allowedAccessLevels),
      groupFullPath,
      groupName,
      initialScopes: JSON.parse(initialScopes || '[]'),
    },
  });
};
