import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import MergeScheduleInput from '~/merge_requests/components/merge_schedule_input.vue';

export default () => {
  const el = document.querySelector('.js-merge-request-schedule-input');

  if (!el) return false;

  const { mergeAfter, mergeBefore, paramKey } = el.dataset;

  return initVueApp({
    el,
    name: 'MergeScheduleInputRoot',
    component: MergeScheduleInput,
    props: {
      mergeAfter,
      mergeBefore,
      paramKey,
    },
  });
};
