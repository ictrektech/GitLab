import { s__ } from '~/locale';

export const ROUTE_OVERVIEW = 'overview';
export const ROUTE_SCHEMA = 'schema';
export const ROUTE_QUERY = 'query';
export const ROUTE_GROUP_STATUS = 'group_status';

export const ORBIT_TABS = [
  { route: ROUTE_OVERVIEW, label: s__('Orbit|Overview'), eventName: 'click_orbit_overview_tab' },
  { route: ROUTE_SCHEMA, label: s__('Orbit|Schema'), eventName: 'click_orbit_schema_tab' },
  {
    route: ROUTE_QUERY,
    label: s__('Orbit|Query editor'),
    eventName: 'click_orbit_query_editor_tab',
  },
  {
    route: ROUTE_GROUP_STATUS,
    label: s__('Orbit|Status'),
    eventName: 'click_orbit_group_status_tab',
  },
];

export const FEEDBACK_URL = 'https://gitlab.com/groups/gitlab-org/-/work_items/22266';
export const GROUPS_POLL_INTERVAL_MS = 20000;
export const LOAD_STATUS = {
  LOADING: 'loading',
  FAILED: 'failed',
  READY: 'ready',
};
