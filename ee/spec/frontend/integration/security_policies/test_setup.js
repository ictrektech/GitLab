import { load } from 'js-yaml';
import projectSecurityPolicies from 'test_fixtures/graphql/security_policies/integration/project_security_policies.query.graphql.json';
// The helpers are globals in `*_spec.js` files only, so this one imports them.
import {
  getText,
  registerBootstrappedApp,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import { setFeatureFlags } from 'ee_jest/integration/helpers/setup_utils';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import setWindowLocation from 'helpers/set_window_location_helper';
import initSecurityPoliciesList from 'ee/security_orchestration/security_policies_list';
import initPolicyEditor from 'ee/security_orchestration/policy_editor';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import {
  APPROVAL_POLICY_TYPE,
  SCAN_EXECUTION_POLICY_TYPE,
} from 'ee/security_orchestration/components/constants';

const PROJECT_PATH = 'flightjs/Flight';
const GROUP_PATH = 'flightjs';
// Exported because a save opens its merge request against the assigned policy project.
export const POLICY_PROJECT_PATH = 'flightjs/security-policy-project';
export const POLICY_PROJECT_BRANCH = 'main';

export const NAMESPACE_PATHS = {
  [NAMESPACE_TYPES.PROJECT]: PROJECT_PATH,
  [NAMESPACE_TYPES.GROUP]: GROUP_PATH,
};

// Hand-copied from the two views below, whose `data:` hashes differ; only `namespace_path`,
// `root_namespace_path` and `designated_as_csp` are covered by the view specs.
const SHARED_DATASET = {
  accessTokens: '[]',
  // Mirrors `assigned_policy_project` in ee/app/helpers/ee/security_orchestration_helper.rb.
  assignedPolicyProject: JSON.stringify({
    id: 'gid://gitlab/Project/2',
    name: 'Security policy project',
    full_path: POLICY_PROJECT_PATH,
    branch: POLICY_PROJECT_BRANCH,
    policy_yaml_has_syntax_errors: 'false',
    policy_yaml_missing: 'false',
    policy_yaml_path: `/${POLICY_PROJECT_PATH}/-/blob/${POLICY_PROJECT_BRANCH}/.gitlab/security-policies/policy.yml`,
  }),
  disableSecurityPolicyProject: 'false',
  disableScanPolicyUpdate: 'false',
  documentationPath: '/help/user/application_security/policies/_index.md',
  emptyFilterSvgPath: '/assets/illustrations/empty-state/empty-search-md.svg',
  emptyListSvgPath: '/assets/illustrations/empty-state/empty-secure-add-md.svg',
  maxScanExecutionPolicyActions: '10',
  maxScanExecutionPolicySchedules: '5',
};

// ee/app/views/projects/security/policies/index.html.haml
const PROJECT_DATASET = {
  ...SHARED_DATASET,
  namespacePath: PROJECT_PATH,
  newPolicyPath: `/${PROJECT_PATH}/-/security/policies/new`,
};

// ee/app/views/groups/security/policies/index.html.haml
const GROUP_DATASET = {
  ...SHARED_DATASET,
  designatedAsCsp: 'false',
  namespacePath: GROUP_PATH,
  newPolicyPath: `/groups/${GROUP_PATH}/-/security/policies/new`,
  rootNamespacePath: GROUP_PATH,
};

const datasetFor = (namespaceType) =>
  namespaceType === NAMESPACE_TYPES.GROUP ? GROUP_DATASET : PROJECT_DATASET;

const policiesPathFor = (namespaceType) =>
  namespaceType === NAMESPACE_TYPES.GROUP
    ? `/groups/${GROUP_PATH}/-/security/policies`
    : `/${PROJECT_PATH}/-/security/policies`;

export function mountPoliciesList({
  namespaceType = NAMESPACE_TYPES.PROJECT,
  queryString = '',
} = {}) {
  setWindowLocation(`${policiesPathFor(namespaceType)}${queryString}`);

  const el = document.createElement('div');
  Object.assign(el.dataset, datasetFor(namespaceType));
  document.body.appendChild(el);

  return registerBootstrappedApp(initSecurityPoliciesList(el, namespaceType));
}

// The editor receives the existing policy as parsed YAML, the shape `FetchPolicyService`
// hands the view, so derive it from the generated fixture rather than a hand-written mock.
const policyFromFixture = (name) => {
  const node = projectSecurityPolicies.data.namespace.securityPolicies.nodes.find(
    (policy) => policy.name === name,
  );

  if (!node) {
    throw new Error(
      `No policy named "${name}" in the project_security_policies fixture. Regenerate it from ee/spec/frontend/fixtures/security_policies_integration.rb, whose policy names this helper depends on.`,
    );
  }

  return load(node.yaml);
};

// The generator's own `edited_policy_name`, which the update_policy fixture replaces.
export const EXISTING_SCAN_EXECUTION_POLICY = policyFromFixture('Run DAST in every pipeline');
export const EXISTING_APPROVAL_POLICY = policyFromFixture('critical vulnerability CS approvals');

// Keyed by type so a caller cannot pair a policy type with a policy body of another type.
const POLICIES_BY_TYPE = {
  [SCAN_EXECUTION_POLICY_TYPE]: EXISTING_SCAN_EXECUTION_POLICY,
  [APPROVAL_POLICY_TYPE]: EXISTING_APPROVAL_POLICY,
};

// `policy` is optional, so a type with no generated policy would silently mount create mode.
const UNSET_POLICY = Symbol('policy');

const existingPolicyFor = (policyType) => {
  const policy = POLICIES_BY_TYPE[policyType];

  if (!policy) {
    throw new Error(
      `No existing policy for the "${policyType}" type. Pass \`policy\` with the one to edit, or \`policy: null\` to mount the create page.`,
    );
  }

  return policy;
};

// Hand-copy of the `orchestration_policy_data` both edit views build. When a new key makes
// ee/spec/helpers/ee/security_orchestration_helper_spec.rb fail, add it here too.
const EDITOR_DATASET = {
  accessTokens: '[]',
  assignedPolicyProject: SHARED_DATASET.assignedPolicyProject,
  designatedAsCsp: 'false',
  disableScanPolicyUpdate: 'false',
  enabledExperiments: '[]',
  globalGroupApproversEnabled: 'true',
  maxActivePipelineExecutionPoliciesReached: 'false',
  maxActiveScanExecutionPoliciesReached: 'false',
  maxActiveScanResultPoliciesReached: 'false',
  maxActiveVulnerabilityManagementPoliciesReached: 'false',
  maxPipelineExecutionPoliciesAllowed: '5',
  maxScanExecutionPoliciesAllowed: '5',
  maxScanExecutionPolicyActions: '10',
  maxScanExecutionPolicySchedules: '5',
  maxScanResultPoliciesAllowed: '5',
  maxVulnerabilityManagementPoliciesAllowed: '5',
  // `false` selects the single-pane layout, so the async Monaco-backed YAML editor mounts
  // only if a spec switches to `.yaml mode`. `true` renders it on load in the split view.
  policyEditorEnabled: 'false',
  policyEditorEmptyStateSvgPath: '/assets/illustrations/monitoring/unable_to_connect.svg',
  roleApproverTypes: '["developer","maintainer","owner"]',
  rootNamespacePath: GROUP_PATH,
  scanPolicyDocumentationPath: '/help/user/application_security/policies/_index.md',
  softwareLicenses: '[]',
  timezones: '[]',
};

// Only these three keys differ between the group and project edit views.
const EDITOR_NAMESPACE_DATASETS = {
  [NAMESPACE_TYPES.PROJECT]: {
    namespaceId: '1',
    namespacePath: PROJECT_PATH,
    policiesPath: `/${PROJECT_PATH}/-/security/policies`,
  },
  [NAMESPACE_TYPES.GROUP]: {
    namespaceId: '2',
    namespacePath: GROUP_PATH,
    policiesPath: `/groups/${GROUP_PATH}/-/security/policies`,
  },
};

/**
 * Mounts the policy editor. `editor_wrapper.vue` derives `isEditing` from the existing
 * policy, so `policy` decides the mode.
 *
 * @param {Object} [options]
 * @param {?Object} [options.policy] - The existing policy, or `null` for create mode, which
 *   leaves `data-policy` off entirely: `policy_editor.js` reads any present attribute,
 *   `"null"` included. Omitted, it edits the generated policy of `policyType`.
 * @param {string} [options.policyType] - Policy type url parameter.
 * @param {string} [options.namespaceType] - Project or group.
 * @param {Object} [options.dataset] - Overrides merged over the dataset last.
 */
export function mountPolicyEditor({
  namespaceType = NAMESPACE_TYPES.PROJECT,
  policyType = SCAN_EXECUTION_POLICY_TYPE,
  policy: requestedPolicy = UNSET_POLICY,
  dataset = {},
} = {}) {
  const policy = requestedPolicy === UNSET_POLICY ? existingPolicyFor(policyType) : requestedPolicy;

  // The edit controller pushes this beta flag, which defaults to enabled.
  setFeatureFlags({
    scheduledPipelineExecutionPolicies: true,
  });

  const policiesPath = policiesPathFor(namespaceType);

  // `app.vue` reads the query param; the dataset stamps `existingPolicy.type`. Both needed.
  setWindowLocation(
    policy
      ? `${policiesPath}/${encodeURIComponent(policy.name)}/edit?type=${policyType}`
      : `${policiesPath}/new?type=${policyType}`,
  );

  const el = document.createElement('div');
  Object.assign(el.dataset, EDITOR_DATASET, EDITOR_NAMESPACE_DATASETS[namespaceType], {
    policyType,
    ...(policy ? { policy: JSON.stringify(policy) } : {}),
    ...dataset,
  });
  document.body.appendChild(el);

  return registerBootstrappedApp(initPolicyEditor(el, namespaceType));
}

/**
 * Asserts a rejected save stopped there. `createMergeRequest` has a domain-wide handler, so
 * a stray second request would be answered rather than surfacing as an unhandled operation.
 * Call it only once the failure is on screen, or it holds for any editor at all.
 */
export const expectNoMergeRequestOpened = () =>
  expect(snapshotRequests().createMergeRequest).toBeUndefined();

// GlTable renders its empty state inside a `b-table-empty-row`, which is not a policy.
export const findPolicyRows = () => [
  ...document.querySelectorAll('[data-testid="policies-list"] tbody tr:not(.b-table-empty-row)'),
];

const findPolicyNames = () =>
  findPolicyRows().map((row) => getText(row.querySelector('[data-testid="policy-name-cell"]')));

export const findEmptyListState = () => document.querySelector('[data-testid="empty-list-state"]');

export const findEmptyFilterState = () =>
  document.querySelector('[data-testid="empty-filter-state"]');

export const findAlert = () => document.querySelector('[data-testid="alert-danger"]');

export const expectListToShow = (names) =>
  waitForAssertion(() => {
    expect(findPolicyNames()).toEqual(names);
  });
