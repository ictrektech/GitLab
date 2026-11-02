// Everything the wizard emits on save, as StepWizard builds it.
export const mockWizardState = {
  name: 'Prod gate',
  description: 'Gates production deployments',
  mode: 'enforce',
  scope: { mode: 'all', projects: [], exclusions: [] },
  scopeChanged: true,
  policyData: {
    trigger: 'deployment_requested',
    triggerConfig: {},
    rules: ['custom'],
    ruleConfigs: { custom: { policy: 'package governance' } },
    actions: [],
    actionConfigs: {},
  },
};

// The request params serializePolicyParams builds from mockWizardState.
export const mockPolicyParams = {
  name: 'Prod gate',
  description: 'Gates production deployments',
  mode: 'enforce',
  policy_scope: {},
  trigger_type: 'deployment_requested',
  rules: [{ type: 'custom', value: 'package governance' }],
  actions: [],
};

// The group a policy belongs to, as the GovernPolicy `group` field returns it.
export const mockPolicyGroup = {
  __typename: 'Group',
  id: 'gid://gitlab/Group/11',
  name: 'Flight',
  fullPath: 'flightjs',
};

// A policy as the policies query returns it: the whole GovernPolicy selection
// set, with __typename and id so Apollo normalizes it. The one builder every
// policy store spec derives its policies from, so the selection set lives here.
export const mockGraphqlPolicy = (overrides = {}) => ({
  __typename: 'GovernPolicy',
  id: 7,
  organizationId: 1,
  namespaceId: null,
  inherited: false,
  group: null,
  name: 'Production gate',
  description: 'Gates production deployments',
  version: 3,
  triggerType: 'deployment_requested',
  rules: [{ type: 'custom', value: 'package governance' }],
  policyRego: null,
  actions: [{ type: 'block' }],
  policyScope: { projects: { including: [1, 2, 3] } },
  scopeRego: null,
  scopeDimensions: null,
  mode: 'enforce',
  lifecycleState: 'active',
  createdAt: '2026-08-19T23:41:12.686Z',
  updatedAt: '2026-08-20T09:12:44.120Z',
  ...overrides,
});

export const mockRemoteTriggers = [
  { __typename: 'PolicyStoreTrigger', id: 'deployment_requested', name: 'Deployment requested' },
];

// mockGraphqlPolicy() as toPolicy maps it for the detail and editor pages:
// snake_case fields plus the derived type, status and scopedProjectsCount.
// Shallow-frozen: blocks top-level reassignment only; nested rules and actions stay mutable.
export const mockMappedPolicy = Object.freeze({
  id: 7,
  organization_id: 1,
  namespace_id: null,
  inherited: false,
  group: null,
  name: 'Production gate',
  description: 'Gates production deployments',
  version: 3,
  trigger_type: 'deployment_requested',
  rules: [{ type: 'custom', value: 'package governance' }],
  policy_rego: null,
  actions: [{ type: 'block' }],
  policy_scope: { projects: { including: [1, 2, 3] } },
  scope_rego: null,
  scope_dimensions: null,
  mode: 'enforce',
  lifecycle_state: 'active',
  created_at: '2026-08-19T23:41:12.686Z',
  updated_at: '2026-08-20T09:12:44.120Z',
  type: 'Deployment requested',
  status: 'active',
  scopedProjectsCount: 3,
});

// mockGraphqlPolicy() as toListPolicies maps it for the list page, plus the
// detail path the list derives from listPath. The row keeps snake_case
// trigger_type, rules and actions because config_info.vue deserializes them.
export const mockListPolicy = (overrides = {}) => ({
  id: 7,
  name: 'Production gate',
  mode: 'enforce',
  inherited: false,
  group: null,
  source: 'Organization',
  trigger_type: 'deployment_requested',
  rules: [{ type: 'custom', value: 'package governance' }],
  actions: [{ type: 'block' }],
  updated_at: '2026-08-20T09:12:44.120Z',
  type: 'Deployment requested',
  status: 'active',
  scopedProjectsCount: 3,
  detailPath: '',
  ...overrides,
});

// A null connection, not an empty one, is the resolver's permission signal.
export const mockPolicyStore = (policies, triggers, pageInfo = {}) => ({
  __typename: 'PolicyStore',
  policies:
    policies === null
      ? null
      : {
          __typename: 'GovernPolicyConnection',
          nodes: policies,
          pageInfo: { __typename: 'PageInfo', hasNextPage: false, endCursor: null, ...pageInfo },
        },
  triggers,
});

// A null count stands for a null connection, the resolver's permission signal.
const mockEvaluationsCount = (count) =>
  count === null ? null : { __typename: 'GovernPolicyEvaluationConnection', count };

const organizationResponse = (policyStore) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: 'gid://gitlab/Organizations::Organization/1',
      policyStore,
    },
  },
});

const groupResponse = (policyStore) => ({
  data: { group: { __typename: 'Group', id: 'gid://gitlab/Group/42', policyStore } },
});

const projectResponse = (policyStore) => ({
  data: { project: { __typename: 'Project', id: 'gid://gitlab/Project/7', policyStore } },
});

export const mockOrganizationPoliciesResponse = (
  policies = [mockGraphqlPolicy()],
  triggers = mockRemoteTriggers,
  pageInfo = {},
) => organizationResponse(mockPolicyStore(policies, triggers, pageInfo));

export const mockGroupPoliciesResponse = (
  policies = [mockGraphqlPolicy()],
  triggers = mockRemoteTriggers,
  pageInfo = {},
) => groupResponse(mockPolicyStore(policies, triggers, pageInfo));

export const mockProjectPoliciesResponse = (
  policies = [mockGraphqlPolicy()],
  triggers = mockRemoteTriggers,
  pageInfo = {},
) => projectResponse(mockPolicyStore(policies, triggers, pageInfo));

export const mockOrganizationEvaluationsCountResponse = (count = 0) =>
  organizationResponse({
    __typename: 'PolicyStore',
    policyEvaluations: mockEvaluationsCount(count),
  });

export const mockGroupEvaluationsCountResponse = (count = 0) =>
  groupResponse({ __typename: 'PolicyStore', policyEvaluations: mockEvaluationsCount(count) });

export const mockGraphqlEvaluation = (overrides = {}) => ({
  __typename: 'GovernPolicyEvaluation',
  id: 'gid://gitlab/Govern::PolicyEvaluation/11',
  triggerType: 'PROJECT_BEFORE_SETTINGS_UPDATE',
  mode: 'ENFORCE',
  verdict: 'DENY',
  evaluatedAt: '2026-10-20T09:00:00Z',
  projectId: 4821,
  project: {
    __typename: 'Project',
    id: 'gid://gitlab/Project/4821',
    nameWithNamespace: 'Flight / Dashboard',
    webPath: '/flightjs/dashboard',
  },
  violations: [
    {
      __typename: 'GovernPolicyViolation',
      id: 'gid://gitlab/Govern::PolicyViolation/3',
      details: { setting: 'visibility', expected: 'private', actual: 'public' },
    },
  ],
  ...overrides,
});

// A null connection, not an empty one, is the resolver's permission signal.
const mockEvaluations = (evaluations) =>
  evaluations === null
    ? null
    : { __typename: 'GovernPolicyEvaluationConnection', nodes: evaluations };

export const mockOrganizationEvaluationsResponse = (evaluations = [mockGraphqlEvaluation()]) =>
  organizationResponse({
    __typename: 'PolicyStore',
    policyEvaluations: mockEvaluations(evaluations),
  });

export const mockGroupEvaluationsResponse = (evaluations = [mockGraphqlEvaluation()]) =>
  groupResponse({ __typename: 'PolicyStore', policyEvaluations: mockEvaluations(evaluations) });

// The resolver nulls the whole field when the experiment is off.
export const mockOrganizationInactiveStoreResponse = () => organizationResponse(null);
export const mockGroupInactiveStoreResponse = () => groupResponse(null);
export const mockProjectInactiveStoreResponse = () => projectResponse(null);
