import { __, s__ } from '~/locale';

// How a row renders, keyed by the `mergeabilityChecks` status it came back with. `passing` means
// the check cannot hold the merge up, so the row counts towards the progress bar. `extraRow` means
// a check outside the four default rows has enough to say to earn a row of its own.
export const CHECK_STATUS = {
  SUCCESS: {
    icon: 'check-circle-filled',
    variant: 'success',
    stateLabel: s__('AiOverview|Passing'),
    passing: true,
  },
  // Neutral rather than green: the row detail still reports the raw state ("Failed", "3
  // unresolved"), so a green tick beside it would read as a contradiction.
  INACTIVE: {
    icon: 'status-neutral',
    variant: 'subtle',
    stateLabel: s__('AiOverview|Not required'),
    passing: true,
  },
  WARNING: {
    icon: 'warning',
    variant: 'warning',
    stateLabel: s__('AiOverview|Override added'),
    passing: true,
    extraRow: true,
  },
  CHECKING: {
    icon: 'status-running',
    variant: 'info',
    stateLabel: s__('AiOverview|In progress'),
    extraRow: true,
  },
  FAILED: {
    icon: 'error',
    variant: 'danger',
    stateLabel: s__('AiOverview|Blocked'),
    extraRow: true,
  },
};

// Not SUCCESS: a check we have heard nothing about is unknown, and the panel must not turn a gap
// in the data into a confident "Ready to merge".
export const DEFAULT_CHECK_STATUS = 'CHECKING';

// The verdict, in precedence order: one blocked row outranks one still checking, which outranks an
// override. CHECKING is deliberately not "not ready" - the merge gate has not decided yet. The
// last entry names no status, so it wins once none of the ones above it match a row.
export const VERDICTS = [
  {
    checkStatus: 'FAILED',
    title: s__('AiOverview|This merge request is not ready to merge'),
  },
  {
    checkStatus: 'CHECKING',
    title: s__('AiOverview|Checking whether this merge request can be merged'),
  },
  {
    checkStatus: 'WARNING',
    title: s__('AiOverview|Ready to merge, with caution'),
  },
  {
    checkStatus: null,
    title: s__('AiOverview|Ready to merge'),
  },
];

// Merge readiness is only a question while the merge request can still be merged, so these states
// replace the panel rather than being scored as a failing check.
export const NON_OPEN_STATE = {
  merged: {
    title: s__('AiOverview|Merged'),
    summary: s__('AiOverview|This merge request has been merged.'),
  },
  closed: {
    title: s__('AiOverview|Closed'),
    summary: s__('AiOverview|This merge request was closed without being merged.'),
  },
  locked: {
    title: s__('AiOverview|Merge in progress'),
    summary: s__('AiOverview|This merge request is being merged.'),
  },
};

export const CHECK_APPROVALS = 'not_approved';
export const CHECK_DISCUSSIONS = 'discussions_not_resolved';
export const CHECK_PIPELINE = 'ci_must_pass';
export const CHECK_CONFLICTS = 'conflict';

// Row labels, keyed by mergeability check identifier. Shares its keys with FAILURE_REASONS in
// ~/vue_merge_request_widget/components/checks/constants, which supplies the row detail.
export const CHECK_LABELS = {
  not_approved: __('Approvals'),
  approvals_syncing: s__('AiOverview|Approval sync'),
  discussions_not_resolved: s__('AiOverview|Discussions'),
  ci_must_pass: __('Pipeline'),
  conflict: __('Merge conflicts'),
  commits_status: __('Source branch'),
  draft_status: __('Draft'),
  not_open: s__('AiOverview|Merge request state'),
  need_rebase: __('Rebase'),
  need_rebase_merge_train: __('Rebase'),
  merge_request_blocked: __('Merge request dependencies'),
  status_checks_must_pass: __('Status checks'),
  jira_association_missing: s__('AiOverview|Jira issue reference'),
  requested_changes: s__('AiOverview|Requested changes'),
  locked_paths: s__('AiOverview|Locked paths'),
  locked_lfs_files: s__('AiOverview|Locked LFS files'),
  security_policy_violations: __('Security policies'),
  security_policy_pipeline_check: s__('AiOverview|Security policy pipelines'),
  merge_time: s__('AiOverview|Merge time'),
  title_regex: __('Title'),
};

// How a reviewer renders, keyed by the `reviewState` of their `mergeRequestInteraction`. Icons
// follow the reviewer sidebar. UNAPPROVED has no entry and falls back to UNREVIEWED.
export const REVIEWER_STATUS = {
  APPROVED: {
    icon: 'check-circle-filled',
    variant: 'success',
    textClass: 'gl-text-success',
    stateLabel: __('Approved'),
  },
  REQUESTED_CHANGES: {
    icon: 'error',
    variant: 'danger',
    textClass: 'gl-text-danger',
    stateLabel: __('Requested changes'),
  },
  REVIEWED: {
    icon: 'comment-lines',
    variant: 'info',
    textClass: 'gl-text-info',
    stateLabel: __('Commented'),
  },
  REVIEW_STARTED: {
    icon: 'comment-dots',
    variant: 'subtle',
    textClass: 'gl-text-subtle',
    stateLabel: __('Review started'),
  },
  UNREVIEWED: {
    icon: 'dash-circle',
    variant: 'subtle',
    textClass: 'gl-text-subtle',
    stateLabel: __('Awaiting review'),
  },
};
