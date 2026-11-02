import { join } from 'node:path';
import { parse, print, visit } from 'graphql';
import { graphql, HttpResponse } from 'msw';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
} from 'ee_jest/integration/core/fixture_utils';
import { captureMissingOperation } from 'ee_jest/integration/core/operation_helpers';
import './fixture_variants/get_dashboards';
import './fixture_variants/get_system_dashboard';
import './fixture_variants/get_analytics_dashboard_scope_namespace';
import './fixture_variants/get_analytics_dashboard_duo_agent_platform_top_level_groups';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/explore/analytics_dashboards/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const systemDashboardResponse = fixtures.getSystemDashboard;
export const scopeNamespaceResponse = fixtures.getAnalyticsDashboardScopeNamespace;
export const dashboardsResponse = fixtures.getDashboards;

export const GLQL_OPERATION = 'GLQL';

// Apollo adds `__typename` to every selection, so it is stripped before comparing.
const normalizeQuery = (query) =>
  print(
    visit(parse(query), {
      Field: (node) => (node.name.value === '__typename' ? null : undefined),
    }),
  );

const glqlResponses = new Map(
  Object.entries(fixtures.dapImpactGlqlResponses).map(([query, entry]) => [
    normalizeQuery(query),
    entry,
  ]),
);

function handleGlqlOperation({ query, variables }) {
  const entry = glqlResponses.get(normalizeQuery(query));

  // Each recorded response is a single page.
  if (!entry || variables.after) {
    captureMissingOperation(`${GLQL_OPERATION} query with no recorded response:\n${query}`);

    return new HttpResponse(null, { status: 400 });
  }

  return HttpResponse.json(entry.response);
}

const OPERATION_HANDLERS = mapStaticOperationHandlers(fixtures);

export function handleAnalyticsDashboardOperation({ operationName }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler());
}

export const analyticsDashboardRestEndpoints = [
  {
    name: 'trackInternalEvents',
    method: 'post',
    path: '/api/v4/usage_data/track_events',
    response: {},
  },
];

// For `server.use`: answers the named panels' queries with `resolver`, and passes the rest
// through to the recorded responses. Panels that share a query get the same answer.
export const respondToGlqlPanels = (titles, resolver) =>
  graphql.link('*/api/glql').operation(({ query }) => {
    const entry = glqlResponses.get(normalizeQuery(query));

    return entry?.panels.some((title) => titles.includes(title)) ? resolver() : undefined;
  });

// Matched on the query text, since every GLQL request shares one operation name.
export const analyticsDashboardGlqlHandlers = [
  graphql.link('*/api/glql').operation(handleGlqlOperation),
];
