export const suggestedLabelColors = {
  '#000000': 'Black',
  '#0033CC': 'UA blue',
  '#428BCA': 'Moderate blue',
  '#44AD8E': 'Lime green',
};

export const mockPageInfo = () => ({
  hasNextPage: true,
  hasPreviousPage: false,
  startCursor: 'start-cursor',
  endCursor: 'end-cursor',
  __typename: 'PageInfo',
});

export const validFetchResponse = {
  data: {
    namespace: {
      id: 'gid://gitlab/Group/1',
      name: 'Group 1',
      complianceFrameworks: {
        pageInfo: mockPageInfo(),
        nodes: [
          {
            id: 'gid://gitlab/ComplianceManagement::Framework/1',
            name: 'GDPR',
            default: true,
            description: 'General Data Protection Regulation',
            pipelineConfigurationFullPath: 'file.yml@group/project',
            color: '#1aaa55',
            namespaceId: 'gid://gitlab/Group/1',
            projects: {
              nodes: [],
            },
            __typename: 'ComplianceFramework',
          },
          {
            id: 'gid://gitlab/ComplianceManagement::Framework/2',
            name: 'PCI-DSS',
            default: false,
            description: 'Payment Card Industry-Data Security Standard',
            pipelineConfigurationFullPath: 'file.yml@group/project',
            color: '#6666c4',
            namespaceId: 'gid://gitlab/Group/1',
            projects: {
              nodes: [],
            },
            __typename: 'ComplianceFramework',
          },
        ],
        __typename: 'ComplianceFrameworkConnection',
      },
      __typename: 'Namespace',
    },
  },
};

export const frameworkFoundResponse = {
  id: 'gid://gitlab/ComplianceManagement::Framework/1',
  name: 'GDPR',
  default: false,
  description: 'General Data Protection Regulation',
  pipelineConfigurationFullPath: 'file.yml@group/project',
  color: '#1aaa55',
};

export const validCreateResponse = {
  data: {
    createComplianceFramework: {
      framework: {
        id: 'gid://gitlab/ComplianceManagement::Framework/1',
        name: 'GDPR',
        default: true,
        description: 'General Data Protection Regulation',
        pipelineConfigurationFullPath: 'file.yml@group/project',
        color: '#1aaa55',
        namespaceId: 'gid://gitlab/Group/1',
        __typename: 'ComplianceFramework',
      },
      errors: [],
      __typename: 'CreateComplianceFrameworkPayload',
    },
  },
};

export const errorCreateResponse = {
  data: {
    createComplianceFramework: {
      framework: null,
      errors: ['Invalid values given'],
      __typename: 'CreateComplianceFrameworkPayload',
    },
  },
};
