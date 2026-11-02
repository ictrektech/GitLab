import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';
import { inviteSearchOrganizationAdminUsersPath } from '~/lib/utils/path_helpers/organization_admin';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import OrganizationAccessApp from './components/organization_access_app.vue';
import OrganizationAccessResourceApp from './components/resource_access_app.vue';
import { RESOURCE_ARTIFACT_REGISTRY } from './constants';
import { mockResolvers } from './graphql/mock_resolvers';

Vue.use(VueApollo);

const createApolloProvider = () =>
  new VueApollo({ defaultClient: createDefaultClient(mockResolvers) });

export const initOrganizationAccess = () => {
  const el = document.getElementById('js-organization-access');

  if (!el) return false;

  const { organizationPath } = el.dataset;

  return initVueApp({
    el,
    name: 'OrganizationAccessRoot',
    component: OrganizationAccessApp,
    apolloProvider: createApolloProvider(),
    props: { organizationPath },
  });
};

export const initOrganizationAccessArtifactRegistry = () => {
  const el = document.getElementById('js-organization-access-artifact-registry');

  if (!el) return false;

  return initVueApp({
    el,
    name: 'OrganizationAccessArtifactRegistryRoot',
    component: OrganizationAccessResourceApp,
    apolloProvider: createApolloProvider(),
    provide: {
      // Stopgap: this returns users who aren't in the org yet.
      // https://gitlab.com/gitlab-org/gitlab/-/work_items/629712 switches it to an org member search.
      searchUrl: inviteSearchOrganizationAdminUsersPath(el.dataset.organizationPath, {
        format: 'json',
      }),
    },
    props: { resourceKey: RESOURCE_ARTIFACT_REGISTRY },
  });
};
