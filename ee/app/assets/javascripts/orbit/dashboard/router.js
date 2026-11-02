import VueRouter from 'vue-router';
import { s__ } from '~/locale';
import OrbitSchemaPage from './schema/orbit_schema_page.vue';
import { ROUTE_GROUP_STATUS, ROUTE_OVERVIEW, ROUTE_QUERY, ROUTE_SCHEMA } from './constants';
import OrbitGroupStatusPage from './group_status/orbit_group_status_page.vue';
import OrbitOverviewPage from './overview/orbit_overview_page.vue';
import OrbitQueryEditorPage from './query_editor/orbit_query_editor_page.vue';

export default function createDashboardRouter(base) {
  return new VueRouter({
    mode: 'history',
    base,
    routes: [
      {
        path: '/',
        redirect: { name: ROUTE_OVERVIEW },
      },
      {
        name: ROUTE_OVERVIEW,
        path: '/overview',
        component: OrbitOverviewPage,
        meta: { name: s__('Orbit|Overview') },
      },
      {
        name: ROUTE_SCHEMA,
        path: '/schema',
        component: OrbitSchemaPage,
        meta: { name: s__('Orbit|Schema') },
      },
      {
        name: ROUTE_QUERY,
        path: '/query',
        component: OrbitQueryEditorPage,
        meta: { name: s__('Orbit|Query editor') },
      },
      {
        name: ROUTE_GROUP_STATUS,
        path: '/group-status',
        component: OrbitGroupStatusPage,
        meta: { name: s__('Orbit|Status') },
      },
      { path: '/explore', redirect: { name: ROUTE_OVERVIEW } },
      { path: '/configuration', redirect: { name: ROUTE_OVERVIEW } },
      // A path, not a name: on Vue 3, a named redirect would pass on the catch-all param.
      { path: '*', redirect: '/overview' },
    ],
  });
}
