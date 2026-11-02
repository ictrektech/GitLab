import { RESOURCE_ACCESS_ERROR } from '~/graphql_shared/constants';
import {
  HTTP_STATUS_FORBIDDEN,
  HTTP_STATUS_NOT_FOUND,
  HTTP_STATUS_UNAUTHORIZED,
} from '~/lib/utils/http_status';
import { s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { trialEnded } from 'ee/orbit/access/turn_on_action';
import { ORBIT_AREAS } from '../../constants';
import {
  ACTION_ERROR_KIND,
  ACTION_EXCLUDE,
  ACTION_INCLUDE,
  ACTION_LABELS,
  ACTION_TURN_OFF,
  ACTION_TURN_ON,
  ACTIVE_INDEXING_STATES,
  CONFIRM_EXCLUDE,
  CONFIRM_TURN_OFF,
  INDEXING_STATE,
  INDEXING_STATE_LABELS,
  TURN_ON_TRACKING_LABEL,
} from './constants';

const REPORTED_ERROR_KINDS = [ACTION_ERROR_KIND.SERVER, ACTION_ERROR_KIND.NETWORK];
const NO_ACCESS_STATUSES = [HTTP_STATUS_UNAUTHORIZED, HTTP_STATUS_FORBIDDEN, HTTP_STATUS_NOT_FOUND];
const AREA_DETAIL_STATES = [...ACTIVE_INDEXING_STATES, INDEXING_STATE.FAILED];

const AREA_ICONS = {
  [INDEXING_STATE.READY]: { icon: 'status-success', iconVariant: 'success' },
  [INDEXING_STATE.NOT_STARTED]: { icon: 'status-waiting', iconVariant: 'subtle' },
  [INDEXING_STATE.FAILED]: { icon: 'status-failed', iconVariant: 'danger' },
  [INDEXING_STATE.UNKNOWN]: { icon: 'status-neutral', iconVariant: 'subtle' },
};

const ACTION_APPLIES_TO = {
  // The hourly AutoIndexWorker turns off every excluded group, so Turn on needs the exclusion removed first.
  [ACTION_TURN_ON]: (group) => !group.isOn && !group.isExcluded,
  [ACTION_TURN_OFF]: (group) => group.isOn,
  [ACTION_EXCLUDE]: (group) => !group.isExcluded,
  [ACTION_INCLUDE]: (group) => group.isExcluded,
};

export function groupsForAction(groups, action) {
  return groups.filter(
    (group) => group.allowedActions.includes(action) && ACTION_APPLIES_TO[action](group),
  );
}

export function actionItemsFor(groups) {
  return Object.keys(ACTION_APPLIES_TO)
    .filter((action) => groupsForAction(groups, action).length > 0)
    .map((action) => ({ value: action, text: ACTION_LABELS[action] }));
}

export function indexStatusLabel(group) {
  if (!group.isOn) {
    return trialEnded(group.turnOnAction) ? s__('Orbit|Indexing paused') : s__('Orbit|Not indexed');
  }
  if (!group.indexingState) return s__('Orbit|Status not available');

  return (
    INDEXING_STATE_LABELS[group.indexingState] ?? INDEXING_STATE_LABELS[INDEXING_STATE.UNKNOWN]
  );
}

export function hasIndexingError(group) {
  return group.isOn && group.indexingState === INDEXING_STATE.FAILED;
}

export function isIndexingNow(group) {
  return group.isOn && group.indexingState === INDEXING_STATE.INDEXING;
}

// Orbit reports no percent, so the area states show how far the index is.
export function indexingAreasFor(group) {
  if (!group.isOn || !AREA_DETAIL_STATES.includes(group.indexingState)) return [];

  const states = new Map((group.indexingAreas ?? []).map(({ name, state }) => [name, state]));

  return ORBIT_AREAS.filter(({ key }) => states.has(key)).map(({ key, label }) => {
    const state = states.get(key) ?? INDEXING_STATE.UNKNOWN;

    return {
      key,
      label,
      stateLabel: INDEXING_STATE_LABELS[state] ?? INDEXING_STATE_LABELS[INDEXING_STATE.UNKNOWN],
      isIndexing: state === INDEXING_STATE.INDEXING,
      ...(AREA_ICONS[state] ?? AREA_ICONS[INDEXING_STATE.UNKNOWN]),
    };
  });
}

// Apollo drops the GraphQL errors of a cached result, so a row with no status is the fallback.
export function indexStatusWarningFor(groups, serverMessage) {
  if (serverMessage) return serverMessage;
  if (groups.some((group) => group.isOn && !group.indexingState)) {
    return s__('Orbit|GitLab Orbit did not return the index status of some groups.');
  }

  return null;
}

export function isIndexingActive(group) {
  return group.isOn && ACTIVE_INDEXING_STATES.includes(group.indexingState);
}

export function hasActiveIndexing(groups) {
  return groups.some(isIndexingActive);
}

export function requestErrorFor(
  error,
  {
    noAccessMessage = s__(
      'Orbit|You do not have permission to do this. Check that Admin Mode is on.',
    ),
  } = {},
) {
  const status = error.networkError?.statusCode ?? error.response?.status;
  const serverMessage = error.graphQLErrors?.[0]?.message ?? error.response?.data?.message;

  if (NO_ACCESS_STATUSES.includes(status) || serverMessage === RESOURCE_ACCESS_ERROR) {
    return { kind: ACTION_ERROR_KIND.NO_ACCESS, message: noAccessMessage };
  }

  const isServerError = status >= 500;

  if (serverMessage && !isServerError) {
    return { kind: ACTION_ERROR_KIND.REJECTED, message: serverMessage };
  }

  if (!status && (error.networkError || error.request)) {
    return {
      kind: ACTION_ERROR_KIND.NETWORK,
      message: s__('Orbit|The request did not reach GitLab. Check your connection and try again.'),
    };
  }

  return {
    kind: ACTION_ERROR_KIND.SERVER,
    message: s__('Orbit|GitLab could not complete the request. Try again.'),
  };
}

export function reportRequestError(error, options) {
  const failure = requestErrorFor(error, options);
  if (REPORTED_ERROR_KINDS.includes(failure.kind)) Sentry.captureException(error);
  return failure;
}

export function reportFirstRequestError(results) {
  const reported = results.find(({ failure }) => REPORTED_ERROR_KINDS.includes(failure?.kind));
  if (reported) Sentry.captureException(reported.error);
}

export function confirmKindFor(action, groups) {
  if (action === ACTION_TURN_OFF) return CONFIRM_TURN_OFF;
  if (action === ACTION_EXCLUDE && groups.some((group) => group.isOn)) return CONFIRM_EXCLUDE;

  return null;
}

export function turnOnTrackingLabel(groups) {
  const trialCount = groups.filter((group) => group.startsTrial).length;

  if (!trialCount) return TURN_ON_TRACKING_LABEL.TURN_ON;
  return trialCount === groups.length
    ? TURN_ON_TRACKING_LABEL.START_TRIAL
    : TURN_ON_TRACKING_LABEL.MIXED;
}

export function startBulkProgress(action, groups) {
  return {
    action,
    done: 0,
    total: groups.length,
    pendingPaths: groups.map((group) => group.fullPath),
  };
}

export function completeBulkProgress(progress, fullPath) {
  return {
    ...progress,
    done: progress.done + 1,
    pendingPaths: progress.pendingPaths.filter((path) => path !== fullPath),
  };
}

export function summarizeBulkAction(action, results) {
  const failed = results.filter(({ failure }) => failure);

  return {
    failures: Object.fromEntries(failed.map(({ group, failure }) => [group.fullPath, failure])),
    failedPaths: failed.map(({ group }) => group.fullPath),
    result: {
      action,
      total: results.length,
      failed: failed.map(({ group, failure }) => ({
        name: group.name,
        fullPath: group.fullPath,
        message: failure.message,
      })),
    },
  };
}

export async function mapWithConcurrency(items, limit, task) {
  const results = [];
  let nextIndex = 0;

  const runNext = async () => {
    if (nextIndex >= items.length) return;

    const index = nextIndex;
    nextIndex += 1;
    results[index] = await task(items[index]);
    await runNext();
  };

  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, runNext));
  return results;
}
