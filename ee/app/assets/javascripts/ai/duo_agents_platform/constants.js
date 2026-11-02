import { __, s__ } from '~/locale';

export const DUO_AGENT_PLATFORM_POLLING_INTERVAL = 10000;
export const AGENT_PLATFORM_INDEX_COMPONENT_NAME = 'DuoAgentPlatformIndex';

export const AGENT_PLATFORM_PROJECT_PAGE = 'project';
export const AGENT_PLATFORM_GROUP_PAGE = 'group';
export const AGENT_PLATFORM_USER_PAGE = 'user';
export const AGENT_PLATFORM_SIDE_PANEL_PAGE = 'side_panel';

export const INBOX_TAB_NEEDS_DECISION = 0;
export const INBOX_TAB_ALL = 1;

export const CANCEL_SESSION_ICON = 'stop';
export const RETRY_SESSION_ICON = 'retry';

// DUO_CLI_RUN is not interactive, so it is excluded here.
export const INTERACTIVE_CLI_SOURCE_TYPES = ['DUO_CLI_INTERACTIVE', 'DUO_CLI_ACP'];

export const AGENT_PLATFORM_STATUS_ICON = {
  CREATED: {
    icon: 'status-waiting',
    variant: 'subtle',
  },
  RUNNING: {
    icon: 'status-running',
    variant: 'info',
  },
  FINISHED: {
    icon: 'status-success',
    variant: 'success',
  },
  PAUSED: {
    icon: 'status-paused',
    variant: 'subtle',
  },
  STOPPED: {
    icon: 'status-cancelled',
    variant: 'subtle',
  },
  INPUT_REQUIRED: {
    icon: 'status-alert',
    variant: 'warning',
  },
  IDLE: {
    icon: 'status-success',
    variant: 'subtle',
  },
  PLAN_APPROVAL_REQUIRED: {
    icon: 'status-alert',
    variant: 'warning',
  },
  TOOL_CALL_APPROVAL_REQUIRED: {
    icon: 'status-alert',
    variant: 'warning',
  },
  FAILED: {
    icon: 'status-failed',
    variant: 'danger',
  },
  UNKNOWN: {
    icon: 'status-neutral',
    variant: 'subtle',
  },
};

export const FLOW_TRIGGER_TYPE_MENTION = {
  text: __('Mention'),
  description: s__(
    'AICatalog|Trigger %{itemType} when service account user is mentioned in an issue or merge request.',
  ),
  value: 'mention',
  valueInt: 0, // Matches EVENT_TYPES[:mention] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'MENTION',
};

export const FLOW_TRIGGER_TYPE_ASSIGN = {
  text: __('Assign'),
  description: s__(
    'AICatalog|Trigger %{itemType} when service account user is assigned to an issue or merge request.',
  ),
  value: 'assign',
  valueInt: 1, // Matches EVENT_TYPES[:assign] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'ASSIGN',
};

export const FLOW_TRIGGER_TYPE_ASSIGN_REVIEWER = {
  text: __('Assign reviewer'),
  description: s__(
    'AICatalog|Trigger %{itemType} when service account user is assigned as a reviewer to a merge request.',
  ),
  value: 'assign_reviewer',
  valueInt: 2, // Matches EVENT_TYPES[:assign_reviewer] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'ASSIGN_REVIEWER',
};

export const FLOW_TRIGGER_TYPE_PIPELINE_HOOKS = {
  text: __('Pipeline events'),
  description: s__('AICatalog|Trigger %{itemType} when a pipeline status changes.'),
  value: 'pipeline_hooks',
  valueInt: 3, // Matches EVENT_TYPES[:pipeline_hooks] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'PIPELINE_HOOKS',
};

// Dotted path into the pipeline webhook payload, evaluated by `Gitlab::FilterEvaluator`.
// The shape comes from `Gitlab::DataBuilder::Pipeline#hook_attrs`:
// https://gitlab.com/gitlab-org/gitlab/-/blob/87f27de87474583e1d3d02f04971646a3dba5fd7/lib/gitlab/data_builder/pipeline.rb#L17
export const FILTER_FIELD_PIPELINE_STATUS = 'object_attributes.status';
export const FILTER_FIELD_ACTION = 'action';
// Matches the `status.name` key injected by ExecuteWorkItemStatusChangedWorkflowTriggersWorker.
export const FILTER_FIELD_WORK_ITEM_STATUS_NAME = 'status.name';
// Matches the `work_item_type_id` key injected by both work item trigger workers.
export const FILTER_FIELD_WORK_ITEM_TYPE_ID = 'work_item_type_id';
// Matches the `software_factory_enabled` key injected by both work item trigger workers.
export const FILTER_FIELD_WORK_ITEM_SOFTWARE_FACTORY_ENABLED = 'software_factory_enabled';
export const FILTER_OPERATOR_IN = 'in';

export const PIPELINE_HOOK_STATUSES = [
  { text: s__('Pipeline|Running'), value: 'running' },
  { text: s__('Pipeline|Passed'), value: 'success' },
  { text: s__('Pipeline|Failed'), value: 'failed' },
  { text: s__('Pipeline|Canceled'), value: 'canceled' },
];

// Not in FLOW_TRIGGER_TYPES; folded into the merge_request picker as actions and
// referenced only by token rendering and form normalization.
export const FLOW_TRIGGER_TYPE_MERGE_REQUEST_READY = {
  value: 'merge_request_ready',
  valueInt: 4, // Matches EVENT_TYPES[:merge_request_ready] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'MERGE_REQUEST_READY',
};

// Not in FLOW_TRIGGER_TYPES; folded into the merge_request picker as actions and
// referenced only by token rendering and form normalization.
export const FLOW_TRIGGER_TYPE_MERGE_REQUEST_CODE_CONFLICT = {
  value: 'merge_request_code_conflict',
  valueInt: 5, // Matches EVENT_TYPES[:merge_request_code_conflict] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'MERGE_REQUEST_CODE_CONFLICT',
};

export const FILTER_FIELD_MERGE_REQUEST_ACTION = 'action';

export const MERGE_REQUEST_ACTION_APPROVED = {
  text: s__('MergeRequest|Approved'),
  value: 'approved',
};

export const MERGE_REQUEST_ACTION_REQUESTED_CHANGES = {
  text: s__('MergeRequest|Changes requested'),
  value: 'requested_changes',
  featureFlag: 'dapSoftwareFactory',
};

export const MERGE_REQUEST_ACTION_MERGED = {
  text: s__('MergeRequest|Merged'),
  value: 'merged',
  featureFlag: 'mergeRequestMergedFlowTrigger',
};

export const MERGE_REQUEST_ACTION_CODE_CONFLICT = {
  text: s__('MergeRequest|Merge conflict'),
  value: 'code_conflict',
  eventTypeValueInt: FLOW_TRIGGER_TYPE_MERGE_REQUEST_CODE_CONFLICT.valueInt,
};

export const MERGE_REQUEST_ACTION_READY = {
  text: s__('MergeRequest|Marked ready'),
  value: 'ready',
  eventTypeValueInt: FLOW_TRIGGER_TYPE_MERGE_REQUEST_READY.valueInt,
};

export const MERGE_REQUEST_ACTION_CREATED = {
  text: s__('MergeRequest|Created'),
  value: 'created',
};

export const MERGE_REQUEST_ACTIONS = [
  MERGE_REQUEST_ACTION_APPROVED,
  MERGE_REQUEST_ACTION_REQUESTED_CHANGES,
  MERGE_REQUEST_ACTION_MERGED,
  MERGE_REQUEST_ACTION_CODE_CONFLICT,
  MERGE_REQUEST_ACTION_READY,
  MERGE_REQUEST_ACTION_CREATED,
];

export const FLOW_TRIGGER_TYPE_MERGE_REQUEST = {
  text: __('Merge request'),
  description: (glFeatures) => {
    if (glFeatures.dapSoftwareFactory) {
      return glFeatures.mergeRequestMergedFlowTrigger
        ? s__(
            'AICatalog|Trigger %{itemType} when a merge request is created, ready, approved, merged, has changes requested, or has conflicts.',
          )
        : s__(
            'AICatalog|Trigger %{itemType} when a merge request is created, ready, approved, has changes requested, or has conflicts.',
          );
    }

    return glFeatures.mergeRequestMergedFlowTrigger
      ? s__(
          'AICatalog|Trigger %{itemType} when a merge request is created, ready, approved, merged, or has conflicts.',
        )
      : s__(
          'AICatalog|Trigger %{itemType} when a merge request is created, ready, approved, or has conflicts.',
        );
  },
  value: 'merge_request',
  valueInt: 6, // Matches EVENT_TYPES[:merge_request] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'MERGE_REQUEST',
};

export const WORK_ITEM_ACTION_CREATED = {
  text: s__('WorkItem|Created'),
  value: 'created',
};

export const WORK_ITEM_ACTION_STATUS_CHANGED = {
  text: s__('WorkItem|Status changed'),
  value: 'status_changed',
};

export const WORK_ITEM_ACTIONS = [WORK_ITEM_ACTION_CREATED, WORK_ITEM_ACTION_STATUS_CHANGED];

// GlCollapsibleListbox does not accept boolean values, so `ruleValue` holds the value of the rule.
export const WORK_ITEM_SOFTWARE_FACTORY_OPTIONS = [
  { value: 'yes', text: s__('DuoAgentsPlatform|Software Factory work items'), ruleValue: true },
  { value: 'no', text: s__('DuoAgentsPlatform|Other work items'), ruleValue: false },
];

export const FLOW_TRIGGER_TYPE_WORK_ITEM = {
  text: s__('WorkItem|Work item'),
  description: s__(
    'AICatalog|Trigger %{itemType} when a project-level work item is created or its status is updated.',
  ),
  value: 'work_item',
  valueInt: 7, // Matches EVENT_TYPES[:work_item] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'WORK_ITEM',
};

// Not offered when creating a trigger, but triggers already store it, so it needs a name
// here or those triggers render as something else entirely.
export const FLOW_TRIGGER_TYPE_COMMIT_TO_DEFAULT_BRANCH = {
  text: s__('DuoAgentsPlatform|Commit to default branch'),
  value: 'commit_to_default_branch',
  // Matches EVENT_TYPES[:commit_to_default_branch] in ee/app/models/ai/flow_trigger.rb
  valueInt: 8,
  graphQL: 'COMMIT_TO_DEFAULT_BRANCH',
  isAvailable: () => false,
};

export const FLOW_TRIGGER_TYPE_SCHEDULE = {
  text: __('Schedule'),
  description: s__('AICatalog|Trigger %{itemType} on a recurring schedule.'),
  value: 'scheduled',
  valueInt: 9, // Matches EVENT_TYPES[:scheduled] in ee/app/models/ai/flow_trigger.rb
  graphQL: 'SCHEDULED',
  isAvailable: (glFeatures = {}) =>
    Boolean(glFeatures?.aiFlowSchedules && glFeatures?.autonomousServiceAccountExecution),
};

export const FLOW_TRIGGER_TYPES = [
  FLOW_TRIGGER_TYPE_MENTION,
  FLOW_TRIGGER_TYPE_ASSIGN,
  FLOW_TRIGGER_TYPE_ASSIGN_REVIEWER,
  FLOW_TRIGGER_TYPE_PIPELINE_HOOKS,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST,
  FLOW_TRIGGER_TYPE_WORK_ITEM,
  FLOW_TRIGGER_TYPE_COMMIT_TO_DEFAULT_BRANCH,
  FLOW_TRIGGER_TYPE_SCHEDULE,
];

export const FLOW_TRIGGER_MODE_SCHEDULE = FLOW_TRIGGER_TYPE_SCHEDULE.value;
export const FLOW_TRIGGER_MODE_EVENT = 'event';

// Mirrors the maxLength in app/validators/json_schemas/ai_flow_trigger_goals.json.
export const FLOW_TRIGGER_GOAL_MAX_LENGTH = 4096;

/* eslint-disable @gitlab/require-i18n-strings -- internal preset enum values, not user-facing */
export const SCHEDULE_FREQUENCY_EVERY_15_MINUTES = 'EVERY_15_MINUTES';
export const SCHEDULE_FREQUENCY_EVERY_30_MINUTES = 'EVERY_30_MINUTES';
export const SCHEDULE_FREQUENCY_HOURLY = 'HOURLY';
export const SCHEDULE_FREQUENCY_DAILY = 'DAILY';
export const SCHEDULE_FREQUENCY_WEEKDAYS = 'WEEKDAYS';
export const SCHEDULE_FREQUENCY_WEEKLY = 'WEEKLY';
export const SCHEDULE_FREQUENCY_MONTHLY = 'MONTHLY';
export const SCHEDULE_DEFAULT_TIMEZONE = 'Etc/UTC';
/* eslint-enable @gitlab/require-i18n-strings */

export const SCHEDULE_FREQUENCIES = [
  { value: SCHEDULE_FREQUENCY_EVERY_15_MINUTES, text: s__('DuoAgentsPlatform|Every 15 minutes') },
  { value: SCHEDULE_FREQUENCY_EVERY_30_MINUTES, text: s__('DuoAgentsPlatform|Every 30 minutes') },
  { value: SCHEDULE_FREQUENCY_HOURLY, text: s__('DuoAgentsPlatform|Hourly') },
  { value: SCHEDULE_FREQUENCY_DAILY, text: __('Daily') },
  { value: SCHEDULE_FREQUENCY_WEEKDAYS, text: s__('DuoAgentsPlatform|Weekdays') },
  { value: SCHEDULE_FREQUENCY_WEEKLY, text: __('Weekly') },
  { value: SCHEDULE_FREQUENCY_MONTHLY, text: __('Monthly') },
];

export const SCHEDULE_FIELD_MINUTE = 'minute';
export const SCHEDULE_FIELD_HOUR = 'hour';
export const SCHEDULE_FIELD_DAY_OF_WEEK = 'dayOfWeek';
export const SCHEDULE_FIELD_DAY_OF_MONTH = 'dayOfMonth';
export const SCHEDULE_FIELD_TIMEZONE = 'timezone';

// Fields each frequency exposes — drives picker visibility, validation, and randomized defaults.
export const SCHEDULE_FREQUENCY_FIELDS = {
  [SCHEDULE_FREQUENCY_EVERY_15_MINUTES]: [],
  [SCHEDULE_FREQUENCY_EVERY_30_MINUTES]: [],
  [SCHEDULE_FREQUENCY_HOURLY]: [SCHEDULE_FIELD_MINUTE, SCHEDULE_FIELD_TIMEZONE],
  [SCHEDULE_FREQUENCY_DAILY]: [SCHEDULE_FIELD_MINUTE, SCHEDULE_FIELD_HOUR, SCHEDULE_FIELD_TIMEZONE],
  [SCHEDULE_FREQUENCY_WEEKDAYS]: [
    SCHEDULE_FIELD_MINUTE,
    SCHEDULE_FIELD_HOUR,
    SCHEDULE_FIELD_TIMEZONE,
  ],
  [SCHEDULE_FREQUENCY_WEEKLY]: [
    SCHEDULE_FIELD_MINUTE,
    SCHEDULE_FIELD_HOUR,
    SCHEDULE_FIELD_DAY_OF_WEEK,
    SCHEDULE_FIELD_TIMEZONE,
  ],
  [SCHEDULE_FREQUENCY_MONTHLY]: [
    SCHEDULE_FIELD_MINUTE,
    SCHEDULE_FIELD_HOUR,
    SCHEDULE_FIELD_DAY_OF_MONTH,
    SCHEDULE_FIELD_TIMEZONE,
  ],
};

export const SCHEDULE_MINUTE_VALUES = [0, 15, 30, 45];
export const SCHEDULE_HOUR_MIN = 0;
export const SCHEDULE_HOUR_MAX = 23;
export const SCHEDULE_DAY_OF_WEEK_MIN = 0;
export const SCHEDULE_DAY_OF_WEEK_MAX = 6;
export const SCHEDULE_DAY_OF_MONTH_MIN = 1;
// Capped at 28 so every month has the selected day.
export const SCHEDULE_DAY_OF_MONTH_MAX = 28;

export const DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES = {
  first: 20,
  before: null,
  after: null,
  last: null,
};

// Can cancel only if session is in an active state (not already finished, failed, or stopped)
export const AGENT_PLATFORM_CANCELABLE_STATUSES = [
  'CREATED',
  'RUNNING',
  'PAUSED',
  'INPUT_REQUIRED',
  'PLAN_APPROVAL_REQUIRED',
  'TOOL_CALL_APPROVAL_REQUIRED',
];

export const STALE_ROUTE_ERROR_CODES = ['WORKFLOW_NOT_FOUND', 'NO_RESOURCE_PERMISSIONS'];

export const SIDE_PANEL_ROUTE_CONTEXT = 'side_panel';

export const AGENT_PLATFORM_SESSION_RETENTION_LENGTH = 30;

export const AGENT_PLATFORM_STATUS_FINISHED = 'FINISHED';
export const AGENT_PLATFORM_STATUS_FAILED = 'FAILED';
export const AGENT_PLATFORM_STATUS_STOPPED = 'STOPPED';
export const AGENT_PLATFORM_STATUS_IDLE = 'IDLE';

export const MESSAGE_SUB_TYPE_DELEGATION = 'delegation';
export const MESSAGE_SUB_TYPE_DELEGATION_RETURNS = 'delegation_returns';
export const MESSAGE_SUB_TYPE_START_FLOW = 'start_flow';
export const MESSAGE_SUB_TYPE_EXTERNAL = 'external';

export const WORKFLOW_TERMINAL_STATUSES = [
  AGENT_PLATFORM_STATUS_FINISHED,
  AGENT_PLATFORM_STATUS_FAILED,
  AGENT_PLATFORM_STATUS_STOPPED,
];
export const WORKFLOW_AWAITING_INPUT_STATUSES = [
  'INPUT_REQUIRED',
  'PLAN_APPROVAL_REQUIRED',
  'TOOL_CALL_APPROVAL_REQUIRED',
];

export const AUTOMATION_RUN_STATUS_NEVER = 'NEVER';

// Keyed by the AiFlowTriggerRunStatus enum values, plus NEVER.
export const AUTOMATION_RUN_STATUS_META = {
  PENDING: { text: __('Pending'), icon: 'status-waiting', variant: 'neutral' },
  RUNNING: { text: __('Running'), icon: 'status-running', variant: 'info' },
  AWAITING_INPUT: { text: __('Awaiting input'), icon: 'status-alert', variant: 'warning' },
  SUCCEEDED: { text: __('Succeeded'), icon: 'status-success', variant: 'success' },
  FAILED: { text: __('Failed'), icon: 'status-failed', variant: 'danger' },
  CANCELED: { text: __('Canceled'), icon: 'status-cancelled', variant: 'neutral' },
  [AUTOMATION_RUN_STATUS_NEVER]: {
    text: s__('DuoAgentsPlatform|Never run'),
    icon: 'status-neutral',
    variant: 'neutral',
  },
};

// Mirrors RUN_STATUSES in ee/lib/gitlab/graphql/loaders/ai/flow_trigger_run_summary_loader.rb.
export const WORKFLOW_STATUS_TO_AUTOMATION_RUN_STATUS = {
  CREATED: 'PENDING',
  RUNNING: 'RUNNING',
  PAUSED: 'AWAITING_INPUT',
  INPUT_REQUIRED: 'AWAITING_INPUT',
  PLAN_APPROVAL_REQUIRED: 'AWAITING_INPUT',
  TOOL_CALL_APPROVAL_REQUIRED: 'AWAITING_INPUT',
  FINISHED: 'SUCCEEDED',
  FAILED: 'FAILED',
  STOPPED: 'CANCELED',
  IDLE: 'SUCCEEDED',
};

export const TODO_STATUS_ICON = {
  completed: { ...AGENT_PLATFORM_STATUS_ICON.FINISHED, ariaLabel: __('Completed') },
  pending: { ...AGENT_PLATFORM_STATUS_ICON.CREATED, ariaLabel: __('Pending') },
  cancelled: { ...AGENT_PLATFORM_STATUS_ICON.STOPPED, ariaLabel: __('Canceled') },
};

// The REST note payload serializes the Ruby state machine symbol directly, giving
// lowercase values ('running', 'failed', …). Derive sets from the canonical uppercase
// constants so the two representations can never drift apart.
export const SESSION_STATUS_PAUSED = 'paused';
export const SESSION_STATUS_FINISHED = AGENT_PLATFORM_STATUS_FINISHED.toLowerCase();
export const SESSION_STATUS_FAILED = AGENT_PLATFORM_STATUS_FAILED.toLowerCase();
export const SESSION_STATUS_STOPPED = AGENT_PLATFORM_STATUS_STOPPED.toLowerCase();
export const SESSION_INPUT_REQUIRED_STATUSES = new Set(
  WORKFLOW_AWAITING_INPUT_STATUSES.map((s) => s.toLowerCase()),
);

export const SESSION_RUNNING_STATUSES = new Set(['created', 'running']);

// Keyed by the WorkflowSourceTypeEnum values that the backend currently
// verifies (ee/app/models/ai/duo_workflows/workflow.rb SERVER_SOURCE_TYPES).
// Unlabeled values fall back to the bare sourceLink.
export const SOURCE_TYPE_LABELS = {
  SLACK: s__('DuoAgentPlatform|Slack'),
  MCP: s__('DuoAgentPlatform|MCP'),
};
