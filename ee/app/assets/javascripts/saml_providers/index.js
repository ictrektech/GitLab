import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';

import SamlSettingsForm from 'ee/saml_providers/saml_settings_form';
import initSamlMembershipRoleSelector from 'ee/saml_providers/saml_membership_role_selector';
import { initScimTokenApp } from 'ee/saml_providers/scim_token';

import MembersApp from './saml_members/index.vue';
import { useSamlMembers } from './saml_members/store';

function initMembers(el) {
  const { groupId } = el.dataset;
  useSamlMembers(pinia).setInitialState({
    groupId: Number(groupId),
  });

  initVueApp({ el, name: 'MembersAppRoot', pinia, component: MembersApp });
}

export function initSamlProvidersApp() {
  const membersEl = document.querySelector('.js-saml-members');
  initMembers(membersEl);

  initSamlMembershipRoleSelector();
  new SamlSettingsForm('#js-saml-settings-form').init();
  initScimTokenApp();
}
