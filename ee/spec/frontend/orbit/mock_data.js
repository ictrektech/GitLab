const mockBasicSchema = {
  schema_version: 'v4.1',
  domains: [
    { name: 'ci', description: 'CI/CD domain', node_names: ['Job', 'Pipeline', 'Stage'] },
    { name: 'core', description: 'Core domain', node_names: ['User', 'Project'] },
  ],
  nodes: [
    { name: 'Job', domain: 'ci', description: 'A CI/CD job' },
    { name: 'Pipeline', domain: 'ci', description: 'A CI/CD pipeline' },
    { name: 'Stage', domain: 'ci', description: 'A pipeline stage' },
    { name: 'User', domain: 'core', description: 'A GitLab user' },
    { name: 'Project', domain: 'core', description: 'A GitLab project' },
  ],
  edges: [
    {
      name: 'AUTHORED',
      description: 'Authorship relationship',
      variants: [
        { source_type: 'User', target_type: 'Pipeline' },
        { source_type: 'User', target_type: 'Job' },
      ],
    },
    {
      name: 'CONTAINS',
      description: 'Containment relationship',
      variants: [{ source_type: 'Pipeline', target_type: 'Stage' }],
    },
  ],
};

export const mockExpandedSchema = {
  ...mockBasicSchema,
  nodes: [
    {
      name: 'Job',
      domain: 'ci',
      description: 'A CI/CD job',
      primary_key: 'id',
      label_field: 'name',
      properties: [
        { name: 'id', data_type: 'int64', nullable: false },
        { name: 'name', data_type: 'string', nullable: true },
        { name: 'status', data_type: 'string', nullable: false },
      ],
      style: { color: '#f59e0b', size: 30 },
    },
    {
      name: 'Pipeline',
      domain: 'ci',
      description: 'A CI/CD pipeline',
      primary_key: 'id',
      properties: [
        { name: 'id', data_type: 'int64', nullable: false },
        { name: 'ref', data_type: 'string', nullable: true },
      ],
      style: { color: '#f59e0b', size: 35 },
    },
    {
      name: 'Stage',
      domain: 'ci',
      description: 'A pipeline stage',
      properties: [],
      style: { color: '#fbbf24', size: 25 },
    },
    {
      name: 'User',
      domain: 'core',
      description: 'A GitLab user',
      properties: [
        { name: 'id', data_type: 'int64', nullable: false },
        { name: 'username', data_type: 'string', nullable: false },
      ],
      style: { color: '#ec4899', size: 30 },
    },
    {
      name: 'Project',
      domain: 'core',
      description: 'A GitLab project',
      properties: [{ name: 'id', data_type: 'int64', nullable: false }],
      style: { color: '#06b6d4', size: 30 },
    },
  ],
};

export const mockScopedSchema = {
  nodes: [
    {
      name: 'User',
      domain: 'core',
      description: 'A GitLab user account.',
      primary_key: 'id',
      label_field: 'username',
      properties: [
        { name: 'id', data_type: 'Int', nullable: false },
        { name: 'username', data_type: 'String', nullable: false },
      ],
      style: { color: '#10B981' },
    },
    {
      name: 'Project',
      domain: 'core',
      description: 'A GitLab project.',
      primary_key: 'id',
      label_field: 'name',
      properties: [
        { name: 'id', data_type: 'Int', nullable: false },
        { name: 'name', data_type: 'String', nullable: false },
      ],
      style: { color: '#3B82F6' },
    },
    {
      name: 'Pipeline',
      domain: 'ci',
      description: 'A CI/CD pipeline.',
      primary_key: 'id',
      label_field: 'id',
      properties: [
        { name: 'id', data_type: 'Int', nullable: false },
        {
          name: 'status',
          data_type: 'Enum',
          nullable: false,
          enum_values: ['created', 'running', 'success'],
        },
        { name: 'ref', data_type: 'String', nullable: true },
      ],
      style: { color: '#6366F1' },
    },
    {
      name: 'Job',
      domain: 'ci',
      description: 'A CI/CD job.',
      primary_key: 'id',
      label_field: 'name',
      properties: [{ name: 'name', data_type: 'String', nullable: false }],
      style: { color: '#8B5CF6' },
    },
    {
      name: 'Package',
      domain: 'packages',
      description: 'A package.',
      primary_key: 'id',
      label_field: 'id',
      properties: [{ name: 'id', data_type: 'Int', nullable: false }],
      style: { color: '#FB923C' },
    },
  ],
  edges: [
    {
      name: 'IN_PROJECT',
      description: 'Project association for entities',
      variants: [
        { source_type: 'Pipeline', target_type: 'Project' },
        { source_type: 'Job', target_type: 'Project' },
        { source_type: 'Package', target_type: 'Project' },
      ],
    },
    {
      name: 'TRIGGERED',
      description: 'User who triggered a pipeline',
      variants: [{ source_type: 'User', target_type: 'Pipeline' }],
    },
    {
      name: 'HAS_JOB',
      description: 'Pipeline contains a job',
      variants: [{ source_type: 'Pipeline', target_type: 'Job' }],
    },
    {
      name: 'AUTO_CANCELED_BY',
      description: 'Canceled by a newer pipeline',
      variants: [
        { source_type: 'Pipeline', target_type: 'Pipeline' },
        { source_type: 'Job', target_type: 'Pipeline' },
      ],
    },
  ],
};

export const orbitPlatform = ({ saas = true, instance = null } = {}) => ({ saas, instance });

export const buildOrbitGroup = ({
  id = 1,
  name = 'gl-demo',
  enabled = true,
  state = 'READY',
  areas = [],
  projects = null,
  enabledAt = null,
} = {}) => ({
  __typename: 'Group',
  id: `gid://gitlab/Group/${id}`,
  name,
  fullName: name,
  fullPath: name,
  avatarUrl: null,
  maxAccessLevel: { integerValue: 50 },
  userPermissions: { startOrbitTrial: false, updateKnowledgeGraphSetting: true },
  orbit: {
    __typename: 'OrbitNamespace',
    enabled,
    enabledAt,
    indexing: { state, areas, projects },
  },
});

const SDLC_AREAS = ['core', 'plan', 'code_review', 'ci', 'security'];

export const buildGroupWithPendingProjects = ({ id = 1, name = 'gl-demo', pending = 2 } = {}) =>
  buildOrbitGroup({
    id,
    name,
    state: 'INDEXING',
    areas: [
      ...SDLC_AREAS.map((area) => ({ name: area, state: 'READY' })),
      { name: 'source_code', state: 'INDEXING' },
    ],
    projects: { indexed: 100 - pending, totalKnown: 100, gaps: 0 },
  });

export const mockQueryResponse = {
  data: {
    result: {
      nodes: [
        { type: 'User', id: 1, username: 'admin', name: 'Administrator' },
        { type: 'User', id: 2, username: 'dev', name: 'Developer' },
      ],
      edges: [],
      columns: [],
      row_count: 2,
    },
  },
};

export const mockNeighborResponse = {
  data: {
    result: {
      nodes: [
        { type: 'Project', id: 10, name: 'ProjectA' },
        { type: 'Project', id: 11, name: 'ProjectB' },
      ],
      edges: [
        { from: 'Group', from_id: 1, to: 'Project', to_id: 10, type: 'CONTAINS' },
        { from: 'Group', from_id: 1, to: 'Project', to_id: 11, type: 'CONTAINS' },
      ],
      columns: [],
    },
  },
};

export const buildItemCountGroup = ({ id = 1, domains = {} } = {}) => ({
  __typename: 'Group',
  id: `gid://gitlab/Group/${id}`,
  orbit: {
    __typename: 'OrbitNamespace',
    itemCounts: {
      domains: Object.entries(domains).map(([name, entities]) => ({
        name,
        entities: Object.entries(entities).map(([entity, count]) => ({
          name: entity,
          count: String(count),
        })),
      })),
    },
  },
});

export const memberGroupsResponse = (nodes) => ({
  data: { orbit: { __typename: 'Orbit', memberGroups: { nodes } } },
});
