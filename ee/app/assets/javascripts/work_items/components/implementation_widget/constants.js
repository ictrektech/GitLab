import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';

// Extra goal context passed to the "Generate MR with Duo" action so the
// agent treats the saved workplan as the primary spec instead of starting
// from the work-item description.
export const WORKPLAN_GOAL_PREFIX =
  'The work item has an agent_plan widget containing a workplan authored for you. Treat that plan as the primary specification: define your tasks and approach from it, and only fall back to the description or comments for additional context when the plan is unclear. The widget can also contain readiness feedback (readinessScoreFeedback) from a review of that plan. Treat every point in it as a finding to resolve, including non-blocking ones: address each one in your implementation, or explain in the merge request description why you did not.';

export const WORKPLAN_SOURCE = 'work_item_plan_to_merge_request';

export const WORKPLAN_ACTION_EVENT = 'click_work_item_workplan_action';

export const GENERATE_MR_BUTTON_OPTIONS = {
  size: 'medium',
  variant: 'confirm',
  category: 'primary',
};

export const IMPLEMENTATION_UNAVAILABLE_MESSAGE = s__(
  "DuoAgentPlatform|Implementation with GitLab Duo isn't turned on for this project.",
);

export const IMPLEMENTATION_HELP_PATH = helpPagePath('user/work_items/workplan', {
  anchor: 'implement-a-workplan-with-gitlab-duo',
});

export const IMPLEMENTATION_WITHOUT_WORKPLAN_HELP_PATH = helpPagePath('user/work_items/workplan', {
  anchor: 'implement-a-work-item-without-a-workplan',
});

export const WORKPLAN_PANEL_URL_VALUE = 'workplan';

export const WORKPLAN_STATE_PARAM = 'workplan_state';

export const WORKPLAN_STATE_EDIT = 'edit';

export const PLAN_READINESS_LEVELS = {
  LOW: {
    value: 'LOW',
    variant: 'error',
  },
  MEDIUM: {
    value: 'MEDIUM',
    variant: 'warning',
  },
  HIGH: {
    value: 'HIGH',
    variant: 'success',
  },
};

export const AGENT_STEP_PILL_VARIANTS = {
  error: 'var(--gl-status-danger-icon-color)',
  warning: 'var(--gl-status-warning-icon-color)',
  info: 'var(--gl-status-info-icon-color)',
  success: 'var(--gl-status-success-icon-color)',
  neutral: 'var(--gl-status-neutral-background-color)',
};

// `generationStatus` values for the work item's latest `workplan/v1` flow.
export const GENERATION_STATUS_NOT_STARTED = 'NOT_STARTED';
export const GENERATION_STATUS_GENERATING = 'GENERATING';
export const GENERATION_STATUS_NEEDS_INPUT = 'NEEDS_INPUT';
export const GENERATION_STATUS_COMPLETED = 'COMPLETED';
export const GENERATION_STATUS_CANCELED = 'CANCELED';
export const GENERATION_STATUS_FAILED = 'FAILED';

export const GENERATION_STATUSES = [
  GENERATION_STATUS_NOT_STARTED,
  GENERATION_STATUS_GENERATING,
  GENERATION_STATUS_NEEDS_INPUT,
  GENERATION_STATUS_COMPLETED,
  GENERATION_STATUS_CANCELED,
  GENERATION_STATUS_FAILED,
];

// The row offers exactly one of these at a time.
export const WORKPLAN_ACTION = {
  VIEW: 'view',
  CONTINUE: 'continue',
  RETRY: 'retry',
  CREATE: 'create',
  NONE: 'none',
};

// Watchdog for a pending flow action. Every real ending moves `generationStatus`,
// which releases the action, so this only fires for a run whose status never moves
// at all. Well above the seconds a healthy run takes, to not release one early.
export const FLOW_ACTION_TIMEOUT_MS = 2 * 60 * 1000;

// Safety net while a run is active. The `workItemUpdated` push that carries the run's
// terminal status does not reliably arrive, which would otherwise strand the widget on
// "Reviewing work item..." until a reload. Polling stops the moment the status settles.
export const ACTIVE_RUN_POLL_INTERVAL_MS = 10 * 1000;

// A run we started can read as terminal for a moment before it truly ends, which would
// otherwise stop the polling that corrects it. Longer than one poll, so a genuine
// terminal status is confirmed by a fresh read rather than the one that raised it.
export const TERMINAL_STATUS_CONFIRM_MS = 15 * 1000;

// Statuses where a run owns the workplan, so the UI must not offer to start another.
export const GENERATION_STATUSES_ACTIVE = [
  GENERATION_STATUS_GENERATING,
  GENERATION_STATUS_NEEDS_INPUT,
];

// Bounds of the `readinessScore` GraphQL field, matching the `WorkItems::AgentPlan` validation.
export const READINESS_SCORE_MIN = 0;

export const READINESS_SCORE_MAX = 100;

// Thresholds are on the same 0-100 scale as the `readinessScore` GraphQL field.
export const READINESS_SCORE_MEDIUM_THRESHOLD = 40;

export const READINESS_SCORE_HIGH_THRESHOLD = 80;
