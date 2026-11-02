import { n__, s__, sprintf } from '~/locale';
import { STATUS_DONE, STATUS_TODO } from '~/ai/settings/readiness/constants';

export const STEP_COUNT = 4;

export const SETUP_BLOCKED = 'blocked';
export const SETUP_LIMITED = 'limited';
export const SETUP_PARTIAL = 'partial';
export const SETUP_RUNNER_NEEDED = 'runner-needed';
export const SETUP_COMPLETE = 'complete';

export const isLocked = (cascadingSettings) =>
  Boolean(cascadingSettings?.lockedByAncestor || cascadingSettings?.lockedByApplicationSetting);

// The ancestor group that locked a setting, or null when an administrator did.
export const lockingGroup = (cascadingSettings, rootAncestorName) => {
  if (!cascadingSettings?.lockedByAncestor) return null;

  return cascadingSettings.ancestorNamespace?.fullName ?? rootAncestorName;
};

export const stepStatus = (done) => (done ? STATUS_DONE : STATUS_TODO);

// An agent without a record follows the Agents switch, so only an explicit false unchecks it.
export const isAgentSelected = (agent) => agent.enabled !== false;

export const lockIconProps = (cascadingSettings) => ({
  isLockedByGroupAncestor: cascadingSettings.lockedByAncestor,
  isLockedByApplicationSettings: cascadingSettings.lockedByApplicationSetting,
  ancestorNamespace: cascadingSettings.ancestorNamespace,
});

// Blocked: the Agent Platform is off where it is owned, so nothing on this page can work.
// Limited: everything this group can set is set, and what is on works; the steps still off
// were turned off by the level above.
const setupStatus = ({ platformOffAtOwner, stepsLeft, lockedCount, runnerConfirmed }) => {
  if (platformOffAtOwner) return SETUP_BLOCKED;
  if (stepsLeft > 0) return SETUP_PARTIAL;
  if (lockedCount > 0) return SETUP_LIMITED;

  return runnerConfirmed ? SETUP_COMPLETE : SETUP_RUNNER_NEEDED;
};

// Names who turned a step off. It follows the status in the state line, so it reads as the
// reason. Each step names its own party: a parent group may lock one step while an
// administrator locks the other. A locked-off GitLab Duo also says what happens to changes.
const duoLockedNote = (group) =>
  group
    ? sprintf(s__('DuoAgentPlatform|GitLab Duo is turned off by %{group}.'), { group }, false)
    : s__('DuoAgentPlatform|GitLab Duo is turned off by an administrator.');

const flowsLockedNote = (group) =>
  group
    ? sprintf(s__('DuoAgentPlatform|Flows are turned off by %{group}.'), { group }, false)
    : s__('DuoAgentPlatform|Flows are turned off by an administrator.');

const bothLockedNote = (group) =>
  group
    ? sprintf(
        s__('DuoAgentPlatform|GitLab Duo and flows are turned off by %{group}.'),
        { group },
        false,
      )
    : s__('DuoAgentPlatform|GitLab Duo and flows are turned off by an administrator.');

const lockedNote = ({ duoLockedOff, flowsLockedOff, duoLockedBy, flowsLockedBy }) => {
  const notes = [];

  if (duoLockedOff && flowsLockedOff && duoLockedBy === flowsLockedBy) {
    notes.push(bothLockedNote(duoLockedBy));
  } else {
    if (duoLockedOff) notes.push(duoLockedNote(duoLockedBy));
    if (flowsLockedOff) notes.push(flowsLockedNote(flowsLockedBy));
  }

  if (duoLockedOff) {
    notes.push(
      s__('DuoAgentPlatform|Settings you change here take effect when GitLab Duo is turned on.'),
    );
  }

  return notes.join(' ');
};

const stateLine = ({
  duoOn,
  platformOn,
  agentsOn,
  flowsOn,
  platformOffAtOwner,
  isSaaS,
  rootAncestorName,
  stepsLeft,
  status,
  duoLockedOff,
  flowsLockedOff,
}) => {
  if (platformOffAtOwner) {
    return isSaaS
      ? sprintf(
          s__('DuoAgentPlatform|Agent Platform is off for %{group}.'),
          { group: rootAncestorName },
          false,
        )
      : s__('DuoAgentPlatform|Agent Platform is off for this instance.');
  }
  if (!duoOn && !duoLockedOff && !platformOn) {
    return s__('DuoAgentPlatform|Turn on GitLab Duo and the Agent Platform to get started.');
  }
  if (!duoOn && !duoLockedOff) return s__('DuoAgentPlatform|Turn on GitLab Duo to get started.');
  if (!platformOn) return s__('DuoAgentPlatform|Turn on the Agent Platform to get started.');
  // GitLab Duo is locked off here: the locked note is the whole message, no nudge to set up.
  if (!duoOn) return '';
  if (!agentsOn && !flowsOn) {
    if (flowsLockedOff) return s__('DuoAgentPlatform|1 more step to set up agents.');

    return n__(
      'DuoAgentPlatform|Nothing is turned on yet. %d step left to set up agents and flows.',
      'DuoAgentPlatform|Nothing is turned on yet. %d steps left to set up agents and flows.',
      stepsLeft,
    );
  }
  if (!agentsOn) {
    return n__(
      'DuoAgentPlatform|Flows work now. %d more step to set up agents.',
      'DuoAgentPlatform|Flows work now. %d more steps to set up agents.',
      stepsLeft,
    );
  }
  if (!flowsOn) {
    return flowsLockedOff
      ? s__('DuoAgentPlatform|Agents work now.')
      : s__('DuoAgentPlatform|Agents work now. 1 more step to set up flows.');
  }
  if (status === SETUP_RUNNER_NEEDED) {
    return s__(
      "DuoAgentPlatform|Agents work now. Flows are on, but they won't start until you connect a runner.",
    );
  }

  return s__('DuoAgentPlatform|Agents and flows are ready in this group.');
};

// GitLab Duo off outranks flows off: nothing runs without Duo, so its party names the limit.
const lockingParty = ({ duoLockedOff, flowsLockedOff, duoLockedBy, flowsLockedBy }) => {
  if (duoLockedOff) return duoLockedBy;
  if (flowsLockedOff) return flowsLockedBy;

  return null;
};

const progressLabel = ({ status, stepsLeft, lockedBy }) => {
  if (status === SETUP_BLOCKED) return s__('DuoAgentPlatform|Blocked');
  if (status === SETUP_LIMITED) {
    return lockedBy
      ? sprintf(s__('DuoAgentPlatform|Limited by %{group}'), { group: lockedBy }, false)
      : s__('DuoAgentPlatform|Limited by your administrator');
  }
  if (status === SETUP_RUNNER_NEEDED) return s__('DuoAgentPlatform|Runner needed');
  if (status === SETUP_COMPLETE) return s__('DuoAgentPlatform|Setup complete');

  return n__('DuoAgentPlatform|%d step left', 'DuoAgentPlatform|%d steps left', stepsLeft);
};

export const readinessSummary = (steps) => {
  const {
    duoOn,
    platformOn,
    agentsOn,
    flowsOn,
    platformOffAtOwner,
    runnerConfirmed,
    duoLocked = false,
    flowsLocked = false,
    duoLockedBy = null,
    flowsLockedBy = null,
  } = steps;
  // A lock only takes a step away from this group while the step is off.
  const duoLockedOff = !duoOn && duoLocked;
  const flowsLockedOff = !flowsOn && flowsLocked;
  const lockedCount = [duoLockedOff, flowsLockedOff].filter(Boolean).length;
  const doneCount = [duoOn, platformOn, agentsOn, flowsOn].filter(Boolean).length;
  const stepsLeft = STEP_COUNT - doneCount - lockedCount;
  const status = setupStatus({ platformOffAtOwner, stepsLeft, lockedCount, runnerConfirmed });
  const lockedBy = lockingParty({ duoLockedOff, flowsLockedOff, duoLockedBy, flowsLockedBy });

  return {
    doneCount,
    status,
    progressLabel: progressLabel({ status, stepsLeft, lockedBy }),
    progressBarLabel: sprintf(
      s__('DuoAgentPlatform|Agent setup progress: %{done} of %{total} steps complete'),
      { done: doneCount, total: STEP_COUNT },
    ),
    stateLine: stateLine({ ...steps, stepsLeft, status, duoLockedOff, flowsLockedOff }),
    lockedNote: lockedNote({ duoLockedOff, flowsLockedOff, duoLockedBy, flowsLockedBy }),
  };
};
