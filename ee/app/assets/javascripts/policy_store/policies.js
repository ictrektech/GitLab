import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPE_ORGANIZATION } from '~/graphql_shared/constants';
import { convertObjectPropsToSnakeCase } from '~/lib/utils/common_utils';
import { s__ } from '~/locale';
import { presentable } from './utils';
import { TRIGGERS } from './catalog/triggers';
import {
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
  NAMESPACE_TYPE_PROJECT,
} from './constants';

// Same resolution the wizard uses: the local catalog supplies the label for ids
// it knows, the API-provided name covers newer triggers, the raw id is the last
// resort. Keeps the list and the editor rendering the same trigger the same way.
const triggerLabel = (triggerType, remoteTriggers) =>
  presentable(remoteTriggers.find(({ id }) => id === triggerType) ?? { id: triggerType }, TRIGGERS)
    .label;

// A stored criterion is a plain array of ids or `{ id }` hashes.
const scopedProjectsCount = (policyScope) => {
  const including = policyScope?.projects?.including;

  return Array.isArray(including) ? including.length : 0;
};

/**
 * Maps the `policyStore` GraphQL payload to the rows the list renders — the
 * same derived columns as toPolicy, straight from the camelCase GraphQL fields.
 * trigger_type, rules and actions stay snake_case because config_info.vue
 * deserializes them from the row.
 *
 * @param {Object|null} policyStore - The `group.policyStore` or
 *   `organization.policyStore` query result; null when the experiment is not
 *   active for the container.
 * @returns {Array} The list rows.
 */
export const toListPolicies = (policyStore) => {
  const triggers = (policyStore?.triggers ?? []).filter((trigger) => trigger?.id);

  return (policyStore?.policies?.nodes ?? []).map((policy) => ({
    id: policy.id,
    name: policy.name,
    mode: policy.mode,
    inherited: policy.inherited,
    group: policy.group,
    // The source cell renders from `group` and `inherited`; this is the value
    // the column sorts on, which a slot-only column would not have. Keyed on
    // the owner rather than the rendered label so every policy from one owner
    // sorts together, whether the row reads "Flight" or "Inherited from Flight".
    source: policy.group?.name ?? s__('PolicyStore|Organization'),
    trigger_type: policy.triggerType,
    rules: policy.rules,
    actions: policy.actions,
    updated_at: policy.updatedAt,
    type: triggerLabel(policy.triggerType, triggers),
    status: policy.lifecycleState,
    scopedProjectsCount: scopedProjectsCount(policy.policyScope),
  }));
};

/**
 * Maps a single-policy read of the `policyStore` GraphQL payload to the
 * policy the detail page renders and the editor loads back into the wizard,
 * with the same derived columns as the list. The raw fields are snake_cased
 * because deserializePolicyData and deserializeScope read the shape the store
 * persists. Trigger labels come from the triggers the same document carries.
 *
 * @param {Object|null} policyStore - The `group.policyStore` or
 *   `organization.policyStore` query result, queried for exactly one policy id.
 * @returns {Object|null} The policy, or null when the read produced none:
 *   an unknown id, a denied read (null connection) or an inactive store.
 */
export const toPolicy = (policyStore) => {
  const policy = policyStore?.policies?.nodes?.[0];

  if (!policy) return null;

  const triggers = (policyStore.triggers ?? []).filter((trigger) => trigger?.id);

  // Shallow on purpose: the free-form JSON fields keep their stored shape.
  return {
    ...convertObjectPropsToSnakeCase(policy, { dropKeys: ['__typename'] }),
    type: triggerLabel(policy.triggerType, triggers),
    status: policy.lifecycleState,
    scopedProjectsCount: scopedProjectsCount(policy.policyScope),
  };
};

// GraphQL Int is 32-bit; widen together with the id field when it moves to a
// wider type. policies_spec pins this to the type the documents declare.
const MAX_POLICY_STORE_ID = 2 ** 31 - 1;

/**
 * Parses a policy store id as the GraphQL boundary takes it: a plain Int, not
 * a GlobalID. Pages receive it as a string from the URL or the dataset, whose
 * routes already limit it to digits, so only a value above the Int range can
 * arrive malformed; the digits rule is still applied so a caller cannot pass
 * a hex or exponent string that Number() would quietly accept. Ids start at
 * 1, so 0 cannot name a policy and is rejected like any other non-id.
 *
 * @param {string|number} value - The id as a page or caller supplied it.
 * @returns {number|null} The integer id, or null when the value cannot name a policy.
 */
export const policyStoreId = (value) => {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  if (!/^\d+$/.test(String(value))) return null;

  const id = Number(value);

  return id >= 1 && id <= MAX_POLICY_STORE_ID ? id : null;
};

// The serializer emits the store's snake_case shape; these are the keys whose
// mutation argument is spelled differently. Only supplied keys are mapped: the
// update mutation keeps omitted fields and clears on an explicit null, so a
// missing policy_scope must not arrive as policyScope: null.
const MUTATION_VARIABLE_NAMES = {
  trigger_type: 'triggerType',
  policy_scope: 'policyScope',
  lifecycle_state: 'lifecycleState',
};

const declaredVariables = (document) =>
  new Set(
    document.definitions
      .find((definition) => definition.kind === 'OperationDefinition')
      .variableDefinitions.map((definition) => definition.variable.name.value),
  );

// Update names it policyId, delete names it id; create declares neither, so
// an id sent to it would be dropped as silently as any undeclared variable.
const ID_VARIABLE_NAMES = ['policyId', 'id'];

// A blank id is "no policy", as singlePolicyQuery's skip() reads it: the
// editor's new-policy page injects policyId as ''.
const idVariable = (document, policyId) => {
  if (policyId === undefined || policyId === null || policyId === '') return {};

  const declared = declaredVariables(document);
  const name = ID_VARIABLE_NAMES.find((candidate) => declared.has(candidate));

  if (!name) {
    // eslint-disable-next-line @gitlab/require-i18n-strings
    throw new Error('Policy store mutation declares no id argument');
  }

  const id = policyStoreId(policyId);

  // Constant message: an interpolated id would split one Sentry issue per policy.
  if (id === null) {
    // eslint-disable-next-line @gitlab/require-i18n-strings
    throw new Error('Policy store id is not a valid Int');
  }

  return { [name]: id };
};

// The container comes from the caller, never from the params: a param naming
// the other container would send both non-null values and fail the server's
// exactly-one-of check. Both spellings, since params arrive in the store's
// snake_case shape.
const CONTAINER_VARIABLE_NAMES = new Set([
  'organizationId',
  'organization_id',
  'groupPath',
  'group_path',
]);

// The server ignores a variable the document does not declare, so a param
// nobody mapped would be dropped silently instead of failing. Each mutation
// declares its own set, so the check runs against the document being sent.
const toMutationVariables = (document, params) => {
  const declared = declaredVariables(document);

  return Object.fromEntries(
    Object.entries(params).map(([key, value]) => {
      const name = MUTATION_VARIABLE_NAMES[key] ?? key;

      if (CONTAINER_VARIABLE_NAMES.has(name)) {
        throw new Error(`Policy store param is a container argument: ${key}`);
      }

      if (!declared.has(name)) {
        throw new Error(`Policy store param not declared by the mutation: ${key}`);
      }

      return [name, value];
    }),
  );
};

// No document requires its container variable, so a missing or empty
// identifier would reach the server as no container (or an empty path) and
// surface its raw error. Falsy also rejects 0, which is never a valid
// organization id.
const requireContainerIdentifier = (namespaceIdentifier) => {
  if (namespaceIdentifier) return;

  // Constant Sentry-facing message, never rendered: apiErrorMessage yields
  // nothing for a plain Error, so callers fall back to their own copy.
  // eslint-disable-next-line @gitlab/require-i18n-strings
  throw new Error('Policy store container identifier is blank');
};

/**
 * Exactly one container variable for the policy store query documents, which
 * read a group by `fullPath` and an organization by `id`. The mutation
 * documents spell theirs differently; see policyMutationVariables.
 *
 * @param {string} namespaceType - One of the NAMESPACE_TYPE_* constants.
 * @param {string|number} namespaceIdentifier - The group's or project's full path, or the
 *   organization's id.
 * @returns {Object} `{ fullPath }` for a group or project, `{ id }` for an organization.
 * @throws {Error} When the identifier is blank.
 */
export const containerQueryVariables = (namespaceType, namespaceIdentifier) => {
  requireContainerIdentifier(namespaceIdentifier);

  return namespaceType === NAMESPACE_TYPE_ORGANIZATION
    ? { id: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier) }
    : { fullPath: namespaceIdentifier };
};

/**
 * Reads the container's policyStore out of a query result, whichever root
 * field the document used.
 *
 * @param {Object|null|undefined} data - The query result's data.
 * @param {string} namespaceType - One of the NAMESPACE_TYPE_* constants.
 * @returns {Object|null|undefined} The policyStore, null when the read was denied.
 */
export const policyStoreFrom = (data, namespaceType) => {
  if (namespaceType === NAMESPACE_TYPE_GROUP) return data?.group?.policyStore;
  if (namespaceType === NAMESPACE_TYPE_PROJECT) return data?.project?.policyStore;

  return data?.organization?.policyStore;
};

// Exactly one container argument for the mutation documents.
const containerVariables = (namespaceType, namespaceIdentifier) => {
  requireContainerIdentifier(namespaceIdentifier);

  // A project is read-only, so no mutation document takes one. Without this the
  // project's path would be sent as an organization's id.
  if (namespaceType === NAMESPACE_TYPE_PROJECT) {
    // eslint-disable-next-line @gitlab/require-i18n-strings
    throw new Error('Policy store mutations have no project container');
  }

  return namespaceType === NAMESPACE_TYPE_GROUP
    ? { groupPath: namespaceIdentifier }
    : { organizationId: convertToGraphQLId(TYPE_ORGANIZATION, namespaceIdentifier) };
};

/**
 * Builds the variables for a policy store mutation a component sends through
 * `this.$apollo.mutate`: the supplied params mapped to the document's
 * arguments plus exactly one container argument. The container branch lives
 * here so no component has to know how a group or an organization is named.
 *
 * @param {Object} options
 * @param {Object} options.document - The mutation the variables are built for.
 * @param {string} options.namespaceType - NAMESPACE_TYPE_GROUP or NAMESPACE_TYPE_ORGANIZATION
 * @param {string|number} options.namespaceIdentifier - For groups: the full path
 *   (e.g. 'my-org/my-group'). For organizations: the numeric ID.
 * @param {string|number} [options.policyId] - The policy an update or delete targets,
 *   sent as whichever id argument the document declares; a blank id sends none.
 *   Throws on an id that cannot name a policy, or when the document declares no
 *   id argument.
 * @param {Object} [options.params] - Params from serializePolicyParams, or a subset
 *   such as `{ lifecycle_state }`. Throws on a param the document does not declare
 *   or one that names a container.
 * @returns {Object} The mutation variables.
 */
export const policyMutationVariables = ({
  document,
  namespaceType,
  namespaceIdentifier,
  policyId,
  params = {},
}) => ({
  ...toMutationVariables(document, params),
  ...idVariable(document, policyId),
  ...containerVariables(namespaceType, namespaceIdentifier),
});
