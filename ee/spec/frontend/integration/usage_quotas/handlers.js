import { join } from 'node:path';
import { HttpResponse } from 'msw';
import {
  createFixturePaginator,
  loadFixturesMap,
  mapStaticOperationHandlers,
} from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/usage_quotas/pipelines/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

const paginateProjects = createFixturePaginator({ lookupKey: 'ciMinutesProjectMonthlyUsage' });

const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  getProjectsCiMinutesUsage: ({ variables }) =>
    paginateProjects(fixtures.getProjectsCiMinutesUsage, variables),
};

export function handleUsageQuotasOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const usageQuotasRestEndpoints = [];
