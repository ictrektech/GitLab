import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import updateNamespaceFeatureSettingsMutation from 'ee/ai/model_selection/graphql/update_ai_namespace_feature_settings.mutation.graphql';
import getAiNamespaceFeatureSettingsQuery from 'ee/ai/model_selection/graphql/get_ai_namepace_feature_settings.query.graphql';
import ModelSelectionBatchSettingsUpdater from 'ee/ai/model_selection/batch_settings_updater.vue';
import ModelSelectDropdown from 'ee/ai/shared/feature_settings/model_select_dropdown.vue';
import GitlabDefaultModelModal from 'ee/ai/model_selection/gitlab_default_model_modal.vue';
import { SUPPRESS_DEFAULT_MODEL_MODAL_KEY } from 'ee/ai/model_selection/constants';

import {
  mockCodeSuggestionsFeatureSettings,
  mockLoadBalancedAgenticChatFeatureSettings,
  mockMixedLoadBalancedFeatureSettings,
} from './mock_data';

Vue.use(VueApollo);
jest.mock('~/alert');

describe('ModelSelectionBatchSettingsUpdater', () => {
  let wrapper;
  let mockApollo;

  const groupId = 'gid://gitlab/Group/1';
  const mockToastShow = jest.fn();

  const updateSuccessHandler = jest.fn().mockResolvedValue({
    data: { aiModelSelectionNamespaceUpdate: { errors: [] } },
  });

  const refetchHandler = jest.fn().mockResolvedValue({
    data: { aiModelSelectionNamespaceSettings: { nodes: mockCodeSuggestionsFeatureSettings } },
  });

  const createComponent = ({
    apolloHandlers = [
      [updateNamespaceFeatureSettingsMutation, updateSuccessHandler],
      [getAiNamespaceFeatureSettingsQuery, refetchHandler],
    ],
    props = {},
  } = {}) => {
    mockApollo = createMockApollo([...apolloHandlers]);
    wrapper = mountExtended(ModelSelectionBatchSettingsUpdater, {
      apolloProvider: mockApollo,
      propsData: {
        aiFeatureSettings: mockCodeSuggestionsFeatureSettings,
        mainFeature: 'Code Suggestions',
        ...props,
      },
      provide: { groupId },
      mocks: { $toast: { show: mockToastShow } },
    });
  };

  const findDropdown = () => wrapper.findComponent(ModelSelectDropdown);
  const findResetButton = () => wrapper.findComponentByTestId('reset-to-default-button');
  const findModal = () => wrapper.findComponent(GitlabDefaultModelModal);
  const selectModel = (ref) => findDropdown().vm.$emit('select', ref);
  const clickReset = () => findResetButton().vm.$emit('click');

  afterEach(() => {
    localStorage.clear();
  });

  describe('bulk update dropdown', () => {
    it('renders a dropdown with a static "Bulk update" label and no latched selection', () => {
      createComponent();

      expect(findDropdown().props('placeholderDropdownText')).toBe('Bulk update');
      expect(findDropdown().props('selectedOption')).toBe(null);
    });

    it('offers the union of models across sub-features, sorted by name', () => {
      createComponent();

      expect(
        findDropdown()
          .props('items')
          .map((item) => item.text),
      ).toEqual(['Claude Haiku 3', 'Claude Sonnet 3.5', 'Claude Sonnet 3.7']);
    });

    it('carries provider, description, and costIndicator on each option', () => {
      createComponent();

      expect(findDropdown().props('items')).toContainEqual({
        value: 'claude_3_haiku_20240307',
        text: 'Claude Haiku 3',
        provider: 'Anthropic',
        description: 'Earlier generation model for high-volume tasks.',
        costIndicator: '$',
      });
    });

    describe('when no models are available', () => {
      beforeEach(() => {
        createComponent({
          props: {
            aiFeatureSettings: [
              { feature: 'f1', title: 'F1', selectableModels: [], defaultModel: null },
            ],
          },
        });
      });

      it('disables the dropdown', () => {
        expect(findDropdown().props('disabled')).toBe(true);
      });
    });
  });

  describe('with a load-balanced default model', () => {
    beforeEach(() => {
      createComponent({
        props: { aiFeatureSettings: mockLoadBalancedAgenticChatFeatureSettings },
      });
    });

    it('does not offer the load-balanced default as a dropdown option', () => {
      const values = findDropdown()
        .props('items')
        .map(({ value }) => value);

      // The GitLab default is applied through "Reset to default", not the dropdown.
      expect(values).not.toContain('__default__duo_agent_platform_agentic_chat');
      expect(values).not.toContain('');
    });

    it('still offers the other selectable models', () => {
      expect(
        findDropdown()
          .props('items')
          .map(({ text }) => text),
      ).toEqual(['Claude Haiku 3', 'Claude Sonnet 3.5', 'Claude Sonnet 3.7']);
    });

    describe('when the section mixes load-balanced and normal sub-features', () => {
      // Section mixes a load-balanced sub-feature with a normal one whose default
      // model (claude_sonnet_3_7_20250219) is also one of its selectable models.
      // That model must not be treated as a load-balanced pseudo default, so bulk
      // updating to it still includes the normal sub-feature.
      beforeEach(() => {
        createComponent({
          props: { aiFeatureSettings: mockMixedLoadBalancedFeatureSettings },
        });
      });

      it('applies a normal sub-feature model whose ref equals its own default', async () => {
        selectModel('claude_sonnet_3_7_20250219');
        await waitForPromises();

        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            groupId,
            features: ['DUO_AGENT_PLATFORM_AGENTIC_CHAT', 'DUO_CHAT'],
            offeredModelRef: 'claude_sonnet_3_7_20250219',
          },
        });
      });
    });

    describe('when the confirmation modal is suppressed and reset is clicked', () => {
      beforeEach(async () => {
        localStorage.setItem(SUPPRESS_DEFAULT_MODEL_MODAL_KEY, 'true');
        createComponent({
          props: { aiFeatureSettings: mockLoadBalancedAgenticChatFeatureSettings },
        });

        await clickReset();
        await waitForPromises();
      });

      it('applies the GitLab default (empty ref) to the feature', () => {
        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            groupId,
            features: ['DUO_AGENT_PLATFORM_AGENTIC_CHAT'],
            offeredModelRef: '',
          },
        });
      });
    });
  });

  describe('when a model is selected', () => {
    beforeEach(async () => {
      createComponent();

      selectModel('claude_3_haiku_20240307');
      await waitForPromises();
    });

    it('emits update-batch-saving-state around the request', () => {
      expect(wrapper.emitted('update-batch-saving-state')).toEqual([[true], [false]]);
    });

    it('re-enables the controls once the request settles', () => {
      expect(findDropdown().props('disabled')).toBe(false);
      expect(findDropdown().props('isLoading')).toBe(false);
      expect(findResetButton().props('disabled')).toBe(false);
    });

    it('applies the model to every compatible sub-feature', () => {
      expect(updateSuccessHandler).toHaveBeenCalledWith({
        input: {
          groupId,
          features: ['CODE_COMPLETIONS', 'CODE_GENERATIONS'],
          offeredModelRef: 'claude_3_haiku_20240307',
        },
      });
    });

    it('refetches the feature settings', () => {
      expect(refetchHandler).toHaveBeenCalled();
    });

    it('shows a success toast', () => {
      expect(mockToastShow).toHaveBeenCalledWith('All Code Suggestions features updated');
    });

    it('does not HTML-escape special characters in the toast message', async () => {
      createComponent({ props: { mainFeature: 'Agents & flows' } });

      selectModel('claude_3_haiku_20240307');
      await waitForPromises();

      expect(mockToastShow).toHaveBeenCalledWith('All Agents & flows features updated');
    });
  });

  describe('while a bulk update is in flight', () => {
    beforeEach(() => {
      createComponent();

      selectModel('claude_3_haiku_20240307');
    });

    it('disables the dropdown and reset button and shows the dropdown loading', () => {
      expect(findDropdown().props('disabled')).toBe(true);
      expect(findDropdown().props('isLoading')).toBe(true);
      expect(findResetButton().props('disabled')).toBe(true);
    });
  });

  describe('when a model only fits some sub-features', () => {
    beforeEach(async () => {
      const partialFeature = {
        feature: 'partial_feature',
        title: 'Partial',
        mainFeature: 'Code Suggestions',
        selectedModel: null,
        defaultModel: {
          ref: 'claude_sonnet_3_7_20250219',
          name: 'Claude Sonnet 3.7',
          modelProvider: 'Anthropic',
        },
        selectableModels: [{ ref: 'gpt_4o', name: 'GPT-4o', modelProvider: 'OpenAI' }],
      };

      createComponent({
        props: { aiFeatureSettings: [...mockCodeSuggestionsFeatureSettings, partialFeature] },
      });

      selectModel('gpt_4o');
      await waitForPromises();
    });

    it('applies only to the compatible subset', () => {
      expect(updateSuccessHandler).toHaveBeenCalledWith({
        input: {
          groupId,
          features: ['PARTIAL_FEATURE'],
          offeredModelRef: 'gpt_4o',
        },
      });
    });

    it('shows a partial-apply toast', () => {
      expect(mockToastShow).toHaveBeenCalledWith('1 of 3 Code Suggestions features updated');
    });
  });

  describe('reset to default', () => {
    it('renders the reset button when every sub-feature has a default model', () => {
      createComponent();

      expect(findResetButton().exists()).toBe(true);
      expect(findResetButton().props('category')).toBe('tertiary');
    });

    it('does not render the reset button when a sub-feature has no default model', () => {
      createComponent({
        props: {
          aiFeatureSettings: [
            { feature: 'f1', title: 'F1', selectableModels: [], defaultModel: null },
          ],
        },
      });

      expect(findResetButton().exists()).toBe(false);
    });

    describe('when the confirmation modal is not suppressed', () => {
      beforeEach(async () => {
        createComponent();

        await clickReset();
        await waitForPromises();
      });

      it('does not run the mutation immediately', () => {
        expect(updateSuccessHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the confirmation modal is suppressed', () => {
      beforeEach(async () => {
        localStorage.setItem(SUPPRESS_DEFAULT_MODEL_MODAL_KEY, 'true');
        createComponent();

        await clickReset();
        await waitForPromises();
      });

      it('applies the GitLab default to all sub-features', () => {
        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            groupId,
            features: ['CODE_COMPLETIONS', 'CODE_GENERATIONS'],
            offeredModelRef: '',
          },
        });
      });
    });

    describe('when the modal confirms', () => {
      beforeEach(async () => {
        createComponent();

        findModal().vm.$emit('confirm-submit', '');
        await waitForPromises();
      });

      it('applies the GitLab default to all sub-features', () => {
        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            groupId,
            features: ['CODE_COMPLETIONS', 'CODE_GENERATIONS'],
            offeredModelRef: '',
          },
        });
      });
    });
  });

  describe('when the update fails', () => {
    it('shows an error alert on a network error', async () => {
      createComponent({
        apolloHandlers: [
          [updateNamespaceFeatureSettingsMutation, jest.fn().mockRejectedValue('ERROR')],
        ],
      });

      selectModel('claude_3_haiku_20240307');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message:
            'An error occurred while updating the Code Suggestions sub-feature settings. Please try again.',
        }),
      );
    });

    it('shows an error alert on a business logic error', async () => {
      const errorHandler = jest.fn().mockResolvedValue({
        data: { aiModelSelectionNamespaceUpdate: { errors: ['nope'] } },
      });

      createComponent({
        apolloHandlers: [[updateNamespaceFeatureSettingsMutation, errorHandler]],
      });

      selectModel('claude_3_haiku_20240307');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message:
            'An error occurred while updating the Code Suggestions sub-feature settings. Please try again.',
        }),
      );
    });
  });

  it('is not full-width (block=false) so it hugs its label', () => {
    createComponent();

    expect(findDropdown().props('block')).toBe(false);
  });
});
