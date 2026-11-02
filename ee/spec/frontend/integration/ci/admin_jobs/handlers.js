import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { isEqual } from 'lodash-es';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
  matchFixture,
} from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_all_jobs';
import './fixture_variants/get_all_jobs_count';
import './fixture_variants/get_cancelable_jobs_count';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/ci/admin_jobs/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

// What the Finished tab sends, built from the `jobStatuses` the page provides.
export const FINISHED_STATUSES = ['SUCCESS', 'FAILED', 'CANCELED'];
export const FAILED_STATUS = 'FAILED';

// The filtered search sends a single status as a bare string, which GraphQL coerces to a list.
const isFailedFilter = (statuses) =>
  statuses === FAILED_STATUS || isEqual(statuses, [FAILED_STATUS]);

const allJobsFixtureTable = [
  { matches: ({ statuses }) => !statuses, fixture: () => fixtures.getAllJobs },
  {
    matches: ({ statuses }) => isEqual(statuses, FINISHED_STATUSES),
    fixture: () => fixtures.getAllJobsFinished,
  },
  { matches: ({ statuses }) => isFailedFilter(statuses), fixture: () => fixtures.getAllJobsFailed },
];

const allJobsCountFixtureTable = [
  { matches: ({ statuses }) => !statuses, fixture: () => fixtures.getAllJobsCount },
  {
    matches: ({ statuses }) => isFailedFilter(statuses),
    fixture: () => fixtures.getAllJobsCountFailed,
  },
];

const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  getAllJobs: ({ variables }) =>
    getActiveVariant('getAllJobs') ??
    matchFixture(variables, allJobsFixtureTable, {
      guard: () => true,
      label: 'getAllJobs',
    }).fixture(),
  getAllJobsCount: ({ variables }) =>
    getActiveVariant('getAllJobsCount') ??
    matchFixture(variables, allJobsCountFixtureTable, {
      guard: () => true,
      label: 'getAllJobsCount',
    }).fixture(),
};

export function handleAdminJobsOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const adminJobsRestEndpoints = [
  // The app tracks a pageload internal event on mount.
  {
    method: 'post',
    path: /\/api\/v4\/usage_data\/track_event/,
    response: {},
    name: 'trackInternalEvent',
  },
];
