import { s__ } from '~/locale';
import { CATEGORY_COMPLIANCE, CATEGORY_DEPLOYMENT } from './categories';

// GOVERN-016's kinds, spelled as the ADR spells them and as the registry's `kind` sends
// them. A `schedule` trigger is neither asked nor told: the engine starts it itself, so
// no author can answer it and only RECORDED_TRIGGERS carries one.
export const TRIGGER_KIND_GATE = 'gate';
export const TRIGGER_KIND_EVENT = 'event';
export const TRIGGER_KIND_SCHEDULE = 'schedule';

// Triggers a policy can respond to. `id` is persisted as the policy's `trigger_type`, so it
// is the wire value and must match what the metadata endpoint returns.
//
// `kind` is GOVERN-016's: a `gate` trigger is asked before the change and may be answered by
// stopping it, an `event` trigger is told after the fact and cannot be. It decides the
// actions a trigger can be answered with. See `compatibility.js` and the ADR:
// https://gitlab.com/gitlab-org/architecture/govern/design-doc/-/merge_requests/28
//
// The CD deployment gate experiment ships the three deployment lifecycle triggers.
// See https://gitlab.com/gitlab-org/gitlab/-/issues/607341 for scope.
export const TRIGGER_DEPLOYMENT_REQUESTED = 'deployment_requested';
export const TRIGGER_ENVIRONMENT_ADVANCED = 'environment_advanced';
export const TRIGGER_DEPLOYMENT_PROMOTED = 'deployment_promoted';

// Settings enforcement (https://gitlab.com/groups/gitlab-org/-/work_items/23462). The ADR
// makes the periodic drift check author-facing, but the gem's authoring catalogue omits it
// deliberately — the engine records it on a schedule and no author can answer it. That sweep
// covers every settings policy whatever trigger it was authored with, which is why the
// settings-change, project-created and project-transferred descriptions all say so rather
// than only the change-requested one.
//
// The sweep itself arrives in https://gitlab.com/gitlab-org/gitlab/-/merge_requests/261561,
// so those three descriptions must not merge ahead of it or they describe a daily check that
// is not running.
export const TRIGGER_PROJECT_SETTINGS_CHANGE_REQUESTED = 'project.before_settings_update';
export const TRIGGER_PROJECT_SETTINGS_DRIFT_CHECKED = 'project.scheduled_settings_drift_check';

// Project lifecycle (https://gitlab.com/gitlab-org/gitlab/-/work_items/630210). None of
// these carry configuration: the event itself is the whole condition, and what a policy
// checks about the project is the rules' job.
export const TRIGGER_PROJECT_CREATED = 'project.after_create';
export const TRIGGER_PROJECT_TRANSFERRED = 'project.after_transfer';

export const TRIGGERS = [
  {
    id: TRIGGER_DEPLOYMENT_REQUESTED,
    kind: TRIGGER_KIND_GATE,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Deployment requested'),
    description: s__('PolicyStore|When a deployment to a gated environment is requested'),
    icon: 'deployments',
    fields: [],
  },
  {
    id: TRIGGER_ENVIRONMENT_ADVANCED,
    kind: TRIGGER_KIND_GATE,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Environment advanced'),
    description: s__('PolicyStore|When a deployment advances to the next environment'),
    icon: 'environment',
    fields: [],
  },
  {
    id: TRIGGER_DEPLOYMENT_PROMOTED,
    kind: TRIGGER_KIND_GATE,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Deployment promoted'),
    description: s__('PolicyStore|When an existing deployment is promoted to a new environment'),
    icon: 'upgrade',
    fields: [],
  },
  {
    id: TRIGGER_PROJECT_SETTINGS_CHANGE_REQUESTED,
    kind: TRIGGER_KIND_GATE,
    category: CATEGORY_COMPLIANCE,
    label: s__('PolicyStore|Project settings change requested'),
    description: s__(
      'PolicyStore|When a change to a project setting is requested, before it is saved. Settings policies are also checked daily.',
    ),
    icon: 'settings',
    fields: [],
  },
  {
    id: TRIGGER_PROJECT_CREATED,
    // An event, not a gate: creation inherits some settings only after the project
    // row exists, so there is nothing left to gate by the time this fires.
    kind: TRIGGER_KIND_EVENT,
    category: CATEGORY_COMPLIANCE,
    label: s__('PolicyStore|Project created'),
    description: s__(
      'PolicyStore|When a new project has been created. Settings policies are also checked daily.',
    ),
    icon: 'project',
    fields: [],
  },
  {
    id: TRIGGER_PROJECT_TRANSFERRED,
    kind: TRIGGER_KIND_EVENT,
    category: CATEGORY_COMPLIANCE,
    label: s__('PolicyStore|Project transferred'),
    description: s__(
      'PolicyStore|When a project moves to a different namespace. Settings policies are also checked daily.',
    ),
    icon: 'arrow-right',
    fields: [],
  },
];

// Triggers the engine records on an evaluation but nobody authors. The gem draws the same
// line: `TYPES` is the persisted vocabulary and `ALL` the authoring catalogue, and the
// drift check is in `TYPES` only. These entries exist to give a recorded evaluation a
// label instead of its wire id; they can never reach the editor's picker, which
// `toCatalogs()` builds from the remote catalogue the API serves.
export const RECORDED_TRIGGERS = [
  {
    id: TRIGGER_PROJECT_SETTINGS_DRIFT_CHECKED,
    kind: TRIGGER_KIND_SCHEDULE,
    category: CATEGORY_COMPLIANCE,
    label: s__('PolicyStore|Daily settings check'),
    description: s__(
      'PolicyStore|When the daily check compared a project setting against the policy. This check runs on every settings policy and cannot be selected when creating one.',
    ),
    icon: 'clock',
    fields: [],
  },
];

// Every trigger a stored record can name, for surfaces that resolve a label rather than
// offer a choice. Authoring surfaces read TRIGGERS.
export const ALL_TRIGGERS = [...TRIGGERS, ...RECORDED_TRIGGERS];
