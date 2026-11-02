import { sprintf, s__ } from '~/locale';
import { TRIGGER_KIND_EVENT } from './triggers';

/**
 * Whether a trigger can be ruled out as answerable by an action. An `event` trigger is told
 * after the change already happened, so nothing hanging off it can stop anything: GOVERN-016
 * has the registry reject a blocking action on an `event` trigger at save time, whatever
 * enforcement mode the policy runs in.
 * https://gitlab.com/gitlab-org/architecture/govern/design-doc/-/merge_requests/28
 *
 * The rule runs one way only. A `gate` trigger may carry a blocking action; it does not have
 * to, and a non-blocking action such as recording the decision is just as valid before the
 * change as after it.
 *
 * A `true` result means the pairing is not ruled out here, not that the store supports it:
 * whether a given trigger's call site implements a given action is per-trigger knowledge that
 * lives in the gitlab-policy-store gem, next to `Roles.for_trigger`.
 *
 * An entry with no `kind` this catalog knows, or that declares no `blocking`, is one the local
 * catalog does not know — a bare entry synthesised for a remote id, or a kind a later ADR
 * revision adds. Both allow the pairing deliberately: hiding something the backend advertises
 * behind a rule the frontend invented is the worse failure.
 *
 * @param {Object|undefined} trigger - The selected trigger's catalog entry, if any.
 * @param {Object} action - An ACTIONS-shaped catalog entry.
 * @returns {boolean}
 */
export const actionAllowedFor = (trigger, action) =>
  trigger?.kind !== TRIGGER_KIND_EVENT || !action?.blocking;

// sprintf must not escape: the reason renders as tooltip text, so escaping here would show
// entities for translated labels like "Projet créé".
const reasonFor = (trigger) =>
  sprintf(
    s__(
      'PolicyStore|Not available with %{trigger}, which runs after the change: there is nothing left to stop.',
    ),
    { trigger: trigger.label },
    false,
  );

/**
 * The actions a trigger cannot be answered with, as a map of action id to the sentence
 * saying why — what `catalog_group.vue` needs to disable an entry and explain it rather
 * than hide it. No trigger selected means nothing is disabled.
 *
 * @param {Object|undefined} trigger - The selected trigger's catalog entry, if any.
 * @param {Array} actions - ACTIONS-shaped catalog entries.
 * @returns {Object}
 */
export const disabledActionReasons = (trigger, actions = []) => {
  const disabled = actions.filter((action) => !actionAllowedFor(trigger, action));

  if (!disabled.length) return {};

  const reason = reasonFor(trigger);

  return Object.fromEntries(disabled.map((action) => [action.id, reason]));
};

// Names the action, unlike the picker's reason: the save blockers are a list, and the
// picker's sentence would repeat verbatim for every blocking action selected. No escaping,
// for the same reason as above — the sentences render through `{{ }}`.
const blockerFor = (trigger, action) =>
  sprintf(
    s__(
      'PolicyStore|%{action} is not available with %{trigger}, which runs after the change: there is nothing left to stop.',
    ),
    { action: action.label, trigger: trigger.label },
    false,
  );

/**
 * Save blockers for selected actions the trigger cannot be answered with. The picker already
 * refuses these pairings, but a policy loaded from the API can hold one, so the review step
 * names it rather than leaving the author to find out from a generic alert at save time.
 * This covers the one rule the frontend knows; per-trigger support is validated per pair in
 * the backend, https://gitlab.com/gitlab-org/gitlab/-/issues/631712.
 *
 * @param {Object} catalogs - `{ triggers, actions }`, TRIGGERS- and ACTIONS-shaped entries.
 * @param {string|null} triggerId - The selected trigger id, if any.
 * @param {string[]} actionIds - The selected action ids.
 * @returns {string[]}
 */
export const actionTriggerBlockers = (
  { triggers = [], actions = [] },
  triggerId,
  actionIds = [],
) => {
  const trigger = triggers.find(({ id }) => id === triggerId);

  if (!trigger) return [];

  return actionIds
    .map((id) => actions.find((action) => action.id === id))
    .filter((action) => action && !actionAllowedFor(trigger, action))
    .map((action) => blockerFor(trigger, action));
};
