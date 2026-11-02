import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import Insights from './components/insights.vue';
import createRouter from './insights_router';

export default () => {
  const el = document.querySelector('#js-insights-pane');
  const { endpoint, queryEndpoint, notice, namespaceType, fullPath } = el.dataset;
  const router = createRouter(endpoint);

  if (!el) return null;

  return initVueApp({
    el,
    name: 'InsightsRoot',
    pinia,
    router,
    provide: {
      fullPath,
      isProject: namespaceType === 'project',
    },
    component: Insights,
    props: {
      endpoint,
      queryEndpoint,
      notice,
    },
  });
};
