import Vue, { nextTick } from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import VueApollo from 'vue-apollo';
import { parseDocument } from 'yaml';
import { GlAlert } from '@gitlab/ui';
import { getInstanceSlots, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import {
  getSessionStorageValue,
  saveSessionStorageValue,
  removeSessionStorageValue,
} from '~/lib/utils/local_storage';
import { WorkflowStream } from 'ee/ai/duo_agentic_chat/websocket/workflow_stream';
import { RetryableWorkflowStream } from 'ee/ai/duo_agentic_chat/websocket/retryable_workflow_stream';
import {
  WS_CLOSE_INVALID_REQUEST,
  WS_CLOSE_NORMAL,
  WS_CLOSE_PERMISSION_DENIED,
  WS_CLOSE_TRY_AGAIN_LATER,
} from 'ee/ai/duo_agentic_chat/constants';
import {
  DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
  DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
} from 'ee/ai/constants';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import ConnectionErrorAlert from 'ee/ai/duo_agentic_chat/components/connection_error_alert.vue';
import waitForPromises from 'helpers/wait_for_promises';
import { createUserPrompt } from 'ee/ai/duo_agentic_chat/services/user_prompt';
import { runMessageTransformers } from 'ee/ai/duo_agentic_chat/transformers/index';
import storeMutations from 'ee/ai/tanuki_bot/store/mutations';
import * as storeActions from 'ee/ai/tanuki_bot/store/actions';
import getUserWorkflows from 'ee/ai/graphql/get_user_workflow.query.graphql';
import getAiChatContextPresets from 'ee/ai/graphql/get_ai_chat_context_presets.query.graphql';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import getConfiguredAgents from 'ee/ai/graphql/get_configured_agents.query.graphql';
import getAgentFlowConfig from 'ee/ai/graphql/get_agent_flow_config.query.graphql';
import getFoundationalChatAgents from 'ee/ai/graphql/get_foundational_chat_agents.graphql';
import getFlowStatus from 'ee/ai/graphql/get_flow_status.query.graphql';
import duoWorkflowMutation from 'ee/ai/graphql/duo_workflow.mutation.graphql';
import deleteAgenticWorkflowMutation from 'ee/ai/graphql/delete_agentic_workflow.mutation.graphql';
import updateWebSearchMutation from 'ee/ai/graphql/update_duo_workflow_web_search.mutation.graphql';
import getWorkflowLatestCheckpointQuery from 'ee/ai/graphql/get_workflow_latest_checkpoint.query.graphql';
import getWorkflowBranchesQuery from 'ee/ai/graphql/get_workflow_branches.query.graphql';
import getGitlabCreditsStatusQuery from 'ee/ai/graphql/get_gitlab_credits_status.query.graphql';
import getOrbitUserPreference from 'ee/ai/graphql/get_orbit_user_preference.query.graphql';
import DuoAgenticChatStateManagerLight from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_state_manager_light.vue';
import DuoAgenticChatView from 'ee/ai/duo_agentic_chat/components/duo_agentic_chat_view.vue';
import PromptInputActions from 'ee/ai/duo_agentic_chat/components/prompt_input_actions.vue';
import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';
import {
  getCurrentModel,
  getDefaultModel,
  getModel,
  saveModel,
  isModelSelectionDisabled as checkModelSelectionDisabled,
} from 'ee/ai/duo_agentic_chat/utils/model_selection_utils';
import * as WorkflowSocketUtils from 'ee/ai/duo_agentic_chat/websocket/workflow_utils';
import { loadThreadSnapshot } from 'ee/ai/duo_agentic_chat/utils/chat_thread_snapshot';
import { AGENTIC_CHAT_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import {
  MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE,
  MOCK_GITLAB_DEFAULT_MODEL_ITEM,
  MOCK_CONFIGURED_AGENTS_RESPONSE,
  MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE,
  MOCK_FLOW_CONFIG_RESPONSE,
} from './mock_data';

jest.mock('~/behaviors/markdown/render_gfm', () => {
  const actual = jest.requireActual('~/behaviors/markdown/render_gfm');
  return { ...actual, renderGFM: jest.fn() };
});

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

jest.mock('ee/ai/duo_agentic_chat/utils/agent_utils', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat/utils/agent_utils'),
  catalogAgentsFromResponse: jest.fn(
    jest.requireActual('ee/ai/duo_agentic_chat/utils/agent_utils').catalogAgentsFromResponse,
  ),
}));

jest.mock('ee/ai/duo_agentic_chat/websocket/workflow_stream', () => ({
  WorkflowStream: jest.fn(),
}));

jest.mock('ee/ai/duo_agentic_chat/websocket/retryable_workflow_stream', () => ({
  RetryableWorkflowStream: jest.fn(),
}));

const createMockStream = () => ({
  connect: jest.fn(),
  disconnect: jest.fn(),
  send: jest.fn(),
  subscribe: jest.fn().mockImplementation(() => ({ dispose: jest.fn() })),
  getStatus: jest.fn().mockReturnValue({ connected: false, bufferedCount: 0 }),
  terminate: jest.fn(),
  retry: jest.fn().mockReturnValue(true),
});

jest.mock('yaml');

jest.mock('~/lib/utils/websocket_utils', () => ({
  parseMessage: jest.fn(async (event) => {
    const data = typeof event.data === 'string' ? event.data : await event.data.text();
    return JSON.parse(data);
  }),
}));

jest.mock('ee/ai/duo_agentic_chat/utils/workflow_utils', () => ({
  WorkflowUtils: {
    transformChatMessages: jest.fn(),
    parseWorkflowData: jest.fn(),
    normalizeDuoMessages: jest.fn(),
    // Real implementation so thread reloads exercise snapshot reconciliation end to end.
    reconcileLoadedMessages: jest.requireActual('ee/ai/duo_agentic_chat/utils/workflow_utils')
      .WorkflowUtils.reconcileLoadedMessages,
  },
}));

jest.mock('ee/ai/duo_agentic_chat/utils/model_selection_utils', () => ({
  getCurrentModel: jest.fn(),
  getDefaultModel: jest.fn(),
  getModel: jest.fn(),
  saveModel: jest.fn(),
  isModelSelectionDisabled: jest.fn(),
}));

jest.mock('ee/ai/duo_agentic_chat/utils/chat_thread_snapshot', () => ({
  saveThreadSnapshot: jest.fn(),
  loadThreadSnapshot: jest.fn(),
  clearThreadSnapshot: jest.fn(),
}));

// Applies the pipeline for real (mirroring the module it replaces) so the transformers
// the state manager wires in still run, while keeping the call spy for pipeline assertions.
jest.mock('ee/ai/duo_agentic_chat/transformers/index', () => ({
  runMessageTransformers: jest.fn((messages, transformers) =>
    transformers.reduce((msgs, transformer) => transformer(msgs), messages),
  ),
}));

jest.mock('ee/ai/duo_agentic_chat/observability/events_tracker', () => ({
  EventsTracker: {
    updateContext: jest.fn(),
    trackApproveTool: jest.fn(),
    trackDenyTool: jest.fn(),
    trackClickThroughFlowWidget: jest.fn(),
    reset: jest.fn(),
  },
}));

const MOCK_WORKFLOW_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/456';
const MOCK_CONTEXT_PRESETS_RESPONSE = {
  data: {
    aiChatContextPresets: {
      questions: [
        'How can I optimize my CI pipeline?',
        'What are best practices for merge requests?',
        'How do I set up a workflow for my project?',
        'What are the advantages of using GitLab CI/CD?',
      ],
      // This surface does not render the categorized empty state, but the
      // shared query selects the field, so it has to resolve.
      questionCategories: [],
    },
  },
};
const MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE = {
  data: {
    aiDuoWorkflowCreate: {
      workflow: { id: MOCK_WORKFLOW_ID },
      errors: [],
    },
  },
};
const MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE = {
  data: {
    deleteDuoWorkflowsWorkflow: { success: true, clientMutationId: null, errors: [] },
  },
};
const MOCK_UPDATE_WEB_SEARCH_MUTATION_RESPONSE = {
  data: {
    updateDuoWorkflowWebSearch: {
      workflow: { id: MOCK_WORKFLOW_ID },
      errors: [],
    },
  },
};

const MOCK_USER_WORKFLOWS_RESPONSE = {
  data: {
    duoWorkflowWorkflows: {
      pageInfo: { endCursor: null, hasNextPage: false },
      edges: [
        {
          node: {
            id: MOCK_WORKFLOW_ID,
            title: 'Test workflow goal',
            lastUpdatedAt: '2024-01-01T00:00:00Z',
            aiCatalogItemVersionId: null,
            agentName: 'GitLab Duo',
            archived: false,
          },
        },
      ],
    },
  },
};

const MOCK_WORKFLOW_EVENTS_RESPONSE = {
  duoWorkflowWorkflows: {
    nodes: [
      {
        id: 'workflow-1',
        status: 'completed',
        title: null,
        aiCatalogItemVersionId: '',
        workflowDefinition: null,
        archived: false,
        stalled: false,
        webSearchEnabled: false,
        latestCheckpoint: {
          workflowGoal: '',
          workflowStatus: 'completed',
          errors: null,
          duoMessages: [],
        },
      },
    ],
  },
};

const MOCK_TRANSFORMED_MESSAGES = [
  {
    content: 'Hello, how can I help?',
    role: 'assistant',
    requestId: '456-1-agent',
    message_type: 'agent',
  },
];

const MOCK_PARSED_FLOW_CONFIG = { components: [{ name: 'test', type: 'agent' }] };

const MOCK_UTILS_SETUP = () => {
  WorkflowUtils.transformChatMessages.mockReturnValue(MOCK_TRANSFORMED_MESSAGES);
  WorkflowUtils.normalizeDuoMessages.mockReturnValue([]);
  WorkflowUtils.parseWorkflowData.mockReturnValue({
    workflowGoal: '',
    workflowStatus: 'completed',
    errors: null,
    duoMessages: [],
  });
  parseDocument.mockReturnValue(MOCK_PARSED_FLOW_CONFIG);

  getCurrentModel.mockReturnValue(MOCK_GITLAB_DEFAULT_MODEL_ITEM);
  getDefaultModel.mockReturnValue(MOCK_GITLAB_DEFAULT_MODEL_ITEM);
  // getModel needs to search arrays by value, simple Array.find helper
  getModel.mockImplementation((models, value) => models?.find((m) => m.value === value));
  saveModel.mockReturnValue(true);
  checkModelSelectionDisabled.mockReturnValue(false);

  jest
    .spyOn(WorkflowSocketUtils, 'buildWebsocketUrl')
    .mockReturnValue('/api/v4/ai/duo_workflows/ws');
  jest.spyOn(WorkflowSocketUtils, 'buildStartRequest').mockReturnValue({
    startRequest: {
      workflowID: '456',
      clientVersion: '1.0',
      workflowDefinition: 'chat',
      goal: '',
      approval: {},
    },
  });
  jest.spyOn(WorkflowSocketUtils, 'processWorkflowMessage');
};

Vue.use(Vuex);
Vue.use(VueApollo);

jest.mock('~/lib/utils/common_utils', () => ({
  getCookie: jest.fn(),
}));

jest.mock('~/lib/utils/local_storage', () => ({
  getStorageValue: jest.fn(() => ({ exists: false })),
  saveStorageValue: jest.fn(),
  getSessionStorageValue: jest.fn(() => ({ exists: false })),
  saveSessionStorageValue: jest.fn(),
  removeSessionStorageValue: jest.fn(),
}));

jest.mock('ee/ai/utils', () => {
  const actualUtils = jest.requireActual('ee/ai/utils');

  return {
    __esModule: true,
    ...actualUtils,
    setAgenticMode: jest.fn(),
  };
});

describe('Duo Agentic Chat State Manager Light', () => {
  let wrapper;
  let mockStream;
  let store;

  const actionSpies = {
    addDuoChatMessage: jest.fn((context, message) => {
      // Use the real action implementation
      storeActions.addDuoChatMessage(context, message);
    }),
    setMessages: jest.fn((context, messages = []) => {
      // Directly commit to store instead of async dispatches to avoid timing issues
      context.commit('CLEAN_MESSAGES');
      messages?.forEach((msg) => {
        storeActions.addDuoChatMessage(context, msg);
      });
    }),
    setCurrentAgent: jest.fn((context, agent) => {
      storeActions.setCurrentAgent(context, agent);
    }),
  };

  const mockRefetch = jest.fn().mockResolvedValue({});
  let mockRouter;
  let mockRoute;
  const userWorkflowsQueryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_WORKFLOWS_RESPONSE);
  const contextPresetsQueryHandlerMock = jest.fn().mockResolvedValue(MOCK_CONTEXT_PRESETS_RESPONSE);
  const availableModelsQueryHandlerMock = jest
    .fn()
    .mockResolvedValue(MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE);
  const configuredAgentsQueryMock = jest.fn().mockResolvedValue(MOCK_CONFIGURED_AGENTS_RESPONSE);
  const aiFoundationalChatAgentsQueryMock = jest
    .fn()
    .mockResolvedValue(MOCK_FOUNDATIONAL_CHAT_AGENTS_RESPONSE);
  const agentFlowConfigQueryMock = jest.fn().mockResolvedValue(MOCK_FLOW_CONFIG_RESPONSE);
  const FLOW_STATUS_COMPLETED_RESPONSE = {
    data: {
      duoWorkflowWorkflows: {
        edges: [
          {
            node: {
              id: '1',
              status: 'completed',
            },
          },
        ],
      },
    },
  };
  const flowStatusQueryMock = jest.fn().mockResolvedValue(FLOW_STATUS_COMPLETED_RESPONSE);
  const createWorkflowMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE);
  const deleteWorkflowMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE);
  const updateWebSearchMutationMock = jest
    .fn()
    .mockResolvedValue(MOCK_UPDATE_WEB_SEARCH_MUTATION_RESPONSE);
  const workflowEventsQueryMock = jest
    .fn()
    .mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
  const workflowBranchesQueryMock = jest
    .fn()
    .mockResolvedValue({ data: { duoWorkflowBranches: [] } });
  const creditsAvailableQueryMock = jest.fn().mockResolvedValue({
    data: { gitlabCreditsAvailable: true, gitlabCreditsUnavailableReason: null },
  });
  const orbitPreferenceQueryMock = jest.fn();

  const findDuoChat = () => wrapper.findComponent(DuoAgenticChatView);
  const findPromptInputActions = () => wrapper.findComponent(PromptInputActions);

  const threadSnapshotEmpty = null;

  const createComponent = ({
    propsData = {},
    data = {},
    apolloHandlers = [[getAiChatAvailableModels, availableModelsQueryHandlerMock]],
    stubs = {},
    mountFn = shallowMountExtended,
    routeName = AGENTIC_CHAT_SHOW_ROUTE,
  } = {}) => {
    store = new Vuex.Store({
      mutations: storeMutations,
      actions: actionSpies,
      state: {
        messages: [],
        toolMessage: '',
        currentAgent: null,
      },
    });

    const apolloProvider = createMockApollo([
      [getUserWorkflows, userWorkflowsQueryHandlerMock],
      [getAiChatContextPresets, contextPresetsQueryHandlerMock],
      [getConfiguredAgents, configuredAgentsQueryMock],
      [getFoundationalChatAgents, aiFoundationalChatAgentsQueryMock],
      [getAgentFlowConfig, agentFlowConfigQueryMock],
      [getFlowStatus, flowStatusQueryMock],
      [duoWorkflowMutation, createWorkflowMutationMock],
      [deleteAgenticWorkflowMutation, deleteWorkflowMutationMock],
      [updateWebSearchMutation, updateWebSearchMutationMock],
      [getWorkflowLatestCheckpointQuery, workflowEventsQueryMock],
      [getWorkflowBranchesQuery, workflowBranchesQueryMock],
      [getGitlabCreditsStatusQuery, creditsAvailableQueryMock],
      [getOrbitUserPreference, orbitPreferenceQueryMock],
      ...apolloHandlers,
    ]);

    // Mirror real Vue Router: pushing a named location updates the reactive
    // $route so the route-derived multithreadedView computed re-evaluates.
    // eslint-disable-next-line no-restricted-properties
    mockRoute = Vue.observable({ name: routeName });
    mockRouter = {
      push: jest.fn((location) => {
        if (location?.name) {
          mockRoute.name = location.name;
        }
      }),
    };

    const defaultProvide = {
      chatConfiguration: {
        title: 'GitLab Duo Agentic Chat',
        isClassicAvailable: false,
        defaultProps: {
          defaultNamespaceSelected: true,
        },
      },
      activeTabData: {
        props: {
          isClassicAvailable: false,
        },
      },
    };

    wrapper = mountFn(DuoAgenticChatStateManagerLight, {
      store,
      apolloProvider,
      propsData: { stream: mockStream, ...propsData },
      provide: defaultProvide,
      mocks: {
        $router: mockRouter,
        $route: mockRoute,
      },
      stubs,
      data() {
        return data;
      },
    });

    if (wrapper.vm.$apollo?.queries?.agenticWorkflows) {
      wrapper.vm.$apollo.queries.agenticWorkflows.refetch = mockRefetch;
    }
  };

  beforeEach(() => {
    mockStream = createMockStream();
    mockRefetch.mockClear();
    loadThreadSnapshot.mockReturnValue(threadSnapshotEmpty);
    MOCK_UTILS_SETUP();
    // Reset Apollo handler mocks to default values
    createWorkflowMutationMock.mockResolvedValue(MOCK_CREATE_WORKFLOW_MUTATION_RESPONSE);
    deleteWorkflowMutationMock.mockResolvedValue(MOCK_DELETE_WORKFLOW_MUTATION_RESPONSE);
    workflowEventsQueryMock.mockResolvedValue({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
    workflowBranchesQueryMock.mockClear();
    workflowBranchesQueryMock.mockResolvedValue({ data: { duoWorkflowBranches: [] } });
    creditsAvailableQueryMock.mockResolvedValue({
      data: { gitlabCreditsAvailable: true, gitlabCreditsUnavailableReason: null },
    });
    orbitPreferenceQueryMock.mockResolvedValue({
      data: {
        currentUser: {
          id: 'gid://gitlab/User/1',
          userPreferences: { orbitSettings: { enabled: true } },
        },
      },
    });
    userWorkflowsQueryHandlerMock.mockResolvedValue(MOCK_USER_WORKFLOWS_RESPONSE);
    // In the default state, there isn't workflowId registered in session storage
    getSessionStorageValue.mockReturnValue({ exists: false, value: null });
  });

  afterEach(() => {
    if (wrapper) {
      wrapper = null;
    }
  });

  describe('effective Orbit preference', () => {
    let originalGon;

    beforeEach(() => {
      originalGon = window.gon;
    });

    afterEach(() => {
      window.gon = originalGon;
    });

    it('loads the effective value for workflow payloads', async () => {
      window.gon = { ...originalGon, orbit_available: true };
      createComponent();
      await waitForPromises();

      expect(wrapper.vm.orbitEnabled).toBe(true);
    });

    it('keeps orbitEnabled false and skips the query when Orbit is not available', async () => {
      window.gon = { ...originalGon, orbit_available: false };
      orbitPreferenceQueryMock.mockClear();
      createComponent();
      await waitForPromises();

      expect(wrapper.vm.orbitEnabled).toBe(false);
      expect(orbitPreferenceQueryMock).not.toHaveBeenCalled();
    });
  });

  describe('reduced presentation', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the agentic chat view', () => {
      expect(findDuoChat().exists()).toBe(true);
    });

    it('hides the chat header', () => {
      expect(findDuoChat().props('showHeader')).toBe(false);
    });

    it('does not provide the subheader or prompt-control slots', () => {
      const slots = getInstanceSlots(findDuoChat().vm);

      expect(slots.subheader).toBeUndefined();
      expect(slots['agentic-model']).toBeUndefined();
      expect(slots['agentic-switch']).toBeUndefined();
    });

    it('passes an empty chatPromptPlaceholder through by default', () => {
      expect(findDuoChat().props('chatPromptPlaceholder')).toBe('');
    });

    it('passes a custom chatPromptPlaceholder to AgenticDuoChat', () => {
      createComponent({
        propsData: { chatPromptPlaceholder: 'What would you like to work on?' },
      });

      expect(findDuoChat().props('chatPromptPlaceholder')).toBe('What would you like to work on?');
    });

    it('replaces the welcome empty state with a blank element for a subscribed user', () => {
      createComponent({ propsData: { subscriptionActive: true } });

      const [vnode] = getInstanceSlots(findDuoChat().vm)['custom-empty-state']({});

      expect(vnode.componentOptions).toBeUndefined();
      const testId = vnode.props
        ? vnode.props['data-testid'] // Vue 3
        : vnode.data.attrs['data-testid']; // Vue 2
      expect(testId).toBe('duo-chat-empty-state-opt-out');
    });

    it('provides the empty-state slot even when no gating state applies, keeping the view fallback hidden', () => {
      expect(getInstanceSlots(findDuoChat().vm)['custom-empty-state']({})).toBeDefined();
    });

    it('still renders gating empty states', async () => {
      creditsAvailableQueryMock.mockResolvedValue({
        data: { gitlabCreditsAvailable: false, gitlabCreditsUnavailableReason: null },
      });
      createComponent();
      await waitForPromises();

      const emptyState = getInstanceSlots(findDuoChat().vm)['custom-empty-state']({});

      expect(emptyState[0].componentOptions).toBeDefined();
    });
  });

  describe('@select-alternative', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    const seedMessages = (messages) => {
      messages.forEach((m) => store.commit('ADD_MESSAGE', m));
    };

    it('fetches branches before selecting a not-yet-loaded historical alternative', async () => {
      seedMessages([
        {
          id: 'user-1',
          role: 'user',
          content: 'What is GitLab?',
          alternative_count: 1,
          thread_ts: 'ts-1',
        },
        { id: 'assistant-1', role: 'assistant', content: 'GitLab is a DevSecOps platform.' },
      ]);
      workflowBranchesQueryMock.mockResolvedValue({
        data: { duoWorkflowBranches: [{ forkThreadTs: 'ts-fork', messages: [] }] },
      });

      findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-1', index: 1 });
      await waitForPromises();

      expect(workflowBranchesQueryMock).toHaveBeenCalledWith(
        expect.objectContaining({ threadTs: 'ts-1' }),
      );
      expect(findDuoChat().props('selectedAlternatives')).toEqual({ 'assistant-1': 1 });
    });

    it('does not fetch branches when selecting an alternative from a live retry in this session', async () => {
      seedMessages([
        { id: 'user-1', role: 'user', content: 'What is GitLab?' },
        { id: 'assistant-1', role: 'assistant', content: 'First (failed) answer' },
        { id: 'user-2', role: 'user', content: 'What is GitLab?', is_retry: true },
        { id: 'assistant-2', role: 'assistant', content: 'Second answer' },
      ]);

      findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-2', index: 1 });
      await waitForPromises();

      expect(workflowBranchesQueryMock).not.toHaveBeenCalled();
      expect(findDuoChat().props('selectedAlternatives')).toEqual({ 'assistant-2': 1 });
    });

    it("hands the view the selected alternative's user message", async () => {
      const olderUser = { id: 'user-old', role: 'user', content: 'Same question' };
      const transformedOutput = [
        { id: 'user-new', role: 'user', content: 'Same question' },
        {
          id: 'assistant-1',
          role: 'assistant',
          content: 'A response',
          alternatives: [{ user_message: olderUser, agent_responses: [] }],
        },
      ];
      runMessageTransformers.mockReturnValue(transformedOutput);
      seedMessages([{ id: 'user-new', role: 'user', content: 'Same question' }]);

      findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-1', index: 1 });
      await waitForPromises();

      expect(findDuoChat().props('messages')).toEqual([olderUser, transformedOutput[1]]);
      expect(wrapper.vm.transformedMessages).toEqual(transformedOutput);
    });

    it('ignores navigation while a turn is in flight', async () => {
      seedMessages([
        { id: 'user-1', role: 'user', content: 'What is GitLab?' },
        { id: 'assistant-1', role: 'assistant', content: 'First (failed) answer' },
        { id: 'user-2', role: 'user', content: 'What is GitLab?' },
        { id: 'assistant-2', role: 'assistant', content: 'Second answer' },
      ]);

      // Sending a prompt marks the turn as in flight (isWaitingOnPrompt).
      findDuoChat().vm.$emit('send-chat-prompt', 'What is GitLab?');
      await nextTick();

      findDuoChat().vm.$emit('select-alternative', { messageId: 'assistant-2', index: 1 });
      await waitForPromises();

      expect(findDuoChat().props('selectedAlternatives')).toEqual({});
    });
  });

  describe('connection loss recovery', () => {
    const stream = () => mockStream;

    const emitSocketError = async (event) => {
      const errorSubscription = stream().subscribe.mock.calls.find(([name]) => name === 'error');
      errorSubscription[1](event);
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      // Take ownership of the connection first.
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();
    });

    it('clears the spinner and offers a retry when the stream gives up', async () => {
      await emitSocketError({ reason: 'max_retries_exceeded' });

      expect(findDuoChat().props('isLoading')).toBe(false);
      expect(wrapper.findComponent(ConnectionErrorAlert).exists()).toBe(true);
      expect(findDuoChat().props('chatState')).toMatchObject({ isEnabled: false });
    });

    it('disables the composer toolbar along with the input', async () => {
      expect(findPromptInputActions().props('disabled')).toBe(false);

      await emitSocketError({ reason: 'max_retries_exceeded' });

      expect(findPromptInputActions().props('disabled')).toBe(true);
    });

    it('retries the connection from the alert', async () => {
      await emitSocketError({ reason: 'max_retries_exceeded' });

      wrapper.findComponent(ConnectionErrorAlert).vm.$emit('retry');
      await waitForPromises();

      expect(stream().retry).toHaveBeenCalled();
      expect(wrapper.findComponent(ConnectionErrorAlert).exists()).toBe(false);
      expect(findDuoChat().props('isLoading')).toBe(true);
    });

    it('stays usable when the retry has nothing to reconnect', async () => {
      await emitSocketError({ reason: 'max_retries_exceeded' });
      stream().retry.mockReturnValueOnce(false);

      wrapper.findComponent(ConnectionErrorAlert).vm.$emit('retry');
      await waitForPromises();

      expect(wrapper.findComponent(ConnectionErrorAlert).exists()).toBe(false);
      expect(findDuoChat().props('isLoading')).toBe(false);
      expect(findDuoChat().props('canSendPrompt')).toBe(true);
    });

    it('clears the connection error when a new chat starts', async () => {
      await emitSocketError({ reason: 'max_retries_exceeded' });

      findDuoChat().vm.$emit('new-chat');
      await waitForPromises();

      expect(wrapper.findComponent(ConnectionErrorAlert).exists()).toBe(false);
      expect(findDuoChat().props('chatState')).toMatchObject({ isEnabled: true });
      expect(findDuoChat().props('canSendPrompt')).toBe(true);
    });
  });

  describe('deferred workflow list', () => {
    it('does not fetch the list on a fresh session', async () => {
      userWorkflowsQueryHandlerMock.mockClear();
      createComponent();
      await waitForPromises();

      expect(userWorkflowsQueryHandlerMock).not.toHaveBeenCalled();
    });

    it('fetches the list when a thread needs hydrating', async () => {
      userWorkflowsQueryHandlerMock.mockClear();
      createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
      await waitForPromises();

      expect(userWorkflowsQueryHandlerMock).toHaveBeenCalledTimes(1);
    });
  });

  describe('context presets failure', () => {
    it('stays out of the transcript and reports to Sentry', async () => {
      contextPresetsQueryHandlerMock.mockRejectedValueOnce(new Error('presets down'));
      createComponent();
      await waitForPromises();

      expect(captureExceptionForDuoChat).toHaveBeenCalledWith(expect.any(Error));
      expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ errors: expect.anything() }),
      );
    });
  });

  describe('session persistence opt-out', () => {
    it('never reads or writes the shared current-workflow record', async () => {
      createComponent();
      await waitForPromises();

      expect(getSessionStorageValue).not.toHaveBeenCalled();
      expect(saveSessionStorageValue).not.toHaveBeenCalled();
      expect(removeSessionStorageValue).not.toHaveBeenCalled();
    });
  });

  describe('a rejected request', () => {
    it('reports it in the thread instead of ending the turn silently', async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();
      actionSpies.addDuoChatMessage.mockClear();

      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({ code: WS_CLOSE_INVALID_REQUEST, reason: 'missing conversation point' });
      await waitForPromises();

      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(expect.anything(), {
        errors: ['Could not process the last message. Send a new message to try again.'],
      });
      expect(captureExceptionForDuoChat).toHaveBeenCalled();
    });

    it('stops waiting on the turn, whatever the last checkpoint status was', async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();

      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({ code: WS_CLOSE_INVALID_REQUEST });
      await waitForPromises();

      expect(findDuoChat().props('isLoading')).toBe(false);
    });
  });

  describe('a denied request', () => {
    it("surfaces the service's denial reason in the thread", async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();
      actionSpies.addDuoChatMessage.mockClear();

      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({
        code: WS_CLOSE_PERMISSION_DENIED,
        reason: 'Model not allowed for this group',
      });
      await waitForPromises();

      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(expect.anything(), {
        errors: ['Model not allowed for this group'],
      });
      expect(captureExceptionForDuoChat).toHaveBeenCalled();
    });

    it('falls back to a generic message when the close frame carries no reason', async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();
      actionSpies.addDuoChatMessage.mockClear();

      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({ code: WS_CLOSE_PERMISSION_DENIED });
      await waitForPromises();

      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(expect.anything(), {
        errors: ['The workflow service denied this request.'],
      });
    });
  });

  describe('embedded landmark', () => {
    it('labels the chat region and avoids the panel chat id', async () => {
      createComponent();
      await waitForPromises();

      expect(findDuoChat().attributes('id')).toBe('duo-chat-embedded');
      expect(findDuoChat().attributes('aria-label')).toBe('GitLab Duo Chat');
      // Region, not complementary: the panel already owns that landmark on this page.
      expect(findDuoChat().attributes('role')).toBe('region');
    });
  });

  // This variant is a parallel copy of the full state manager, so the attachment
  // wiring has to be asserted here too. Without it the composer would accept files
  // and this manager would drop them on the way to the flow service.
  describe('attachments', () => {
    const attachment = {
      id: 'att-1',
      filename: 'diagram.png',
      mimeType: 'image/png',
      byteSize: 2048,
      data: 'aGVsbG8=',
      previewUrl: 'data:image/png;base64,aGVsbG8=',
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('forwards the attachments as additional context', async () => {
      findDuoChat().vm.$emit(
        'send-chat-prompt',
        createUserPrompt({ text: 'Explain this image', attachments: [attachment] }),
      );
      await waitForPromises();

      const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

      expect(call[0].additionalContext.filter((c) => c.category === 'attachments')).toEqual([
        {
          category: 'attachments',
          content: JSON.stringify({
            mime_type: 'image/png',
            data: 'aGVsbG8=',
            filename: 'diagram.png',
          }),
          metadata: '{}',
        },
      ]);
    });

    // An image on its own is a user turn, not an approval resume, so it keeps the
    // context that only a user turn carries.
    it('carries the foundational agent context when only images are sent', async () => {
      // Assigned rather than passed as `data`: loading the workflow resolves the
      // selection itself, and would clear a value seeded before it.
      wrapper.vm.orbitEnabled = true;
      wrapper.vm.selectedFoundationalAgent = {
        referenceWithVersion: 'agent@1.0.0',
        flowConfig: null,
      };

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ attachments: [attachment] }));
      await waitForPromises();

      const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

      expect(call[0].additionalContext).toEqual(
        expect.arrayContaining([
          {
            category: 'orbit_context',
            content: JSON.stringify({ orbit_enabled: true }),
            metadata: '{}',
          },
        ]),
      );
    });

    it('adds no attachments envelope when the event omits them', async () => {
      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Just text' }));
      await waitForPromises();

      const [call] = WorkflowSocketUtils.buildStartRequest.mock.calls;

      expect(call[0].additionalContext.filter((c) => c.category === 'attachments')).toEqual([]);
    });

    it('opens the file picker when the actions menu asks for it', () => {
      const openFilePicker = jest.fn();
      findDuoChat().vm.openFilePicker = openFilePicker;

      findPromptInputActions().vm.$emit('attach-files');

      expect(openFilePicker).toHaveBeenCalled();
    });
  });

  describe('a private stream', () => {
    it('builds its own retrying stream when none is supplied', async () => {
      const ownStream = createMockStream();
      RetryableWorkflowStream.mockImplementation(() => ownStream);

      createComponent({ propsData: { stream: null } });
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();

      expect(WorkflowStream).toHaveBeenCalledTimes(1);
      expect(RetryableWorkflowStream).toHaveBeenCalledWith(
        expect.any(Object),
        expect.objectContaining({ maxRetries: expect.any(Number), retryDelay: expect.any(Number) }),
      );
      expect(ownStream.connect).toHaveBeenCalled();
    });

    it('uses the supplied stream and never touches another', async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'hello');
      await waitForPromises();

      expect(mockStream.connect).toHaveBeenCalledTimes(1);
      expect(RetryableWorkflowStream).not.toHaveBeenCalled();
    });

    it('does not adopt a stream that is already connected at mount', async () => {
      mockStream.getStatus.mockReturnValue({ connected: true, bufferedCount: 0 });
      createComponent();
      await waitForPromises();

      expect(mockStream.subscribe).not.toHaveBeenCalled();
      expect(findDuoChat().props('isLoading')).toBe(false);
      expect(findDuoChat().props('chatState')).toMatchObject({ isEnabled: true });
    });

    it('terminates its stream on destroy', async () => {
      createComponent();
      await waitForPromises();

      wrapper.destroy();

      expect(mockStream.terminate).toHaveBeenCalledTimes(1);
    });
  });

  describe('prompts during a turn', () => {
    const closeStream = async () => {
      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({ code: WS_CLOSE_NORMAL });
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', 'first');
      await waitForPromises();
    });

    it('tells the composer to queue while a turn is running', () => {
      expect(findDuoChat().props('canSendPrompt')).toBe(false);
    });

    it('holds a queued prompt and shows it', async () => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();

      expect(findDuoChat().props('queuedPrompts')).toEqual([
        expect.objectContaining({
          id: expect.any(String),
          prompt: expect.objectContaining({ text: 'second' }),
        }),
      ]);
      expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ role: 'user', content: 'second' }),
      );
    });

    it('sends the queued prompt once the turn ends', async () => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();

      await closeStream();

      expect(findDuoChat().props('canSendPrompt')).toBe(false);
      expect(findDuoChat().props('queuedPrompts')).toEqual([]);
      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ role: 'user', content: 'second' }),
      );
    });

    it('waits for the socket to close before draining, not for the agent status', async () => {
      const openHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'open')[1];
      openHandler();
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();

      // The agent's final status arrives before Workhorse releases the lock.
      WorkflowSocketUtils.processWorkflowMessage.mockResolvedValueOnce({
        lastProcessedMessageId: 'final',
        messages: [],
        status: DUO_WORKFLOW_STATUS_INPUT_REQUIRED,
      });
      mockStream.subscribe.mock.calls.find(([name]) => name === 'message')[1]({ data: '{}' });
      await waitForPromises();

      expect(findDuoChat().props('canSendPrompt')).toBe(false);
      expect(findDuoChat().props('queuedPrompts')).toHaveLength(1);

      await closeStream();

      expect(findDuoChat().props('queuedPrompts')).toEqual([]);
      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ role: 'user', content: 'second' }),
      );
    });

    it('holds a queued prompt while a tool approval is pending', async () => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();

      // The turn pauses on a tool approval and the service closes the socket.
      WorkflowSocketUtils.processWorkflowMessage.mockResolvedValueOnce({
        lastProcessedMessageId: 'approval',
        messages: [],
        status: DUO_WORKFLOW_STATUS_TOOL_CALL_APPROVAL_REQUIRED,
      });
      mockStream.subscribe.mock.calls.find(([name]) => name === 'message')[1]({ data: '{}' });
      await waitForPromises();
      await closeStream();

      // The composer can still send, which the user does to skip the approval.
      expect(findDuoChat().props('canSendPrompt')).toBe(true);
      expect(findDuoChat().props('queuedPrompts')).toHaveLength(1);
      expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ role: 'user', content: 'second' }),
      );

      wrapper.vm.workflowStatus = DUO_WORKFLOW_STATUS_INPUT_REQUIRED;
      await waitForPromises();

      expect(findDuoChat().props('queuedPrompts')).toEqual([]);
      expect(actionSpies.addDuoChatMessage).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ role: 'user', content: 'second' }),
      );
    });

    it('drops a queued prompt on request', async () => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();
      const [{ id }] = findDuoChat().props('queuedPrompts');

      findDuoChat().vm.$emit('remove-queued-prompt', id);
      await nextTick();

      expect(findDuoChat().props('queuedPrompts')).toEqual([]);
    });

    it('drops the queue when the turn is stopped', async () => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();

      findDuoChat().vm.$emit('chat-cancel');
      await waitForPromises();

      expect(findDuoChat().props('queuedPrompts')).toEqual([]);
      expect(findDuoChat().props('canSendPrompt')).toBe(true);
      expect(actionSpies.addDuoChatMessage).not.toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ role: 'user', content: 'second' }),
      );
      expect(mockStream.connect).toHaveBeenCalledTimes(1);
    });

    it('clears the queue when a new chat starts', async () => {
      findDuoChat().vm.$emit('queue-chat-prompt', createUserPrompt({ text: 'second' }));
      await nextTick();

      findDuoChat().vm.$emit('new-chat');
      await waitForPromises();

      expect(findDuoChat().props('queuedPrompts')).toEqual([]);
    });
  });

  describe('a thread that is still loading', () => {
    it('queues prompts until the thread has loaded', async () => {
      let finishLoad;
      workflowEventsQueryMock.mockReturnValueOnce(
        new Promise((resolve) => {
          finishLoad = () => resolve({ data: MOCK_WORKFLOW_EVENTS_RESPONSE });
        }),
      );
      // A restored snapshot renders the transcript, and the composer with it,
      // before the thread load confirms it.
      loadThreadSnapshot.mockReturnValue({
        messages: [{ id: 'restored', role: 'user', content: 'earlier' }],
      });
      createComponent({ data: { workflowId: MOCK_WORKFLOW_ID } });
      await waitForPromises();

      expect(findDuoChat().exists()).toBe(true);
      expect(findDuoChat().props('canSendPrompt')).toBe(false);

      finishLoad();
      await waitForPromises();

      expect(findDuoChat().props('canSendPrompt')).toBe(true);
    });

    it('queues prompts while the chat is unavailable', async () => {
      createComponent();
      await waitForPromises();

      wrapper.vm.isChatAvailable = false;
      await nextTick();

      expect(findDuoChat().props('canSendPrompt')).toBe(false);
    });
  });

  describe('a disabled chat', () => {
    beforeEach(async () => {
      // Another client keeps the flow, so the status poll never releases the lock.
      flowStatusQueryMock.mockReturnValue(new Promise(() => {}));
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'hello' }));
      await waitForPromises();

      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({ code: WS_CLOSE_TRY_AGAIN_LATER });
      await waitForPromises();
    });

    afterEach(() => {
      flowStatusQueryMock.mockReset().mockResolvedValue(FLOW_STATUS_COMPLETED_RESPONSE);
    });

    it('leaves the disabled reason banner to the view', () => {
      // The view renders the reason in its alerts fallback while the header is
      // hidden, so an alert here would show the same sentence twice.
      expect(store.state.messages).not.toHaveLength(0);
      expect(findDuoChat().props('chatState')).toEqual({
        isEnabled: false,
        reason: expect.stringContaining('another tab or location'),
      });
      expect(wrapper.findAllComponents(GlAlert)).toHaveLength(0);
    });
  });

  describe('sending into an existing thread', () => {
    const sendFollowUp = async () => {
      const closeHandler = mockStream.subscribe.mock.calls.find(([name]) => name === 'close')[1];
      closeHandler({ code: WS_CLOSE_NORMAL });
      await waitForPromises();

      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'Follow-up question' }));
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      findDuoChat().vm.$emit('send-chat-prompt', createUserPrompt({ text: 'hello' }));
      await waitForPromises();

      workflowEventsQueryMock.mockClear();
      flowStatusQueryMock.mockClear();
    });

    afterEach(() => {
      flowStatusQueryMock.mockReset().mockResolvedValue(FLOW_STATUS_COMPLETED_RESPONSE);
    });

    it('checks the thread still exists without re-reading its message history', async () => {
      await sendFollowUp();

      expect(flowStatusQueryMock).toHaveBeenCalledWith({ id: MOCK_WORKFLOW_ID });
      expect(workflowEventsQueryMock).not.toHaveBeenCalled();
    });

    it('locks the chat as deleted when the status check reports WORKFLOW_NOT_FOUND', async () => {
      flowStatusQueryMock.mockRejectedValue({
        graphQLErrors: [
          { message: 'Workflow not found', extensions: { code: 'WORKFLOW_NOT_FOUND' } },
        ],
      });

      await sendFollowUp();

      expect(findDuoChat().props('isChatAvailable')).toBe(false);
    });
  });
});
