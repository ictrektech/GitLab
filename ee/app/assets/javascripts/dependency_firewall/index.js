import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import createDefaultClient from '~/lib/graphql';

Vue.use(VueApollo);

const apolloProvider = new VueApollo({
  defaultClient: createDefaultClient(),
});

export default (el) => {
  if (!el) return null;

  const { fullPath, namespaceType, newPolicyPath, disableNewPolicy, dashboardV2Enabled } =
    el.dataset;
  // TODO: remove once dependency_firewall_dashboard_v2 is the only dashboard
  // https://gitlab.com/gitlab-org/gitlab/-/work_items/631486
  const DashboardApp = parseBoolean(dashboardV2Enabled)
    ? () => import('./components/dashboard_v2_app.vue')
    : () => import('./components/dashboard_v1_app.vue');

  return new Vue({
    el,
    name: 'DependencyFirewallDashboardRoot',
    apolloProvider,
    provide: { namespaceType },
    render(createElement) {
      return createElement(DashboardApp, {
        props: {
          fullPath,
          namespaceType,
          newPolicyPath,
          disableNewPolicy: parseBoolean(disableNewPolicy),
        },
      });
    },
  });
};
