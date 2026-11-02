import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { DuoChatPredefinedPrompts } from '@gitlab/duo-ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import getFirstChatThread from 'ee/ai/graphql/get_first_chat_thread.query.graphql';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import ChatEmptyState from 'ee/ai/duo_agentic_chat/components/empty_state/chat_empty_state.vue';
import PromptCategories from 'ee/ai/duo_agentic_chat/components/empty_state/prompt_categories.vue';

Vue.use(VueApollo);

jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

describe('ChatEmptyState', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const promptCategories = [
    {
      key: 'merge_request',
      title: '!42',
      contextual: true,
      questions: ['What changed in this diff?'],
    },
    {
      key: 'get_started',
      title: 'Get started',
      contextual: false,
      questions: ['Help me make my CI pipelines run faster'],
    },
    {
      key: 'development',
      title: 'Development',
      contextual: false,
      questions: ['Show me automated testing strategies'],
    },
  ];

  const firstChatThreadHandler = (nodes) =>
    jest.fn().mockResolvedValue({ data: { duoWorkflowWorkflows: { nodes } } });
  const existingThreads = () =>
    firstChatThreadHandler([{ id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1' }]);
  const noThreads = () => firstChatThreadHandler([]);

  const createComponent = (
    props = {},
    {
      firstChatThreadQueryMock = existingThreads(),
      apolloProvider = createMockApollo([[getFirstChatThread, firstChatThreadQueryMock]]),
      slots = {},
    } = {},
  ) => {
    wrapper = shallowMountExtended(ChatEmptyState, {
      apolloProvider,
      propsData: {
        promptCategories,
        ...props,
      },
      slots: {
        input: '<textarea data-testid="input-slot-content"></textarea>',
        ...slots,
      },
    });
  };

  // The thread check decides which variant renders, so settle it before
  // asserting unless the test is about the in-flight state itself.
  const createComponentForReturningUser = async (props = {}, slots = {}) => {
    createComponent(props, { slots });
    await waitForPromises();
  };

  const createComponentForFirstTimeUser = async (props = {}) => {
    createComponent(props, { firstChatThreadQueryMock: noThreads() });
    await waitForPromises();
  };

  const findHeading = () => wrapper.findByTestId('chat-empty-state-heading');
  const findSecondaryText = () => wrapper.findByTestId('chat-empty-state-secondary-text');
  const findPromptCategories = () => wrapper.findComponent(PromptCategories);
  const findPredefinedPrompts = () => wrapper.findComponent(DuoChatPredefinedPrompts);
  const findSuggestions = () => wrapper.findByTestId('chat-empty-state-suggestions');

  describe('for a returning user', () => {
    beforeEach(() => createComponentForReturningUser());

    it('renders the returning heading without secondary text', () => {
      expect(findHeading().text()).toBe("What's next?");
      expect(findSecondaryText().exists()).toBe(false);
    });

    it('renders the input slot', () => {
      expect(wrapper.findByTestId('input-slot-content').exists()).toBe(true);
    });

    it('shows the suggestions', () => {
      expect(findSuggestions().isVisible()).toBe(true);
    });

    it('filters out the Get started category and expands the contextual one', () => {
      expect(findPromptCategories().props('categories')).toEqual([
        promptCategories[0],
        promptCategories[2],
      ]);
      expect(findPromptCategories().props('initialExpandedKey')).toBe('merge_request');
    });

    it('re-emits a selected prompt', () => {
      findPromptCategories().vm.$emit('select', 'What does this code do?');

      expect(wrapper.emitted('send-prompt')).toEqual([['What does this code do?']]);
    });
  });

  // The events feed the trial or paid funnel, so any other user leaves them alone.
  describe('funnel tracking', () => {
    const selectPrompt = () => findPromptCategories().vm.$emit('select', 'What does this code do?');

    describe('for a user with a trial or subscription', () => {
      beforeEach(() => createComponentForReturningUser({ hasTrialOrSubscription: true }));

      it('tracks viewing the empty state', () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        expect(trackEventSpy).toHaveBeenCalledWith(
          'view_dap_trial_or_paid_empty_state',
          {},
          undefined,
        );
      });

      it('tracks a selected prompt', () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        selectPrompt();

        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_dap_trial_or_paid_empty_state_prompt',
          { label: 'What does this code do?' },
          undefined,
        );
      });
    });

    describe('for a user without a trial or subscription', () => {
      beforeEach(() => createComponentForReturningUser());

      it('tracks neither the view nor a selected prompt', () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        selectPrompt();

        expect(trackEventSpy).not.toHaveBeenCalled();
      });
    });
  });

  describe('for a first-time user', () => {
    beforeEach(() => createComponentForFirstTimeUser());

    it('renders the introduction heading and secondary text', () => {
      expect(findHeading().text()).toBe('Hello from GitLab Duo');
      expect(findSecondaryText().text()).toBe(
        'Collaborate with AI to accomplish tasks or answer questions.',
      );
    });

    it('keeps the Get started category but expands the contextual one', () => {
      expect(findPromptCategories().props('categories')).toEqual(promptCategories);
      expect(findPromptCategories().props('initialExpandedKey')).toBe('merge_request');
    });
  });

  describe('with a selected agent that has its own questions', () => {
    const agentCategory = {
      key: 'agent',
      title: 'Security Analyst',
      contextual: false,
      questions: ['Which vulnerabilities should I fix first?'],
    };

    it('expands the agent category ahead of the contextual one', async () => {
      await createComponentForReturningUser({
        promptCategories: [agentCategory, ...promptCategories],
      });

      expect(findPromptCategories().props('initialExpandedKey')).toBe('agent');
    });

    it('expands the agent category ahead of Get started for a first-time user', async () => {
      await createComponentForFirstTimeUser({
        promptCategories: [
          agentCategory,
          ...promptCategories.filter((category) => !category.contextual),
        ],
      });

      expect(findPromptCategories().props('initialExpandedKey')).toBe('agent');
    });
  });

  describe('on a page with no contextual category', () => {
    const genericCategories = promptCategories.filter((category) => !category.contextual);

    describe('for a first-time user', () => {
      beforeEach(() => createComponentForFirstTimeUser({ promptCategories: genericCategories }));

      it('falls back to expanding the Get started category', () => {
        expect(findPromptCategories().props('initialExpandedKey')).toBe('get_started');
      });
    });

    describe('for a returning user', () => {
      beforeEach(() => createComponentForReturningUser({ promptCategories: genericCategories }));

      it('expands nothing', () => {
        expect(findPromptCategories().props('initialExpandedKey')).toBe(null);
      });
    });
  });

  describe('while the thread check is in flight', () => {
    beforeEach(() => {
      createComponent();
    });

    it('holds back the heading', () => {
      expect(findHeading().exists()).toBe(false);
    });

    it('renders the categories without Get started, expanding none', () => {
      expect(findPromptCategories().props('categories')).toEqual([
        promptCategories[0],
        promptCategories[2],
      ]);
      expect(findPromptCategories().props('initialExpandedKey')).toBe(null);
    });
  });

  describe('when remounted for a new chat', () => {
    const remount = async (nodes) => {
      const handler = firstChatThreadHandler(nodes);
      const apolloProvider = createMockApollo([[getFirstChatThread, handler]]);
      createComponent({}, { firstChatThreadQueryMock: handler, apolloProvider });
      await waitForPromises();
      wrapper.destroy();

      handler.mockReturnValue(new Promise(() => {}));
      createComponent({}, { firstChatThreadQueryMock: handler, apolloProvider });
      await waitForPromises();
    };

    it('renders the returning heading from cache while the check reruns', async () => {
      await remount([{ id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1' }]);

      expect(findHeading().text()).toBe("What's next?");
    });

    it('holds back the heading when the cache has no threads', async () => {
      await remount([]);

      expect(findHeading().exists()).toBe(false);
    });
  });

  describe('when the thread check fails', () => {
    beforeEach(async () => {
      createComponent(
        {},
        {
          firstChatThreadQueryMock: jest.fn().mockRejectedValue(new Error('Network error')),
        },
      );
      await waitForPromises();
    });

    it('falls back to the returning-user variant', () => {
      expect(findHeading().text()).toBe("What's next?");
      expect(findSecondaryText().exists()).toBe(false);
    });

    it('reports the failure', () => {
      expect(captureExceptionForDuoChat).toHaveBeenCalledWith(expect.any(Error));
    });
  });

  describe('with a slash-command welcome message', () => {
    beforeEach(() =>
      createComponentForFirstTimeUser({ welcomeMessage: 'Ready to plan some work?' }),
    );

    it('renders the override heading without secondary text', () => {
      expect(findHeading().text()).toBe('Ready to plan some work?');
      expect(findSecondaryText().exists()).toBe(false);
    });

    it('renders the override heading while the thread check is in flight', () => {
      createComponent({ welcomeMessage: 'Ready to plan some work?' });

      expect(findHeading().text()).toBe('Ready to plan some work?');
    });
  });

  describe('with slash-command prompt overrides', () => {
    beforeEach(() =>
      createComponentForReturningUser({ overridePrompts: ['Generate a work plan'] }),
    );

    it('renders the flat prompt list instead of the categories', () => {
      expect(findPredefinedPrompts().props('prompts')).toEqual(['Generate a work plan']);
      expect(findPromptCategories().exists()).toBe(false);
    });

    it('tracks and re-emits a clicked override prompt', () => {
      findPredefinedPrompts().vm.$emit('click', 'Generate a work plan');

      expect(wrapper.emitted('send-prompt')).toEqual([['Generate a work plan']]);
    });
  });

  describe('with a drafted prompt', () => {
    beforeEach(() => createComponentForReturningUser({ hasDraft: true }));

    it('hides the suggestions so the input can grow', () => {
      expect(findSuggestions().isVisible()).toBe(false);
    });

    it('keeps the heading and the input', () => {
      expect(findHeading().exists()).toBe(true);
      expect(wrapper.findByTestId('input-slot-content').exists()).toBe(true);
    });
  });

  describe('with a notice', () => {
    beforeEach(() =>
      createComponentForReturningUser(
        {},
        { notice: '<div data-testid="notice-slot-content"></div>' },
      ),
    );

    it('renders the notice above the input', () => {
      const notice = wrapper.findByTestId('notice-slot-content').element;
      const input = wrapper.findByTestId('input-slot-content').element;

      expect(notice.compareDocumentPosition(input)).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
    });

    it('hides the suggestions', () => {
      expect(findSuggestions().exists()).toBe(false);
    });
  });

  describe('without categories or overrides', () => {
    beforeEach(() => createComponentForReturningUser({ promptCategories: [] }));

    it('renders neither prompt list', () => {
      expect(findPromptCategories().exists()).toBe(false);
      expect(findPredefinedPrompts().exists()).toBe(false);
    });
  });
});
