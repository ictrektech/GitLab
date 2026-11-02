import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import BillableUsageReportApp from './components/app.vue';

export default () => {
  const el = document.getElementById('js-billable-usage-report');

  if (!el) {
    return null;
  }

  const { termsPath, reportPath, downloadPath, subscriptionPath } = el.dataset;

  return initVueApp({
    el,
    name: 'BillableUsageReportRoot',
    component: BillableUsageReportApp,
    props: {
      termsPath,
      reportPath,
      downloadPath,
      subscriptionPath,
    },
  });
};
