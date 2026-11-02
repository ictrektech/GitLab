import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlDisclosureDropdown } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ChatModelSelector from 'ee/ai/duo_agentic_chat/components/model_selection/chat_model_selector.vue';
import ChatModelSelectDropdown from 'ee/ai/duo_agentic_chat/components/model_selection/chat_model_select_dropdown.vue';
import getAiChatAvailableModels from 'ee/ai/graphql/get_ai_chat_available_models.query.graphql';
import {
  getRecentModelRefs,
  recordRecentModelRef,
  saveModel,
} from 'ee/ai/duo_agentic_chat/utils/model_selection_utils';
import {
  MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE,
  MOCK_NEW_MODEL_SELECTION_LIST_ITEMS,
} from '../mock_data';

// The storage round trip is covered by model_selection_utils_spec.
jest.mock('ee/ai/duo_agentic_chat/utils/model_selection_utils', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat/utils/model_selection_utils'),
  saveModel: jest.fn(),
  getRecentModelRefs: jest.fn(),
  recordRecentModelRef: jest.fn(),
}));

Vue.use(VueApollo);

const MOCK_ROOT_NAMESPACE_ID = 'gid://gitlab/Group/456';
const MOCK_NAMESPACE_ID = 'gid://gitlab/Group/789';
const MOCK_PROJECT_ID = 'gid://gitlab/Project/1';
const DEFAULT_MODEL_ITEM = MOCK_NEW_MODEL_SELECTION_LIST_ITEMS[0];

const MOCK_PINNED_MODEL = { name: 'Claude Haiku 4.5 - Anthropic', ref: 'claude_haiku_4_5' };

const buildPinnedModelsResponse = (pinnedModel) => {
  const { aiChatAvailableModels } = MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE.data;

  return {
    data: {
      aiChatAvailableModels: {
        ...aiChatAvailableModels,
        selectableModels: [
          ...aiChatAvailableModels.selectableModels,
          {
            ...MOCK_PINNED_MODEL,
            modelProvider: 'Anthropic',
            modelDescription: null,
            costIndicator: null,
            requiresPaidCredits: false,
          },
        ],
        pinnedModel,
      },
    },
  };
};

describe('ChatModelSelector', () => {
  let wrapper;
  let availableModelsQueryMock;

  const findDropdown = () => wrapper.findComponent(ChatModelSelectDropdown);
  const findUnavailableDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findUnavailableMessage = () => wrapper.findByTestId('model-selection-unavailable-message');
  const findAgenticChatToggle = () => wrapper.findComponentByTestId('agentic-chat-toggle');
  const findAgenticChatRow = () => wrapper.findByTestId('agentic-chat-toggle-row');

  const createComponent = ({ propsData = {} } = {}) => {
    const apolloProvider = createMockApollo([[getAiChatAvailableModels, availableModelsQueryMock]]);

    wrapper = shallowMountExtended(ChatModelSelector, {
      apolloProvider,
      propsData: {
        rootNamespaceId: MOCK_ROOT_NAMESPACE_ID,
        ...propsData,
      },
    });
  };

  beforeEach(() => {
    availableModelsQueryMock = jest.fn().mockResolvedValue(MOCK_AI_CHAT_AVAILABLE_MODELS_RESPONSE);
    getRecentModelRefs.mockReturnValue(['claude_3_5_sonnet_20240620']);
    recordRecentModelRef.mockReturnValue(['claude_sonnet_4_20250514']);
  });

  describe('available models query', () => {
    it.each`
      description       | propsData                             | expectedVariables
      ${'a project'}    | ${{ projectId: MOCK_PROJECT_ID }}     | ${{ projectId: MOCK_PROJECT_ID }}
      ${'a namespace'}  | ${{ namespaceId: MOCK_NAMESPACE_ID }} | ${{ namespaceId: MOCK_NAMESPACE_ID }}
      ${'a root group'} | ${{}}                                 | ${{ rootNamespaceId: MOCK_ROOT_NAMESPACE_ID }}
    `('queries the models of $description', async ({ propsData, expectedVariables }) => {
      createComponent({ propsData });
      await waitForPromises();

      expect(availableModelsQueryMock).toHaveBeenCalledWith(expectedVariables);
    });

    it('does not query when there is no project or namespace', async () => {
      createComponent({ propsData: { rootNamespaceId: null } });
      await waitForPromises();

      expect(availableModelsQueryMock).not.toHaveBeenCalled();
    });

    it('does not query in non-agentic mode', async () => {
      createComponent({ propsData: { agenticModeEnabled: false } });
      await waitForPromises();

      expect(availableModelsQueryMock).not.toHaveBeenCalled();
    });

    it('emits `error` when the query fails', async () => {
      const error = new Error('nope');
      availableModelsQueryMock.mockRejectedValue(error);
      createComponent();
      await waitForPromises();

      expect(wrapper.emitted('error')).toHaveLength(1);
    });
  });

  describe('when the query has resolved', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('maps the models to plain names with `ref` and `isDefault`', () => {
      expect(findDropdown().props('items')).toEqual(MOCK_NEW_MODEL_SELECTION_LIST_ITEMS);
    });

    it('passes the stored recent refs to the dropdown', () => {
      expect(findDropdown().props('recentRefs')).toEqual(['claude_3_5_sonnet_20240620']);
    });

    it('selects the default model and stops showing the loading state', () => {
      expect(findDropdown().props('selectedOption')).toEqual(DEFAULT_MODEL_ITEM);
      expect(findDropdown().props('isLoading')).toBe(false);
    });

    it('emits `change` with the resolved and the default model', () => {
      expect(wrapper.emitted('change')).toEqual([
        [{ currentModel: DEFAULT_MODEL_ITEM, defaultModel: DEFAULT_MODEL_ITEM }],
      ]);
    });

    it('renders an enabled model selection dropdown', () => {
      expect(findDropdown().props('disabled')).toBe(false);
      expect(findUnavailableDropdown().exists()).toBe(false);
    });
  });

  describe('when a model is selected', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findDropdown().vm.$emit('select', DEFAULT_MODEL_ITEM.value);
      await waitForPromises();
    });

    it('saves the model locally', () => {
      expect(saveModel).toHaveBeenCalledWith(DEFAULT_MODEL_ITEM);
    });

    it('emits `change` with the new selection', () => {
      expect(wrapper.emitted('change')[1]).toEqual([
        { currentModel: DEFAULT_MODEL_ITEM, defaultModel: DEFAULT_MODEL_ITEM },
      ]);
    });

    it('records the selected ref and shows the list it gets back', () => {
      expect(recordRecentModelRef).toHaveBeenCalledWith('claude_sonnet_4_20250514');
      expect(findDropdown().props('recentRefs')).toEqual(['claude_sonnet_4_20250514']);
    });

    it('ignores a selection that is not in the model list', async () => {
      findDropdown().vm.$emit('select', 'not_a_model');
      await waitForPromises();

      expect(wrapper.emitted('change')).toHaveLength(2);
      expect(recordRecentModelRef).toHaveBeenCalledTimes(1);
    });
  });

  describe('when nothing has been recorded yet', () => {
    beforeEach(async () => {
      getRecentModelRefs.mockReturnValue([]);
      createComponent();
      await waitForPromises();
    });

    it('renders the dropdown without a recents group', () => {
      expect(findDropdown().props('recentRefs')).toEqual([]);
    });
  });

  describe('when a model is pinned by an administrator', () => {
    beforeEach(async () => {
      availableModelsQueryMock.mockResolvedValue(buildPinnedModelsResponse(MOCK_PINNED_MODEL));
      createComponent({ propsData: { showClassicChatButton: true } });
      await waitForPromises();
    });

    it('does not render the model selection listbox', () => {
      expect(findDropdown().exists()).toBe(false);
    });

    it('renders an enabled dropdown labelled with the compact pinned model name', () => {
      expect(findUnavailableDropdown().props()).toMatchObject({
        toggleText: 'Claude Haiku 4.5',
        disabled: false,
      });
    });

    it('explains that the model is pinned', () => {
      expect(findUnavailableMessage().text()).toBe('Model has been pinned by an administrator.');
    });

    it('offers an on Agentic chat toggle to switch to non-agentic chat', () => {
      expect(findAgenticChatToggle().props('value')).toBe(true);
    });

    it('emits `switch-to-classic` with false when the row is clicked', () => {
      findAgenticChatRow().trigger('click');

      expect(wrapper.emitted('switch-to-classic')).toEqual([[false]]);
    });

    it('emits the pinned model as the current selection', () => {
      expect(wrapper.emitted('change')[0]).toEqual([
        {
          currentModel: { text: 'Claude Haiku 4.5 - Anthropic', value: 'claude_haiku_4_5' },
          defaultModel: DEFAULT_MODEL_ITEM,
        },
      ]);
    });
  });

  describe('when the pinned model is not in the catalog', () => {
    beforeEach(async () => {
      availableModelsQueryMock.mockResolvedValue(
        buildPinnedModelsResponse({ name: 'Self-hosted Mistral', ref: 'self_hosted_mistral' }),
      );
      createComponent();
      await waitForPromises();
    });

    it('labels the dropdown with the pinned model name as given', () => {
      expect(findUnavailableDropdown().props('toggleText')).toBe('Self-hosted Mistral');
    });
  });

  describe('when a model is pinned and the agentic chat toggle is unavailable', () => {
    beforeEach(async () => {
      availableModelsQueryMock.mockResolvedValue(buildPinnedModelsResponse(MOCK_PINNED_MODEL));
      createComponent({ propsData: { showClassicChatButton: false } });
      await waitForPromises();
    });

    it('still explains that the model is pinned', () => {
      expect(findUnavailableMessage().text()).toBe('Model has been pinned by an administrator.');
    });

    it('does not render the agentic chat toggle', () => {
      expect(findAgenticChatRow().exists()).toBe(false);
    });
  });

  describe('classic chat action', () => {
    beforeEach(async () => {
      createComponent({ propsData: { showClassicChatButton: true, disabled: true } });
      await waitForPromises();
    });

    it('passes the classic chat button state down', () => {
      expect(findDropdown().props()).toMatchObject({
        showClassicChatButton: true,
        classicChatButtonDisabled: true,
        disabled: true,
      });
    });

    it('re-emits `switch-to-classic`', () => {
      findDropdown().vm.$emit('switch-to-classic');

      expect(wrapper.emitted('switch-to-classic')).toHaveLength(1);
    });
  });

  describe('in non-agentic mode', () => {
    beforeEach(async () => {
      createComponent({ propsData: { agenticModeEnabled: false, showClassicChatButton: true } });
      await waitForPromises();
    });

    it('renders a plain disclosure dropdown labelled Non-agentic chat', () => {
      expect(findUnavailableDropdown().props('toggleText')).toBe('Non-agentic chat');
    });

    it('does not render the model selection listbox', () => {
      expect(findDropdown().exists()).toBe(false);
    });

    it('offers an off Agentic chat toggle to switch back', () => {
      expect(findAgenticChatToggle().props('value')).toBe(false);
      expect(findAgenticChatToggle().props('label')).toBe('Agentic chat');
    });

    it('explains that model selection is unavailable', () => {
      expect(findUnavailableMessage().text()).toBe(
        'Non-agentic chat does not use model selection.',
      );
    });

    it('emits `switch-to-classic` with the new value when toggled', () => {
      findAgenticChatToggle().vm.$emit('change', true);

      expect(wrapper.emitted('switch-to-classic')).toEqual([[true]]);
    });

    it('emits `switch-to-classic` when the row is clicked', () => {
      findAgenticChatRow().trigger('click');

      expect(wrapper.emitted('switch-to-classic')).toEqual([[true]]);
    });

    it('does not double-emit when the click originates from the switch itself', () => {
      // The switch emits via its own change handler; the row handler must
      // bail out so the state is not flipped a second time. GlToggle is
      // stubbed here, so stand in a real [role="switch"] target.
      const switchEl = document.createElement('button');
      switchEl.setAttribute('role', 'switch');
      findAgenticChatRow().element.appendChild(switchEl);

      switchEl.dispatchEvent(new Event('click', { bubbles: true }));

      expect(wrapper.emitted('switch-to-classic')).toBeUndefined();
    });

    it('does not emit `switch-to-classic` on row click when disabled', async () => {
      createComponent({
        propsData: { agenticModeEnabled: false, showClassicChatButton: true, disabled: true },
      });
      await waitForPromises();

      findAgenticChatRow().trigger('click');

      expect(wrapper.emitted('switch-to-classic')).toBeUndefined();
    });
  });
});
