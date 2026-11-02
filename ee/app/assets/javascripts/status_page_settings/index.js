import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import StatusPageSettings from './components/settings_form.vue';
import { useStatusPageSettings } from './store';

export default () => {
  const el = document.querySelector('.js-status-page-settings');

  if (!el) {
    return null;
  }

  useStatusPageSettings(pinia).setInitialState(el.dataset);

  return initVueApp({
    el,
    name: 'StatusPageSettingsRoot',
    pinia,
    component: StatusPageSettings,
  });
};
