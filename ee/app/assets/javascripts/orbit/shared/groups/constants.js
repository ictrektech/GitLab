import { s__ } from '~/locale';

export const BULK_ACTION_CONCURRENCY = 5;
export const LISTED_FAILURES_LIMIT = 5;

export const GROUP_FILTER_ALL = 'all';
export const GROUP_FILTER_ON = 'on';
export const GROUP_FILTER_EXCLUDED = 'excluded';

export const GROUP_FILTER_OPTIONS = [
  { value: GROUP_FILTER_ALL, text: s__('Orbit|All') },
  { value: GROUP_FILTER_ON, text: s__('Orbit|On') },
  { value: GROUP_FILTER_EXCLUDED, text: s__('Orbit|Excluded') },
];

export const ACTION_TURN_ON = 'turnOn';
export const ACTION_TURN_OFF = 'turnOff';
export const ACTION_EXCLUDE = 'exclude';
export const ACTION_INCLUDE = 'include';

export const ALL_GROUP_ACTIONS = [ACTION_TURN_ON, ACTION_TURN_OFF, ACTION_EXCLUDE, ACTION_INCLUDE];

export const ACTION_LABELS = {
  [ACTION_TURN_ON]: s__('Orbit|Turn on GitLab Orbit'),
  [ACTION_TURN_OFF]: s__('Orbit|Turn off GitLab Orbit'),
  [ACTION_EXCLUDE]: s__('Orbit|Exclude from automatic indexing'),
  [ACTION_INCLUDE]: s__('Orbit|Remove exclusion'),
};

export const ACTION_PROGRESS_LABELS = {
  [ACTION_TURN_ON]: s__('Orbit|Turning on GitLab Orbit'),
  [ACTION_TURN_OFF]: s__('Orbit|Turning off GitLab Orbit'),
  [ACTION_EXCLUDE]: s__('Orbit|Excluding groups'),
  [ACTION_INCLUDE]: s__('Orbit|Removing exclusions'),
};

export const CONFIRM_TURN_OFF = 'turnOff';
export const CONFIRM_EXCLUDE = 'exclude';
export const CONFIRM_AUTO_INDEX = 'autoIndex';
export const CONFIRM_KINDS = [CONFIRM_TURN_OFF, CONFIRM_EXCLUDE, CONFIRM_AUTO_INDEX];

export const CONFIRMED_ACTIONS = {
  [CONFIRM_TURN_OFF]: ACTION_TURN_OFF,
  [CONFIRM_EXCLUDE]: ACTION_EXCLUDE,
};

export const INDEXING_STATE = {
  NOT_STARTED: 'NOT_STARTED',
  INDEXING: 'INDEXING',
  READY: 'READY',
  FAILED: 'FAILED',
  UNKNOWN: 'UNKNOWN',
};

export const INDEXING_STATE_LABELS = {
  [INDEXING_STATE.NOT_STARTED]: s__('Orbit|Queued to start'),
  [INDEXING_STATE.INDEXING]: s__('Orbit|Indexing'),
  [INDEXING_STATE.READY]: s__('Orbit|Indexed'),
  [INDEXING_STATE.FAILED]: s__('Orbit|Indexing failed'),
  [INDEXING_STATE.UNKNOWN]: s__('Orbit|Status not available'),
};

export const ACTIVE_INDEXING_STATES = [INDEXING_STATE.NOT_STARTED, INDEXING_STATE.INDEXING];

export const ACTION_ERROR_KIND = {
  REJECTED: 'rejected',
  NO_ACCESS: 'noAccess',
  NETWORK: 'network',
  SERVER: 'server',
};

export const TURN_ON_TRACKING_LABEL = {
  START_TRIAL: 'start_trial',
  TURN_ON: 'turn_on',
  MIXED: 'mixed',
};
