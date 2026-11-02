import { ENABLED_AT } from '../../shared/groups/mock_data';

export const buildOrbit = (state, { enabled = true } = {}) => ({
  __typename: 'OrbitNamespace',
  enabled,
  enabledAt: ENABLED_AT,
  indexing: state ? { __typename: 'OrbitIndexing', state, areas: [] } : null,
});

export const buildGroup = ({ name = 'acme', ...overrides } = {}) => ({
  __typename: 'Group',
  id: `gid://gitlab/Group/${name}`,
  name,
  fullPath: name,
  webPath: `/${name}`,
  avatarUrl: null,
  orbit: {
    __typename: 'OrbitNamespace',
    enabled: false,
    enabledAt: null,
    indexing: null,
  },
  ...overrides,
});

export const buildOnGroup = (name, state = 'READY') =>
  buildGroup({ name, orbit: buildOrbit(state) });

export const groupsResponse = (nodes, pageInfo = {}) => ({
  data: {
    orbit: {
      __typename: 'Orbit',
      groups: {
        __typename: 'GroupConnection',
        nodes,
        pageInfo: {
          __typename: 'PageInfo',
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: null,
          endCursor: null,
          ...pageInfo,
        },
      },
    },
  },
});

export const excludedGroupsResponse = (nodes, pageInfo = {}) => ({
  data: {
    orbit: {
      __typename: 'Orbit',
      excludedGroups: {
        __typename: 'GroupConnection',
        nodes,
        pageInfo: { __typename: 'PageInfo', hasNextPage: false, endCursor: null, ...pageInfo },
      },
    },
  },
});

export const orbitUpdateResponse = (errors = []) => ({
  data: { orbitUpdate: { __typename: 'OrbitUpdatePayload', group: null, errors } },
});

export const excludeResponse = (errors = []) => ({
  data: {
    orbitExcludedGroupCreate: {
      __typename: 'OrbitExcludedGroupCreatePayload',
      group: null,
      errors,
    },
  },
});

export const includeResponse = (errors = []) => ({
  data: {
    orbitExcludedGroupDestroy: {
      __typename: 'OrbitExcludedGroupDestroyPayload',
      group: null,
      errors,
    },
  },
});

export const serviceStatusResponse = {
  data: {
    orbit: {
      __typename: 'Orbit',
      serviceStatus: {
        __typename: 'OrbitServiceStatus',
        state: 'HEALTHY',
        version: '0.128.0',
        components: [{ __typename: 'OrbitServiceComponent', name: 'clickhouse', state: 'HEALTHY' }],
      },
    },
  },
};

export const instanceAccess = (state, reason = null, trial = {}) => ({
  __typename: 'OrbitAccess',
  state,
  reason,
  trial: {
    __typename: 'OrbitTrial',
    expiresOn: null,
    offer: { __typename: 'OrbitTrialOffer', durationDays: 30, initialCredits: 1000 },
    ...trial,
  },
});

export const instanceAccessResponse = (access) => ({
  data: { orbit: { __typename: 'Orbit', access } },
});

export const instanceStartTrialResponse = (errors = []) => ({
  data: {
    orbitInstanceStartTrial: { __typename: 'OrbitInstanceStartTrialPayload', errors },
  },
});
