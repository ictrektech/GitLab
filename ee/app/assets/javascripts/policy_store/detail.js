import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import App from './components/detail/app.vue';
import createApolloProvider from './apollo';

export default (el) => {
  if (!el) return null;

  const {
    organizationId,
    namespacePath,
    namespaceType,
    policyId,
    canUpdatePolicy,
    canDeletePolicy,
    listPath,
    editPath,
  } = el.dataset;

  return initVueApp({
    el,
    apolloProvider: createApolloProvider(),
    name: 'PolicyStoreDetailRoot',
    provide: {
      organizationId,
      namespacePath: namespacePath || '',
      namespaceType: namespaceType || '',
      policyId,
      canUpdatePolicy: parseBoolean(canUpdatePolicy),
      canDeletePolicy: parseBoolean(canDeletePolicy),
      listPath: listPath || '',
      editPath: editPath || '',
    },
    component: App,
  });
};
