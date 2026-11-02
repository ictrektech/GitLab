import {
  BUILD_TAB_ACTIONS,
  BUILD_TAB_RULES,
  BUILD_TAB_TRIGGERS,
} from '../components/editor/constants';
import { ACTION_REQUIRE_APPROVAL } from './actions';
import { RULE_CALENDAR, RULE_CUSTOM, RULE_ENVIRONMENT } from './rules';
import {
  TRIGGER_DEPLOYMENT_PROMOTED,
  TRIGGER_DEPLOYMENT_REQUESTED,
  TRIGGER_ENVIRONMENT_ADVANCED,
} from './triggers';

// Catalog entries the Policy Store still supports end to end, but that are not ready to be
// authored: the builder leaves them out of its pickers. Nothing else changes — the API still
// offers them, the store still accepts them, and a policy already using one still opens,
// renders its real label and its configuration, and can be edited and saved. To offer one
// again, delete its id from this list.
//
// The deployment triggers and the calendar and environment rules come from the CD deployment
// experiment, which was wound up without shipping:
// https://gitlab.com/groups/gitlab-org/-/epics/22027
// Custom Rego is hidden until authoring it is ready for users:
// https://gitlab.com/groups/gitlab-org/-/epics/23462
//
// `block` is offered again because the settings fence consumes its decisions at the save
// point (https://gitlab.com/gitlab-org/gitlab/-/merge_requests/261838,
// https://gitlab.com/gitlab-org/gitlab/-/issues/630156). That fence is not merged yet, and
// until it is, offering `block` tells an author a change will be stopped while nothing stops
// it — so this file must not merge ahead of it. What is new with a blocking action offered is
// that the picker can render a disabled entry; `disabledActionReasons` itself already ran on
// every trigger change, over the full catalog rather than the offered subset.
//
// `require_approval` stays hidden for the reason `block` used to be: it has no executor and
// nothing anywhere collects approvals, so it waits on a surface for them existing, not on a
// particular MR.
//
// The ids are the API's wire values, matched exactly, so they have to track the
// gitlab-policy-store gem's catalogue; hidden_spec.js fails if one stops naming a real
// entry, which is also what a rename in the gem would look like here.
export const HIDDEN_CATALOG_IDS = {
  [BUILD_TAB_TRIGGERS]: [
    TRIGGER_DEPLOYMENT_REQUESTED,
    TRIGGER_ENVIRONMENT_ADVANCED,
    TRIGGER_DEPLOYMENT_PROMOTED,
  ],
  [BUILD_TAB_RULES]: [RULE_CUSTOM, RULE_CALENDAR, RULE_ENVIRONMENT],
  [BUILD_TAB_ACTIONS]: [ACTION_REQUIRE_APPROVAL],
};
