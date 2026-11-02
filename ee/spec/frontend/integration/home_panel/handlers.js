import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { loadFixturesMap, matchFixture } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_project_by_path';
import './fixture_variants/set_star_status';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/home_panel/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

// Starring returns the incremented count, unstarring the decremented one.
const starFixtureTable = [
  { matches: ({ starred }) => starred === true, fixture: () => fixtures.setStarStatus },
  { matches: ({ starred }) => starred === false, fixture: () => fixtures.setStarStatusUnstar },
];

const OPERATION_HANDLERS = {
  getProjectByPath: () => getActiveVariant('getProjectByPath') ?? fixtures.getProjectByPath,
  setStarStatus: ({ variables }) =>
    getActiveVariant('setStarStatus') ??
    matchFixture(variables, starFixtureTable, {
      guard: () => true,
      label: 'setStarStatus',
    }).fixture(),
};

export function handleHomePanelOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

// The custom notifications modal reads `events` from both responses; the PUT
// response flips new_note on so toggling an event renders an observable change.
const NOTIFICATION_EVENTS = {
  new_note: false,
  new_issue: false,
  reopen_issue: false,
  close_issue: false,
  reassign_issue: false,
  issue_due: false,
  new_merge_request: false,
  push_to_merge_request: false,
  reopen_merge_request: false,
  close_merge_request: false,
  reassign_merge_request: false,
  merge_merge_request: false,
  failed_pipeline: false,
  fixed_pipeline: false,
  success_pipeline: false,
  moved_project: false,
};

const NOTIFICATION_SETTINGS_PATH = /\/api\/v4\/projects\/\d+\/notification_settings$/;

export const homePanelRestEndpoints = [
  {
    name: 'getNotificationSettings',
    method: 'get',
    path: NOTIFICATION_SETTINGS_PATH,
    response: { level: 'custom', events: NOTIFICATION_EVENTS },
  },
  {
    name: 'updateNotificationSettings',
    method: 'put',
    path: NOTIFICATION_SETTINGS_PATH,
    response: { level: 'custom', events: { ...NOTIFICATION_EVENTS, new_note: true } },
  },
];
