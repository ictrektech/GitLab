import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { s__, sprintf } from '~/locale';
import { groupSettingsGitlabCreditsDashboardIndexPath } from 'ee/lib/utils/path_helpers/group';
import { adminGitlabCreditsDashboardIndexPath } from 'ee/lib/utils/path_helpers/instance_admin';
import { RECENTLY_ENABLED_MS } from 'ee/orbit/constants';
import { ACTION_TURN_OFF, ACTION_TURN_ON, INDEXING_STATE } from 'ee/orbit/shared/groups/constants';
import { trialDateText, turnOnOfferText } from 'ee/orbit/utils/trial_offer_text';
import {
  ORBIT_TRIAL_STATE,
  TURN_ON_ACTION,
  canTurnOn,
  deniedOnInstance,
  needsSales,
  startsTrial,
  trialInUse,
  turnOnAction,
} from './turn_on_action';

const OFF_NOTES = {
  [TURN_ON_ACTION.NOT_LICENSED]: s__('Orbit|GitLab Orbit is available on Premium and Ultimate.'),
  [TURN_ON_ACTION.NOT_AVAILABLE]: s__('Orbit|Contact sales to get GitLab Orbit for this group.'),
  [TURN_ON_ACTION.NOT_ELIGIBLE]: s__('Orbit|Contact sales to get GitLab Orbit for this group.'),
  [TURN_ON_ACTION.UNAVAILABLE]: s__(
    'Orbit|Trial status is not available right now. Try again later.',
  ),
};

const offNote = (action, saas) => {
  if (!saas && deniedOnInstance(action)) {
    return s__('Orbit|Contact sales to get GitLab Orbit for this instance.');
  }

  return OFF_NOTES[action] ?? null;
};

const offerBadge = (action, offer) =>
  startsTrial(action) ? { text: turnOnOfferText(offer), variant: 'info', icon: null } : null;

// Orbit has no status for a group until the indexer picks it up (CDC lag).
const indexingState = (group, now) => {
  const state = group.orbit?.indexing?.state;
  if (state || !group.orbit?.enabled) return state ?? null;

  const enabledAt = group.orbit?.enabledAt;
  const isRecent = enabledAt && now - new Date(enabledAt).getTime() < RECENTLY_ENABLED_MS;
  return isRecent ? INDEXING_STATE.NOT_STARTED : null;
};

const trialEndNote = (trial, saas) =>
  sprintf(
    saas
      ? s__('Orbit|The trial ends on %{date}.')
      : s__('Orbit|The trial of this instance ends on %{date}.'),
    { date: trialDateText(trial.expiresOn) },
  );

const trialStatus = (trial, action, saas) => {
  if (trial?.state === ORBIT_TRIAL_STATE.ACTIVE) {
    return {
      badge: { text: s__('Orbit|Trial active'), variant: 'info', icon: null },
      note: trialEndNote(trial, saas),
    };
  }

  if (action === TURN_ON_ACTION.CREDITS_USED_UP) {
    return {
      badge: { text: s__('Orbit|Credits used up'), variant: 'warning', icon: 'status-alert' },
      note: saas
        ? s__(
            'Orbit|This group has no GitLab Credits left. GitLab Orbit queries are paused until the group has GitLab Credits again.',
          )
        : s__(
            'Orbit|The trial of this instance used all its credits. GitLab Orbit queries are paused.',
          ),
    };
  }

  if (action === TURN_ON_ACTION.TRIAL_ENDED && trial) {
    return {
      badge: { text: s__('Orbit|Trial ended'), variant: 'warning', icon: 'status-alert' },
      note: sprintf(s__('Orbit|The trial ended on %{date}. GitLab Orbit queries are paused.'), {
        date: trialDateText(trial.expiresOn),
      }),
    };
  }

  return { badge: null, note: null };
};

const groupNote = ({ group, isOn, state, canManageOrbit, action, failure, trialNote, saas }) => {
  if (failure) return failure.message;
  if (isOn && state === INDEXING_STATE.FAILED) {
    return s__('Orbit|GitLab Orbit could not index this group. Contact support if this continues.');
  }
  if (isOn && state === INDEXING_STATE.UNKNOWN) {
    return s__('Orbit|GitLab Orbit has not reported a status for this group yet.');
  }
  if (trialNote) return trialNote;
  if (isOn) return null;
  if (!canManageOrbit) {
    if (group.fullPath.includes('/')) {
      return s__('Orbit|Ask an Owner of the top-level group to turn on GitLab Orbit.');
    }
    return sprintf(s__('Orbit|Ask an Owner of %{group} to turn on GitLab Orbit.'), {
      group: group.name,
    });
  }

  return offNote(action, saas);
};

const creditsDashboardPath = ({ group, canManageOrbit, saas, isSelfManagedAdmin }) => {
  if (isSelfManagedAdmin) return adminGitlabCreditsDashboardIndexPath();
  if (saas && canManageOrbit) {
    return groupSettingsGitlabCreditsDashboardIndexPath(group.fullPath);
  }

  return null;
};

export function buildGroupStatusRow(
  group,
  { failure = null, now = Date.now(), saas, isSelfManagedAdmin = false } = {},
) {
  const canManageOrbit = group.userPermissions.readOrbitSetting;
  const isOn = Boolean(group.orbit?.enabled);
  const state = indexingState(group, now);
  const action = canManageOrbit ? turnOnAction(group) : null;
  const trialUsed = canManageOrbit ? trialInUse(group) : null;
  const trial = trialStatus(trialUsed, action, saas);
  const offer = group.orbit?.access?.trial?.offer ?? null;
  const allowedActions = [
    ...(canManageOrbit && !isOn && canTurnOn(action) ? [ACTION_TURN_ON] : []),
    ...(canManageOrbit && isOn && group.userPermissions.updateKnowledgeGraphSetting
      ? [ACTION_TURN_OFF]
      : []),
  ];
  const showsSales = saas && canManageOrbit && needsSales(action, { isOn });

  return {
    id: group.id,
    namespaceId: getIdFromGraphQLId(group.id),
    name: group.name,
    fullPath: group.fullPath,
    webPath: group.webPath,
    avatarUrl: group.avatarUrl,
    allowedActions,
    isOn,
    isExcluded: false,
    indexingState: state,
    indexingAreas: group.orbit?.indexing?.areas ?? [],
    enabledAt: group.orbit?.enabledAt ?? null,
    failure,
    trialBadge: trial.badge ?? offerBadge(action, offer),
    note: groupNote({
      group,
      isOn,
      state,
      canManageOrbit,
      action,
      failure,
      trialNote: trial.note,
      saas,
    }),
    turnOnAction: action,
    trialEndsOn: trialUsed?.state === ORBIT_TRIAL_STATE.ACTIVE ? trialUsed.expiresOn : null,
    startsTrial: startsTrial(action),
    offer,
    showsSales,
    creditsDashboardPath:
      isOn && !showsSales
        ? creditsDashboardPath({ group, canManageOrbit, saas, isSelfManagedAdmin })
        : null,
  };
}
