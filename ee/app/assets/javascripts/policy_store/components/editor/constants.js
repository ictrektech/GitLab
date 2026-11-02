import { s__ } from '~/locale';

export const STEP_BUILD = 'build';
export const STEP_SCOPE = 'scope';
export const STEP_REVIEW = 'review';

export const STEP_ORDER = [STEP_BUILD, STEP_SCOPE, STEP_REVIEW];

export const STEP_LABELS = {
  [STEP_BUILD]: s__('PolicyStore|Build policy'),
  [STEP_SCOPE]: s__('PolicyStore|Select scope'),
  [STEP_REVIEW]: s__('PolicyStore|Review impact'),
};

// Authoring caps matching the store's TEXT_LIMITS
// (gems/gitlab-policy-store, ports/policy_repository.rb). maxlength counts
// UTF-16 units where the store counts characters, so the UI is never looser.
export const POLICY_NAME_MAX_LENGTH = 255;
export const POLICY_DESCRIPTION_MAX_LENGTH = 4096;

export const STATUS_COMPLETE = 'complete';
export const STATUS_CURRENT = 'current';
export const STATUS_UPCOMING = 'upcoming';

export const ARIA_CURRENT_STEP = 'step';

// The `type` a catalog item's `fields` entry declares. ConfigWrapper renders one
// component per type. Taken from the catalog the prototype declares in
// prototype/src/prototypes/policies-v2/catalog.js
// (gitlab-com/gitlab-ux/security-compliance-ux/srm-ux-group/policies-v2), narrowed to
// the types the CD deployment gate's triggers, rules and actions actually use.
export const FIELD_TYPE_TEXT = 'text';
// A text input whose persisted value is a comma-split string array.
export const FIELD_TYPE_TEXT_LIST = 'text_list';
export const FIELD_TYPE_TEXTAREA = 'textarea';
export const FIELD_TYPE_SELECT = 'select';
// A select whose options are filtered as the user types, for lists too long to scan.
export const FIELD_TYPE_SEARCHABLE_SELECT = 'searchable_select';
export const FIELD_TYPE_CHECKBOX = 'checkbox';
export const FIELD_TYPE_MULTI_BADGE = 'multi_badge';
export const FIELD_TYPE_FREEZE_WINDOWS = 'freeze_windows';
export const FIELD_TYPE_CODE = 'code';
// A number input, honouring the `min` and `max` the field declares.
export const FIELD_TYPE_NUMBER = 'number';
// Rows of `{ setting, expected }` pairs, each of which the serializer persists as its own
// rule. See fields/setting_expectations_field.vue.
export const FIELD_TYPE_SETTING_EXPECTATIONS = 'setting_expectations';

// Every type the renderer supports; catalog_spec checks catalog data against it.
export const FIELD_TYPES = [
  FIELD_TYPE_TEXT,
  FIELD_TYPE_TEXT_LIST,
  FIELD_TYPE_TEXTAREA,
  FIELD_TYPE_SELECT,
  FIELD_TYPE_SEARCHABLE_SELECT,
  FIELD_TYPE_CHECKBOX,
  FIELD_TYPE_MULTI_BADGE,
  FIELD_TYPE_FREEZE_WINDOWS,
  FIELD_TYPE_CODE,
  FIELD_TYPE_NUMBER,
  FIELD_TYPE_SETTING_EXPECTATIONS,
];

// The `value_type` a settings catalog entry declares, from `Gitlab::PolicyStore::Settings`.
// Distinct from FIELD_TYPE_*: these describe a setting, not a form control. The contract's
// third type, `integer`, has no catalog entry and so draws no control yet.
export const SETTING_VALUE_TYPE_BOOLEAN = 'boolean';
export const SETTING_VALUE_TYPE_STRING = 'string';

export const BUILD_TAB_TRIGGERS = 'triggers';
export const BUILD_TAB_RULES = 'rules';
export const BUILD_TAB_ACTIONS = 'actions';

// Re-export namespace constants from the shared location for backward compatibility.
export { NAMESPACE_TYPE_GROUP, NAMESPACE_TYPE_ORGANIZATION } from '../../constants';

export const SCOPE_ALL = 'all';
export const SCOPE_SPECIFIC = 'specific';

export const ENFORCEMENT_ENFORCE = 'enforce';
export const ENFORCEMENT_WARN = 'warn';
export const ENFORCEMENT_AUDIT = 'audit';

// The store defaults a new policy to warn, and the wizard always sends a mode,
// so proposing anything else here would quietly override that default.
export const ENFORCEMENT_DEFAULT = ENFORCEMENT_WARN;

export const ENFORCEMENT_MODES = [
  {
    value: ENFORCEMENT_ENFORCE,
    text: s__('PolicyStore|Enforce'),
    description: s__('PolicyStore|Run every action when rules match'),
    icon: 'status-failed',
    variant: 'danger',
  },
  {
    value: ENFORCEMENT_WARN,
    text: s__('PolicyStore|Warn'),
    description: s__('PolicyStore|Warn the user; nothing is blocked or changed'),
    icon: 'status-alert',
    variant: 'warning',
  },
  {
    value: ENFORCEMENT_AUDIT,
    text: s__('PolicyStore|Audit'),
    description: s__('PolicyStore|Record the match; nothing is blocked, changed, or shown'),
    icon: 'status-neutral',
    variant: 'info',
  },
];
