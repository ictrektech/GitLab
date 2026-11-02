import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { NAMESPACE_TYPE_GROUP, NAMESPACE_TYPE_ORGANIZATION } from './constants';
import { ACTIONS } from './catalog/actions';
import { RULES } from './catalog/rules';
import { TRIGGERS } from './catalog/triggers';

/**
 * A rejected GraphQL mutation's user-facing store message, thrown so callers
 * can tell a store rejection from a failed request.
 */
export class PolicyStoreMutationError extends Error {
  constructor(message) {
    super(message);
    // Sentry groups by error.name, which plain subclassing leaves as 'Error'.
    this.name = 'PolicyStoreMutationError';
  }
}

/**
 * Rejects a mutation whose payload carries store errors, so a component
 * awaiting `this.$apollo.mutate` handles a store rejection and a failed
 * request in the same catch. Joined defensively: the backend returns one
 * message, but a joined pair must still fall through the exact-match
 * predicates below rather than hide a second failure.
 *
 * @param {string[]} errors - The mutation payload's `errors`.
 */
export const throwStoreErrors = (errors) => {
  if (errors?.length) throw new PolicyStoreMutationError(errors.join(', '));
};

/**
 * Reads a mutation's payload field, rejecting a response that has none or
 * whose payload carries store errors. Apollo already rejects a top-level
 * error, so a response with neither an error nor a payload is malformed; it
 * is thrown as a plain Error so the caller falls back to its generic copy.
 *
 * @param {Object} data - The `data` of a resolved `this.$apollo.mutate`.
 * @param {string} field - The payload field, such as `governPolicyUpdate`.
 * @returns {Object} The payload.
 */
export const readMutationPayload = (data, field) => {
  const payload = data?.[field];

  if (!payload) throw new Error(`Policy store mutation returned no ${field} payload`);

  throwStoreErrors(payload.errors);

  return payload;
};

/**
 * Reads the reason the Policy Store rejected a write from a failed request.
 *
 * A rejected mutation carries it as the PolicyStoreMutationError message. The
 * mutations also raise user-facing top-level GraphQL errors (a missing
 * policy, the experiment being off, an engine fault), which Apollo rejects as
 * an error with `graphQLErrors`. A plain request error yields nothing, so
 * callers keep their own copy. An empty-string message is returned as-is, so
 * callers should fall back to their own generic copy on any falsy result.
 *
 * @param {Error} error - The error from the failed request.
 * @returns {string|undefined} The store's message, if the error carried one.
 */
export const apiErrorMessage = (error) => {
  if (error instanceof PolicyStoreMutationError) return error.message;

  // Top-level GraphQL errors; a plain request error has none.
  return error?.graphQLErrors?.[0]?.message;
};

export const EMPTY_CATALOGS = Object.freeze({
  triggers: [],
  rules: [],
  actions: [],
});

const LOCAL_CATALOGS = { triggers: TRIGGERS, rules: RULES, actions: ACTIONS };

export const CATALOG_NAMES = Object.freeze(Object.keys(LOCAL_CATALOGS));

export const presentable = ({ id, name }, localCatalog) =>
  localCatalog.find((entry) => entry.id === id) ?? {
    id,
    label: name || id,
    description: '',
    icon: 'question-o',
    fields: [],
  };

const toCatalog = (name, remoteEntries) => {
  const entries = Array.isArray(remoteEntries) ? remoteEntries.filter((remote) => remote?.id) : [];

  // An empty catalog cannot build a policy, so a healthy-but-empty response is
  // as unusable as a missing one.
  if (!entries.length) {
    Sentry.captureException(new Error(`Policy Store returned no ${name}`), {
      tags: { policyStoreCatalog: name },
    });

    return null;
  }

  return entries.map((remote) => presentable(remote, LOCAL_CATALOGS[name]));
};

/**
 * Maps the `policyStore` GraphQL payload to the wizard's catalogs.
 *
 * The local catalog files supply the presentation (label, description, icon,
 * category, config fields) for the ids the API returns. Each catalog fails
 * independently: one that is missing or empty resolves as an empty list and
 * its name appears in `failedCatalogs`, while the others keep their entries.
 * Every failure is reported to Sentry, tagged with the failing catalog.
 *
 * @param {Object|null} policyStore - The `organization.policyStore` query
 *   result; null when the experiment is not active for the organization.
 * @returns {{ catalogs: { triggers: Array, rules: Array, actions: Array },
 *   failedCatalogs: string[] }}
 */
export const toCatalogs = (policyStore) => {
  // Not EMPTY_CATALOGS: that object is frozen and shared, but this one
  // gets filled in below, so it needs to be a fresh, mutable object.
  const catalogs = { triggers: [], rules: [], actions: [] };
  const failedCatalogs = [];

  CATALOG_NAMES.forEach((name) => {
    const entries = toCatalog(name, policyStore?.[name]);

    if (entries) {
      catalogs[name] = entries;
    } else {
      failedCatalogs.push(name);
    }
  });

  return { catalogs, failedCatalogs };
};

/**
 * Whether a store message reports the org-wide unique-name rule was violated.
 *
 * Matched exactly: both store backends raise this bare string, and the
 * ActiveRecord backend joins multiple validation failures into one sentence —
 * a combined message must fall through to the page alert so the other
 * failure reasons stay visible.
 *
 * @param {string|undefined} message - The message from apiErrorMessage.
 * @returns {boolean} Whether the save failed only because the name is taken.
 */
export const isDuplicateNameError = (message) =>
  /^name has already been taken$/i.test((message || '').trim());

const RULE_REGO_PARSE_REFUSAL = /^rules\[\d+\] is invalid:/i;

/**
 * Whether a store message reports a rule whose Rego does not parse.
 *
 * Matched on the whole message, not on segments: the store reports only the
 * first unparseable rule, as `rules[N] is invalid: <engine message> (at
 * <line>:<column>)`, and joins that one rule's engine errors with `; ` inside
 * it — so a two-typo program is still a single refusal.
 *
 * A merged-module failure (`policy_merged_program is invalid: ...`) is raised
 * as a top-level engine error, not a payload error, so it is deliberately not
 * matched here.
 *
 * @param {string|undefined} message - The message from apiErrorMessage.
 * @returns {boolean} Whether the save failed on unparseable rule Rego.
 */
export const isRuleRegoParseError = (message) =>
  RULE_REGO_PARSE_REFUSAL.test((message || '').trim());

/**
 * Whether a policy can be changed from the container currently listing it.
 * The store accepts a write from the organization, or from the one group the
 * policy belongs to; every other container rejects it as "not found", whether
 * the policy is inherited from an ancestor or owned by a descendant. The
 * group is matched by path because that is the only container identity a page
 * is given.
 *
 * This answers "writable from here", not "may this user write" — the two are
 * independent, and a page gates an action on both.
 *
 * @param {Object} policy - A policy from toListPolicies or toPolicy.
 * @param {Object} container
 * @param {string} container.namespaceType - The container the page renders for.
 * @param {string} container.namespacePath - The viewed group's full path, blank for an organization.
 * @returns {boolean} Whether this page can edit, disable or delete the policy.
 */
export const isPolicyWritable = (policy, { namespaceType, namespacePath }) => {
  if (namespaceType === NAMESPACE_TYPE_ORGANIZATION) return true;
  // Matched explicitly rather than as "not an organization": the project
  // surface lists policies it can never write.
  if (namespaceType !== NAMESPACE_TYPE_GROUP) return false;

  return Boolean(policy?.group?.fullPath) && policy.group.fullPath === namespacePath;
};
