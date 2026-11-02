import { s__ } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import {
  SETTING_VALUE_TYPE_BOOLEAN,
  SETTING_VALUE_TYPE_STRING,
} from '../components/editor/constants';

// The settings a `setting_validation` rule can govern, mirroring the catalog
// https://gitlab.com/gitlab-org/gitlab/-/work_items/630152 adds to the `gitlab-policy-store`
// gem entry for entry and key for key — `id`, `value_type`, `values`, `promisable_values`.
// That gem constant is not in this repository yet, so the entries below are copied from
// that issue's branch; the route it serves them on
// (`GET /api/:version/security/policy_store/settings?subject=project`) replaces this array
// with the response and deletes nothing else.
//
// The ids are not a guess: `Govern::PolicyEngine::ProjectSettingsContext` on master emits
// exactly these keys as the evaluation context, and save-time validation
// (https://gitlab.com/gitlab-org/gitlab/-/work_items/630153) rejects any other. The two
// lists silently disagreeing is the failure mode this comment exists to prevent, so widen
// this file only by copying a catalog entry, never by inventing one.
//
// `name` is the catalog's own wording, translated here because the served catalog carries
// no localized names yet.
//
// `promisable_values` are the values a policy may demand. The values it leaves out are
// ones an upper level can still override, which the rule transpiler refuses outright — so
// a restricted setting offers only its promisable values, not every value of its type.
// Where the key is absent, every value of the type qualifies. Which values qualify is the
// gem catalog's call, not this file's: copy the key, never reason it out here.
//
// Polarity note: four of the approval settings are stored under another column name and
// two of them under the opposite value (`Govern::PolicyEngine::ApprovalSettings`). The id
// is what an author pins and what the engine reads, so the inversion never reaches here.
export const SETTINGS = [
  {
    id: 'visibility',
    name: s__('PolicyStore|Visibility'),
    value_type: SETTING_VALUE_TYPE_STRING,
    values: ['private', 'internal', 'public'],
    promisable_values: ['private'],
  },
  {
    id: 'request_access_enabled',
    name: s__('PolicyStore|Allow users to request access'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
  },
  {
    id: 'only_allow_merge_if_pipeline_succeeds',
    name: s__('PolicyStore|Pipelines must succeed'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [true],
  },
  {
    id: 'only_allow_merge_if_all_discussions_are_resolved',
    name: s__('PolicyStore|All threads must be resolved'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [true],
  },
  {
    id: 'remove_source_branch_after_merge',
    name: s__('PolicyStore|Delete source branch by default'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
  },
  {
    id: 'squash_option',
    name: s__('PolicyStore|Squash commits when merging'),
    value_type: SETTING_VALUE_TYPE_STRING,
    values: ['never', 'always', 'default_on', 'default_off'],
  },
  {
    id: 'allow_author_approval',
    name: s__('PolicyStore|Allow author approval'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [false],
  },
  {
    id: 'allow_committer_approval',
    name: s__('PolicyStore|Allow committer approval'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [false],
  },
  {
    id: 'allow_overrides_to_approver_list_per_merge_request',
    name: s__('PolicyStore|Allow approval rule edits'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [false],
  },
  {
    id: 'retain_approvals_on_push',
    name: s__('PolicyStore|Retain approvals on push'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [false],
  },
  {
    id: 'keep_latest_artifact',
    name: s__('PolicyStore|Keep latest artifact'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
    promisable_values: [false],
  },
  {
    id: 'allow_fork_pipelines_to_run_in_parent_project',
    name: s__('PolicyStore|Allow fork pipelines in parent project'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
  },
  {
    id: 'pipeline_variables_minimum_override_role',
    name: s__('PolicyStore|Minimum role to override pipeline variables'),
    value_type: SETTING_VALUE_TYPE_STRING,
    values: ['developer', 'maintainer', 'owner', 'no_one_allowed'],
  },
  {
    id: 'merge_requests_access_level',
    name: s__('PolicyStore|Merge requests access level'),
    value_type: SETTING_VALUE_TYPE_STRING,
    values: ['disabled', 'private', 'enabled'],
  },
  {
    id: 'builds_access_level',
    name: s__('PolicyStore|CI/CD access level'),
    value_type: SETTING_VALUE_TYPE_STRING,
    values: ['disabled', 'private', 'enabled'],
  },
  {
    id: 'forking_access_level',
    name: s__('PolicyStore|Forks access level'),
    value_type: SETTING_VALUE_TYPE_STRING,
    values: ['disabled', 'private', 'enabled'],
  },
  {
    id: 'secret_push_protection_enabled',
    name: s__('PolicyStore|Secret push protection'),
    value_type: SETTING_VALUE_TYPE_BOOLEAN,
  },
];

// Every value any entry above declares, translated. The catalog carries no wording of its
// own, so without this table a French author would read a translated setting name next to
// raw English values. Keyed by the value rather than by setting and value: the ids that
// repeat across settings (`private`, `enabled`, `disabled`) mean the same thing wherever
// they appear. settings_spec pins every declared value to an entry here.
export const VALUE_LABELS = {
  true: s__('PolicyStore|Enabled'),
  false: s__('PolicyStore|Disabled'),
  enabled: s__('PolicyStore|Enabled'),
  disabled: s__('PolicyStore|Disabled'),
  private: s__('PolicyStore|Private'),
  internal: s__('PolicyStore|Internal'),
  public: s__('PolicyStore|Public'),
  never: s__('PolicyStore|Never'),
  always: s__('PolicyStore|Always'),
  default_on: s__('PolicyStore|Default on'),
  default_off: s__('PolicyStore|Default off'),
  developer: s__('PolicyStore|Developer'),
  maintainer: s__('PolicyStore|Maintainer'),
  owner: s__('PolicyStore|Owner'),
  no_one_allowed: s__('PolicyStore|No one'),
};

/**
 * How a setting's value is written on screen. A value the table does not know is humanized
 * rather than dropped, so a catalog that gains a value before this file does still reads as
 * an answer instead of disappearing from a saved policy.
 *
 * @param {*} value - One value of a setting.
 * @returns {string}
 */
export const labelForValue = (value) => VALUE_LABELS[String(value)] ?? humanize(String(value));

/**
 * The values a policy may demand of this setting, as select options. `id` is the value
 * itself, so a boolean option stays a boolean all the way to the persisted rule.
 *
 * @param {Object} setting - A settings catalog entry.
 * @returns {Array|undefined} Options, or undefined when the type enumerates nothing.
 */
export const promisableOptions = (setting) => {
  const permitted =
    setting?.promisable_values ??
    (setting?.value_type === SETTING_VALUE_TYPE_BOOLEAN ? [true, false] : setting?.values);

  return permitted?.map((value) => ({ id: value, label: labelForValue(value) }));
};

/**
 * Whether the catalog narrows this setting to fewer values than its type allows, which is
 * the one thing about an entry an author has to be told rather than shown.
 *
 * @param {Object} setting - A settings catalog entry.
 * @returns {boolean}
 */
export const isRestricted = (setting) => Boolean(setting?.promisable_values);

// The two shapes the catalog's consumers need: the choices an expectations row offers, and
// the entry that row resolves its value control from.
export const SETTING_OPTIONS = SETTINGS.map(({ id, name }) => ({ id, label: name }));

export const SETTINGS_BY_ID = Object.fromEntries(SETTINGS.map((setting) => [setting.id, setting]));
