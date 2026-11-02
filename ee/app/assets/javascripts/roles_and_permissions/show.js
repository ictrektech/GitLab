import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import RoleDetails from './components/role_details/role_details.vue';

Vue.use(VueApollo);

const apolloProvider = new VueApollo({
  defaultClient: createDefaultClient(),
});

export const initRoleDetailsApp = () => {
  const el = document.querySelector('#js-role-details');

  if (!el) {
    return null;
  }

  return initVueApp({
    el,
    name: 'RoleDetailsRoot',
    apolloProvider,
    component: RoleDetails,
    props: {
      roleId: el.dataset.id,
      listPagePath: el.dataset.listPagePath,
      isAdminRole: parseBoolean(el.dataset.isAdminRole),
    },
  });
};
