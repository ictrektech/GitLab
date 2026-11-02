import { TYPENAME_AI_FLOW_TRIGGER } from 'ee/graphql_shared/constants';

export const mockFlowTriggerFactory = (overrides = {}) => ({
  id: `gid://gitlab/${TYPENAME_AI_FLOW_TRIGGER}/1`,
  active: true,
  description: 'Test trigger',
  eventTypes: [0, 1],
  filter: {},
  goals: {},
  statusOnFinish: null,
  readyMergeRequestsOnFinish: false,
  configPath: '/config/test.yml',
  configUrl: 'https://example.com/config/test.yml',
  aiCatalogItemConsumer: {
    id: 'gid://gitlab/Ai::Catalog::ItemConsumer/1',
    item: {
      id: 'gid://gitlab/Ai::Catalog::Item/10',
      name: 'Test Flow',
      __typename: 'AiCatalogItem',
    },
    __typename: 'AiCatalogItemConsumer',
  },
  user: {
    id: 'gid://gitlab/User/1',
    username: 'testuser',
    name: 'Test User',
    avatarUrl: 'https://example.com/avatar.png',
    webPath: '/testuser',
    webUrl: 'https://example.com/testuser',
    __typename: 'UserCore',
  },
  createdAt: '2025-08-08T13:37:18Z',
  updatedAt: '2025-08-08T13:37:18Z',
  // GraphQL type name (matches FlowTriggerFragment's `on AiFlowTriggerType`), which differs from
  // the global-ID type in TYPENAME_AI_FLOW_TRIGGER. It must match so Apollo's normalized cache
  // preserves the fragment's fields on read-back (e.g. under CACHE_AND_NETWORK).
  __typename: 'AiFlowTriggerType',
  ...overrides,
});

export const mockTrigger = mockFlowTriggerFactory();

export const mockTriggers = [mockTrigger];

export const mockAiFlowTriggersResponse = {
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: {
        nodes: mockTriggers,
        __typename: 'AiFlowTriggerConnection',
      },
      __typename: 'Project',
    },
  },
};

export const mockUpdateTriggerActiveResponse = {
  data: {
    aiFlowTriggerUpdate: {
      aiFlowTrigger: {
        id: `gid://gitlab/${TYPENAME_AI_FLOW_TRIGGER}/1`,
        active: false,
        eventTypes: [0, 1],
        filter: {},
        goals: {},
        statusOnFinish: null,
        readyMergeRequestsOnFinish: false,
        __typename: TYPENAME_AI_FLOW_TRIGGER,
      },
      errors: [],
    },
  },
};

export const mockUpdateTriggerActiveErrorResponse = {
  data: {
    aiFlowTriggerUpdate: {
      aiFlowTrigger: null,
      errors: ['Trigger could not be updated'],
    },
  },
};

export const mockDeleteTriggerResponse = {
  data: {
    aiFlowTriggerDelete: {
      errors: [],
    },
  },
};

export const mockEmptyAiFlowTriggersResponse = {
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: {
        nodes: [],
        __typename: 'AiFlowTriggerConnection',
      },
      __typename: 'Project',
    },
  },
};

export const mockNullProjectAiFlowTriggersResponse = {
  data: {
    project: null,
  },
};

export const mockCreateFlowTriggerSuccessMutation = {
  data: {
    aiFlowTriggerCreate: {
      aiFlowTrigger: mockTrigger,
      errors: [],
    },
  },
};

export const mockCreateFlowTriggerErrorMutation = {
  data: {
    aiFlowTriggerCreate: {
      aiFlowTrigger: null,
      errors: ['No input was provided.'],
    },
  },
};

export const mockUpdateFlowTriggerSuccessMutation = {
  data: {
    aiFlowTriggerUpdate: {
      aiFlowTrigger: {
        id: `gid://gitlab/${TYPENAME_AI_FLOW_TRIGGER}/1`,
        active: true,
        eventTypes: [0, 1],
        filter: {},
        goals: {},
        statusOnFinish: null,
        readyMergeRequestsOnFinish: false,
        __typename: TYPENAME_AI_FLOW_TRIGGER,
      },
      errors: [],
    },
  },
};

export const mockUpdateFlowTriggerErrorMutation = {
  data: {
    aiFlowTriggerUpdate: {
      aiFlowTrigger: null,
      errors: ['No input was provided.'],
    },
  },
};

export const mockCatalogItemConsumerFactory = ({
  id = 1,
  itemId = 10,
  name = 'Test Flow',
  itemType = 'FLOW',
  foundationalFlowReference = null,
  serviceAccountId = 501,
  acceptsTriggerGoal = true,
} = {}) => ({
  id: `gid://gitlab/Ai::Catalog::ItemConsumer/${id}`,
  item: {
    id: `gid://gitlab/Ai::Catalog::Item/${itemId}`,
    name,
    itemType,
    foundationalFlowReference,
    acceptsTriggerGoal,
    __typename: itemType === 'THIRD_PARTY_FLOW' ? 'AiCatalogThirdPartyFlow' : 'AiCatalogFlow',
  },
  // The service account lives on the parent group consumer, not the project consumer.
  parentItemConsumer: {
    id: `gid://gitlab/Ai::Catalog::ItemConsumer/${900 + id}`,
    serviceAccount: {
      id: `gid://gitlab/User/${serviceAccountId}`,
    },
  },
});

export const mockCatalogFlowsResponseFactory = (nodes = []) => ({
  data: {
    aiCatalogConfiguredItems: {
      nodes,
    },
  },
});

export const mockCatalogFlowsResponse = mockCatalogFlowsResponseFactory([
  mockCatalogItemConsumerFactory(),
  mockCatalogItemConsumerFactory({
    id: 2,
    itemId: 100,
    name: 'Another Flow',
    serviceAccountId: 502,
  }),
]);

// User/501 (Test Flow's SA) is Developer. User/502 (Another Flow's SA) is
// Maintainer, proving a non-Developer role still resolves.
export const mockServiceAccountRolesResponse = {
  data: {
    project: {
      id: 'gid://gitlab/Project/123',
      projectMembers: {
        nodes: [
          {
            id: 'gid://gitlab/ProjectMember/9001',
            accessLevel: { humanAccess: 'Developer' },
            user: { id: 'gid://gitlab/User/501' },
          },
          {
            id: 'gid://gitlab/ProjectMember/9002',
            accessLevel: { humanAccess: 'Maintainer' },
            user: { id: 'gid://gitlab/User/502' },
          },
        ],
      },
    },
  },
};

export const mockAutomationSessionFactory = (overrides = {}) => ({
  id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/101',
  status: 'FINISHED',
  createdAt: '2026-10-13T10:00:00Z',
  updatedAt: '2026-10-13T10:01:30Z',
  __typename: 'DuoWorkflow',
  ...overrides,
});

export const mockAutomationRecentRunsResponse = (
  sessions = [mockAutomationSessionFactory()],
  pageInfo = {},
) => ({
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: {
        nodes: [
          {
            id: 'gid://gitlab/Ai::FlowTrigger/1',
            sessions: {
              nodes: sessions,
              pageInfo: {
                hasNextPage: false,
                hasPreviousPage: false,
                startCursor: 'start',
                endCursor: 'end',
                __typename: 'PageInfo',
                ...pageInfo,
              },
              __typename: 'DuoWorkflowConnection',
            },
            __typename: 'AiFlowTriggerType',
          },
        ],
        __typename: 'AiFlowTriggerConnection',
      },
      __typename: 'Project',
    },
  },
});

export const mockLastRunFactory = (overrides = {}) => ({
  status: 'SUCCEEDED',
  startedAt: '2026-10-13T10:00:00Z',
  finishedAt: '2026-10-13T10:01:30Z',
  error: null,
  __typename: 'AiFlowTriggerLastRun',
  ...overrides,
});

export const mockAutomationFactory = (overrides = {}) =>
  mockFlowTriggerFactory({ runningCount: 0, lastRun: null, ...overrides });

export const mockAutomationRunStatsResponse = (runStats = {}) => ({
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: {
        nodes: [
          {
            id: 'gid://gitlab/Ai::FlowTrigger/1',
            runStats: {
              totalRuns: 1234,
              finishedRuns: 3,
              failedRuns: 1,
              medianDurationSeconds: 90,
              dailyVolume: [
                { date: '2026-10-13', runs: 4, __typename: 'AiFlowTriggerDailyRunCount' },
              ],
              __typename: 'AiFlowTriggerRunStats',
              ...runStats,
            },
            __typename: 'AiFlowTriggerType',
          },
        ],
        __typename: 'AiFlowTriggerConnection',
      },
      __typename: 'Project',
    },
  },
});

export const mockAiFlowTriggerRunStatsResponse = (runStats = {}) => ({
  data: {
    project: {
      id: 'gid://gitlab/Project/1000000',
      aiFlowTriggers: {
        runStats: {
          totalRuns: 1234,
          finishedRuns: 3,
          failedRuns: 1,
          dailyVolume: [{ date: '2026-10-13', runs: 4, __typename: 'AiFlowTriggerDailyRunCount' }],
          __typename: 'AiFlowTriggerRunStats',
          ...runStats,
        },
        __typename: 'AiFlowTriggerConnection',
      },
      __typename: 'Project',
    },
  },
});
