import { __ } from '~/locale';
import { createRoutes as createCeRoutes } from '~/explore/analytics_dashboards/routes';
import { EDIT_DASHBOARD_PATH } from 'ee/explore/analytics_dashboards/components/dashboards_list/constants';
import DashboardEdit from './pages/edit.vue';

const createEditRoute = (breadcrumbState) => ({
  name: 'dashboard-edit',
  path: `/:slug/${EDIT_DASHBOARD_PATH}`,
  component: DashboardEdit,
  meta: {
    getName: () => __('Edit'),
    getParents: () => [
      {
        text: breadcrumbState.name,
        to: `/${breadcrumbState.slug}`,
      },
    ],
  },
});

export const createRoutes = (breadcrumbState) => [
  ...createCeRoutes(breadcrumbState),
  ...(gon.features?.customDashboardStorage ? [createEditRoute(breadcrumbState)] : []),
];
