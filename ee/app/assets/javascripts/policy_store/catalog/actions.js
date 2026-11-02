import { s__ } from '~/locale';
import { FIELD_TYPE_MULTI_BADGE, FIELD_TYPE_TEXT } from '../components/editor/constants';
import { CATEGORY_COMPLIANCE, CATEGORY_ENFORCEMENT } from './categories';
import { RULE_SETTING_VALIDATION } from './rules';

// Actions a policy can take when its rules match. `id` is persisted as the action object's
// `type`, and the write endpoints constrain it to Gitlab::PolicyStore::Actions::ALL, so an id
// the gem does not hold cannot be saved. Nothing applies an action yet — the gem's
// RoleValidation is the only reader, and it inspects `require_approval` alone.
//
// `blocking` says whether the action stops the thing the trigger is asking about, which rules
// out the triggers it cannot answer: only a `gate` trigger can be stopped. It does not
// establish the pairing is supported. See `compatibility.js` and the ADR:
// https://gitlab.com/gitlab-org/architecture/govern/design-doc/-/merge_requests/28
//
// There is deliberately no `warn` action: warn is an enforcement *mode*, and `block` behaves
// differently depending on it. See https://gitlab.com/gitlab-org/gitlab/-/issues/607341.
export const ACTION_BLOCK = 'block';
export const ACTION_REQUIRE_APPROVAL = 'require_approval';
export const ACTION_LOG_AUDIT_TRAIL = 'log_audit_trail';
export const ACTION_SET_SETTING = 'set_setting';

export const ACTIONS = [
  {
    id: ACTION_BLOCK,
    blocking: true,
    category: CATEGORY_ENFORCEMENT,
    label: s__('PolicyStore|Block'),
    description: s__('PolicyStore|Block the action from proceeding'),
    icon: 'cancel',
    fields: [
      {
        key: 'message',
        type: FIELD_TYPE_TEXT,
        label: s__('PolicyStore|Block message'),
        placeholder: s__('PolicyStore|Message shown when the action is blocked'),
      },
    ],
  },
  {
    id: ACTION_REQUIRE_APPROVAL,
    blocking: true,
    category: CATEGORY_ENFORCEMENT,
    label: s__('PolicyStore|Require approval'),
    description: s__('PolicyStore|Require additional approvals before proceeding'),
    icon: 'approval',
    fields: [
      {
        key: 'roles',
        type: FIELD_TYPE_MULTI_BADGE,
        label: s__('PolicyStore|Role approvers'),
        options: [
          { id: 'developer', label: s__('PolicyStore|Developer') },
          { id: 'maintainer', label: s__('PolicyStore|Maintainer') },
          { id: 'owner', label: s__('PolicyStore|Owner') },
        ],
      },
    ],
  },
  {
    id: ACTION_LOG_AUDIT_TRAIL,
    // Non-blocking, so an event trigger can be answered with it. See `compatibility.js`.
    // That it also runs in every enforcement mode is the engine's call, not this catalog's.
    blocking: false,
    category: CATEGORY_COMPLIANCE,
    label: s__('PolicyStore|Log audit trail'),
    description: s__('PolicyStore|Record the violation as a GitLab audit event'),
    icon: 'audit-events',
    // No fields: the executor builds the event from the decision that matched, so there is
    // nothing here for an author to configure.
    fields: [],
  },
  {
    id: ACTION_SET_SETTING,
    // Non-blocking, so an event trigger can be answered with it. See `compatibility.js`.
    blocking: false,
    category: CATEGORY_COMPLIANCE,
    label: s__('PolicyStore|Set project setting'),
    description: s__(
      'PolicyStore|In enforce mode, write the required value onto the project on arrival, and again whenever the daily settings check finds it changed',
    ),
    icon: 'pencil-square',
    // No fields: the setting and the value come from the rule, not from here, which makes that
    // rule a requirement rather than a pairing — without it the policy says "write the required
    // setting" and names no setting anywhere.
    requiresRule: RULE_SETTING_VALIDATION,
    fields: [],
  },
];
