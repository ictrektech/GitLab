import { GlPopover } from '@gitlab/ui';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';

const mountVuePopover = (el) =>
  initVueApp({
    el,
    name: 'GlPopoverRoot',
    component: GlPopover,
    attrs: JSON.parse(el.dataset.appData),
  });

export default () => [...document.querySelectorAll('.js-vue-popover')].map(mountVuePopover);
