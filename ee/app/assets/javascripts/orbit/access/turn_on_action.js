import { ACCESS_REASON, ACCESS_STATE, TURN_ON_DENIAL_REASON } from './constants';

export const TURN_ON_ACTION = {
  START_TRIAL: 'start_trial',
  TURN_ON: 'turn_on',
  NOT_LICENSED: 'not_licensed',
  NOT_AVAILABLE: 'not_available',
  NOT_ELIGIBLE: 'not_eligible',
  TRIAL_ENDED: 'trial_ended',
  CREDITS_USED_UP: 'credits_used_up',
  UNAVAILABLE: 'unavailable',
};

export const ORBIT_TRIAL_STATE = {
  ELIGIBLE: 'ELIGIBLE',
  NOT_ELIGIBLE: 'NOT_ELIGIBLE',
  ACTIVE: 'ACTIVE',
  ENDED: 'ENDED',
};

const TURN_ON_ACTIONS = [TURN_ON_ACTION.START_TRIAL, TURN_ON_ACTION.TURN_ON];
const TRIAL_ENDED_ACTIONS = [TURN_ON_ACTION.TRIAL_ENDED, TURN_ON_ACTION.CREDITS_USED_UP];
const DENIED_ACTIONS = [
  TURN_ON_ACTION.NOT_LICENSED,
  TURN_ON_ACTION.NOT_AVAILABLE,
  TURN_ON_ACTION.NOT_ELIGIBLE,
];
const SALES_ACTIONS = [...DENIED_ACTIONS, ...TRIAL_ENDED_ACTIONS];
const TRIAL_IN_USE_STATES = [ACCESS_STATE.TRIAL_ACTIVE, ACCESS_STATE.TRIAL_ENDED];

const DENIAL_ACTIONS = {
  [TURN_ON_DENIAL_REASON.FORBIDDEN]: TURN_ON_ACTION.NOT_LICENSED,
  [TURN_ON_DENIAL_REASON.PURCHASE_REQUIRED]: TURN_ON_ACTION.NOT_AVAILABLE,
  [TURN_ON_DENIAL_REASON.TRIAL_ENDED]: TURN_ON_ACTION.TRIAL_ENDED,
  [TURN_ON_DENIAL_REASON.UNAVAILABLE]: TURN_ON_ACTION.UNAVAILABLE,
};

const trialEndedAction = ({ reason }) =>
  reason === ACCESS_REASON.CREDITS_EXHAUSTED
    ? TURN_ON_ACTION.CREDITS_USED_UP
    : TURN_ON_ACTION.TRIAL_ENDED;

// The server has no turn-on denial for a group that is on, so the state still tells an ended trial.
export const turnOnAction = (group) => {
  const access = group.orbit?.access;
  if (!access) return TURN_ON_ACTION.NOT_LICENSED;

  const denial = access.turnOnDenialReason;
  // An instance indexes groups without a trial, so its trial state does not block a group that is off.
  if (!denial && !group.orbit.enabled) return TURN_ON_ACTION.TURN_ON;

  switch (access.state) {
    case ACCESS_STATE.TRIAL_ENDED:
      return trialEndedAction(access);
    case ACCESS_STATE.TRIAL_NOT_ELIGIBLE:
      return TURN_ON_ACTION.NOT_ELIGIBLE;
    case ACCESS_STATE.TRIAL_STATUS_UNAVAILABLE:
      return TURN_ON_ACTION.UNAVAILABLE;
    default:
      break;
  }

  if (!denial) return TURN_ON_ACTION.TURN_ON;
  // Only an administrator starts the instance trial on GitLab Self-Managed and GitLab Dedicated.
  if (denial === TURN_ON_DENIAL_REASON.TRIAL_REQUIRED) {
    return group.userPermissions.startOrbitTrial
      ? TURN_ON_ACTION.START_TRIAL
      : TURN_ON_ACTION.NOT_AVAILABLE;
  }

  return DENIAL_ACTIONS[denial] ?? TURN_ON_ACTION.NOT_AVAILABLE;
};

export const canTurnOn = (action) => TURN_ON_ACTIONS.includes(action);

export const startsTrial = (action) => action === TURN_ON_ACTION.START_TRIAL;

export const trialEnded = (action) => TRIAL_ENDED_ACTIONS.includes(action);

// On GitLab Self-Managed, every group shares the access of the instance.
export const deniedOnInstance = (action) => DENIED_ACTIONS.includes(action);

// A group that is on with no trial uses the GitLab credits of its plan.
export const needsSales = (action, { isOn = false } = {}) =>
  SALES_ACTIONS.includes(action) && !(isOn && action === TURN_ON_ACTION.NOT_ELIGIBLE);

// A beta group can keep an old trial in CustomersDot, but its access state does not use it.
export const trialInUse = (group) => {
  const access = group.orbit?.access;
  return TRIAL_IN_USE_STATES.includes(access?.state) ? access.trial : null;
};
