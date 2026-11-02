import { join } from 'node:path';
import { HttpResponse } from 'msw';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
  matchFixture,
} from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_blob_controls';
import './fixture_variants/get_project_info';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/repository/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

// toggleLock flips this so the projectInfo refetch returns the new lock state.
// The locked fixture holds both paths the specs lock (VERSION and encoding).
let isLocked = false;

// Called by the domain mount helper, so every mounted page starts unlocked.
export function resetPathLockState() {
  isLocked = false;
}

function toggleLockResponse({ lock }) {
  isLocked = lock;
  return lock ? fixtures.toggleLock : fixtures.toggleLockUnlock;
}

function projectInfoResponse() {
  return (
    getActiveVariant('getProjectInfoEE') ??
    (isLocked ? fixtures.getProjectInfoLocked : fixtures.getProjectInfo)
  );
}

const blobControlsFixtureTable = [
  {
    matches: ({ filePath }) => filePath === 'VERSION',
    fixture: () => fixtures.getBlobControls,
  },
  {
    matches: ({ filePath }) => filePath === 'encoding/test.txt',
    fixture: () => fixtures.getBlobControlsNested,
  },
  {
    matches: ({ filePath }) => filePath === 'files/images/logo-black.png',
    fixture: () => fixtures.getBlobControlsBinary,
  },
];

const DYNAMIC_OPERATION_HANDLERS = {
  getProjectInfoEE: projectInfoResponse,
  getBlobControls: ({ variables }) =>
    getActiveVariant('getBlobControls') ??
    matchFixture(variables, blobControlsFixtureTable, {
      guard: () => true,
      label: 'getBlobControls',
    }).fixture(),
  toggleLock: ({ variables }) => toggleLockResponse(variables),
};

// Fixture names match operation names, so every recorded fixture is served
// as-is unless a dynamic handler above overrides it.
const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  ...DYNAMIC_OPERATION_HANDLERS,
};

export function handleRepositoryOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

// The lock disclosure fetches extra details of the locking user when it opens.
export const repositoryRestEndpoints = [
  // Fire-and-forget internal event tracking; opening the code dropdown posts one.
  {
    name: 'trackInternalEvent',
    method: 'post',
    path: '/api/v4/usage_data/track_event',
    response: {},
  },
  {
    name: 'userDetails',
    method: 'get',
    path: /\/api\/v4\/users\/\d+$/,
    response: {
      id: 1,
      name: 'Lock Owner',
      username: 'lock-owner',
      job_title: 'Release manager',
      organization: 'GitLab',
      location: 'Terminal 3',
      local_time: '2:00 PM',
    },
  },
];
