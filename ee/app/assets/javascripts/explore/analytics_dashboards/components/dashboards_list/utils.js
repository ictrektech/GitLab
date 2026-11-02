import {
  NAME_FIELD,
  AUTHOR_FIELD,
  UPDATED_AT_FIELD,
  ACTIONS_FIELD,
} from '~/explore/analytics_dashboards/components/dashboards_list/constants';

export const getDashboardsListFields = () =>
  gon.features?.customDashboardStorage
    ? [NAME_FIELD, AUTHOR_FIELD, UPDATED_AT_FIELD, ACTIONS_FIELD]
    : [NAME_FIELD, AUTHOR_FIELD, ACTIONS_FIELD];
