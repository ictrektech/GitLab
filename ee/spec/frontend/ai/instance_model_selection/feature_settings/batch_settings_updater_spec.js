import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import updateAiFeatureSettings from 'ee/ai/instance_model_selection/feature_settings/graphql/mutations/update_ai_feature_setting.mutation.graphql';
import getAiFeatureSettingsQuery from 'ee/ai/instance_model_selection/feature_settings/graphql/queries/get_ai_feature_settings.query.graphql';
import InstanceModelSelectionBatchSettingsUpdater from 'ee/ai/instance_model_selection/feature_settings/components/batch_settings_updater.vue';
import ModelSelectDropdown from 'ee/ai/shared/feature_settings/model_select_dropdown.vue';
import GitlabManagedModelsDisclaimerModal from 'ee/ai/instance_model_selection/feature_settings/components/gitlab_managed_models_disclaimer_modal.vue';
import {
  mockDuoChatFeatureSettings,
  mockInstanceModelSelectionFeatureSettings,
  mockGitlabManagedModels,
  mockLoadBalancedDefaultModel,
  mockModelsWithLoadBalancedDefault,
} from './mock_data';

Vue.use(VueApollo);
jest.mock('~/alert');

describe('InstanceModelSelectionBatchSettingsUpdater', () => {
  let wrapper;
  let mockApollo;

  const mockToastShow = jest.fn();

  const updateSuccessHandler = jest.fn().mockResolvedValue({
    data: { aiFeatureSettingUpdate: { errors: [] } },
  });

  const refetchHandler = jest.fn().mockResolvedValue({
    data: { aiFeatureSettings: { nodes: mockDuoChatFeatureSettings } },
  });

  const createComponent = ({
    apolloHandlers = [
      [updateAiFeatureSettings, updateSuccessHandler],
      [getAiFeatureSettingsQuery, refetchHandler],
    ],
    props = {},
    provide = {},
  } = {}) => {
    mockApollo = createMockApollo([...apolloHandlers]);
    wrapper = mountExtended(InstanceModelSelectionBatchSettingsUpdater, {
      apolloProvider: mockApollo,
      propsData: {
        aiFeatureSettings: mockDuoChatFeatureSettings,
        mainFeature: 'GitLab Duo Chat',
        ...props,
      },
      provide: {
        canManageInstanceModelSelection: true,
        ...provide,
      },
      mocks: { $toast: { show: mockToastShow } },
    });
  };

  const findDropdown = () => wrapper.findComponent(ModelSelectDropdown);
  const findResetButton = () => wrapper.findComponentByTestId('reset-to-default-button');
  const findDisclaimerModal = () => wrapper.findComponent(GitlabManagedModelsDisclaimerModal);
  const selectModel = (value) => findDropdown().vm.$emit('select', value);

  describe('bulk update dropdown', () => {
    it('renders a "Bulk update" dropdown with no latched selection', () => {
      createComponent();

      expect(findDropdown().props('placeholderDropdownText')).toBe('Bulk update');
      expect(findDropdown().props('selectedOption')).toBe(null);
      expect(findDropdown().props('block')).toBe(false);
    });

    it('groups self-hosted and GitLab-managed models', () => {
      createComponent({ props: { aiFeatureSettings: mockInstanceModelSelectionFeatureSettings } });

      const groupNames = findDropdown()
        .props('items')
        .map((group) => group.text);

      expect(groupNames).toEqual(['Self-hosted models', 'GitLab-managed models']);
    });

    it('carries releaseState on self-hosted options so Beta models can be badged', () => {
      createComponent();

      const [selfHostedGroup] = findDropdown().props('items');

      expect(selfHostedGroup.options).toContainEqual(
        expect.objectContaining({
          value: 'gid://gitlab/Ai::SelfHostedModel/2',
          text: 'Model 2 (Code Llama)',
          releaseState: 'BETA',
        }),
      );
    });

    it('carries provider, description, and costIndicator on GitLab-managed options', () => {
      createComponent({ props: { aiFeatureSettings: mockInstanceModelSelectionFeatureSettings } });

      const gitlabManagedGroup = findDropdown()
        .props('items')
        .find((group) => group.text === 'GitLab-managed models');

      expect(gitlabManagedGroup.options).toContainEqual({
        value: 'claude_sonnet_4_20250514',
        text: 'Claude Sonnet 4.0',
        provider: 'Anthropic',
        description: 'Fast, cost-effective responses',
        costIndicator: '$$$',
      });
    });

    describe('when no models are available for the section', () => {
      beforeEach(() => {
        createComponent({
          props: {
            aiFeatureSettings: [
              {
                feature: 'f1',
                title: 'F1',
                validModels: { nodes: [] },
                validGitlabModels: { nodes: [] },
                defaultGitlabModel: null,
              },
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
    const loadBalancedFeature = {
      feature: 'duo_agent_platform_agentic_chat',
      title: 'GitLab Duo Agentic Chat',
      mainFeature: 'GitLab Duo Agent Platform',
      provider: 'vendored',
      selfHostedModel: null,
      validModels: { nodes: [] },
      gitlabModel: mockLoadBalancedDefaultModel,
      defaultGitlabModel: mockLoadBalancedDefaultModel,
      validGitlabModels: { nodes: mockModelsWithLoadBalancedDefault },
    };

    const findGitlabManagedOptions = () =>
      findDropdown()
        .props('items')
        .find((group) => group.text === 'GitLab-managed models').options;

    beforeEach(() => {
      createComponent({
        props: { aiFeatureSettings: [loadBalancedFeature] },
      });
    });

    it('does not offer the load-balanced default as a dropdown option', () => {
      const values = findGitlabManagedOptions().map(({ value }) => value);

      // The GitLab default is applied through "Reset to default", not the dropdown.
      expect(values).not.toContain('__default__duo_agent_platform_agentic_chat');
      expect(values).not.toContain('');
    });

    it('still offers the other GitLab-managed models', () => {
      expect(findGitlabManagedOptions().map(({ text }) => text)).toEqual(
        mockGitlabManagedModels.map(({ name }) => name),
      );
    });

    describe('when the section mixes load-balanced and normal sub-features', () => {
      // Section mixes a load-balanced sub-feature with a normal one whose default
      // GitLab-managed model (claude_sonnet_4_20250514) is also one of its valid
      // models. That model must not be treated as a load-balanced pseudo default,
      // so bulk updating to it still includes the normal sub-feature.
      const normalFeature = {
        feature: 'duo_chat',
        title: 'General Chat',
        mainFeature: 'GitLab Duo Chat',
        provider: 'vendored',
        selfHostedModel: null,
        validModels: { nodes: [] },
        gitlabModel: mockGitlabManagedModels[0],
        defaultGitlabModel: mockGitlabManagedModels[0],
        validGitlabModels: { nodes: mockGitlabManagedModels },
      };

      beforeEach(() => {
        createComponent({
          props: { aiFeatureSettings: [loadBalancedFeature, normalFeature] },
        });
      });

      it('applies a normal sub-feature model whose ref equals its own default', async () => {
        selectModel('claude_sonnet_4_20250514');
        findDisclaimerModal().vm.$emit('confirm', 'claude_sonnet_4_20250514');
        await waitForPromises();

        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            features: ['DUO_AGENT_PLATFORM_AGENTIC_CHAT', 'DUO_CHAT'],
            provider: 'VENDORED',
            aiSelfHostedModelId: null,
            offeredModelRef: 'claude_sonnet_4_20250514',
          },
        });
      });
    });

    describe('when reset to default is confirmed', () => {
      beforeEach(async () => {
        await findResetButton().vm.$emit('click');
        findDisclaimerModal().vm.$emit('confirm', '');
        await waitForPromises();
      });

      it('applies the GitLab default (empty ref) to the feature', () => {
        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            features: ['DUO_AGENT_PLATFORM_AGENTIC_CHAT'],
            provider: 'VENDORED',
            aiSelfHostedModelId: null,
            offeredModelRef: '',
          },
        });
      });
    });
  });

  describe('when a self-hosted model is selected', () => {
    beforeEach(async () => {
      createComponent();

      selectModel('gid://gitlab/Ai::SelfHostedModel/1');
      await waitForPromises();
    });

    it('applies the self-hosted model to every compatible sub-feature', () => {
      expect(updateSuccessHandler).toHaveBeenCalledWith({
        input: {
          features: ['DUO_CHAT_TROUBLESHOOT_JOB', 'DUO_CHAT', 'DUO_CHAT_EXPLAIN_CODE'],
          provider: 'SELF_HOSTED',
          aiSelfHostedModelId: 'gid://gitlab/Ai::SelfHostedModel/1',
          offeredModelRef: null,
        },
      });
    });

    it('shows a success toast', () => {
      expect(mockToastShow).toHaveBeenCalledWith('All GitLab Duo Chat features updated');
    });

    it('re-enables the controls once the request settles', () => {
      expect(findDropdown().props('disabled')).toBe(false);
      expect(findDropdown().props('isLoading')).toBe(false);
    });

    it('does not HTML-escape special characters in the toast message', async () => {
      createComponent({ props: { mainFeature: 'Agents & flows' } });

      selectModel('gid://gitlab/Ai::SelfHostedModel/1');
      await waitForPromises();

      expect(mockToastShow).toHaveBeenCalledWith('All Agents & flows features updated');
    });
  });

  describe('while a bulk update is in flight', () => {
    beforeEach(() => {
      createComponent();

      selectModel('gid://gitlab/Ai::SelfHostedModel/1');
    });

    it('disables the dropdown and shows it loading', () => {
      expect(findDropdown().props('disabled')).toBe(true);
      expect(findDropdown().props('isLoading')).toBe(true);
    });
  });

  describe('when a GitLab-managed model is selected', () => {
    beforeEach(() => {
      createComponent({ props: { aiFeatureSettings: mockInstanceModelSelectionFeatureSettings } });

      selectModel(mockGitlabManagedModels[0].ref);
    });

    it('opens the disclaimer modal instead of applying immediately', () => {
      expect(updateSuccessHandler).not.toHaveBeenCalled();
    });

    describe('when the disclaimer is confirmed', () => {
      beforeEach(async () => {
        findDisclaimerModal().vm.$emit('confirm', mockGitlabManagedModels[0].ref);
        await waitForPromises();
      });

      it('applies the GitLab-managed model as a vendored provider', () => {
        expect(updateSuccessHandler).toHaveBeenCalledWith({
          input: {
            features: mockInstanceModelSelectionFeatureSettings.map((fs) =>
              fs.feature.toUpperCase(),
            ),
            provider: 'VENDORED',
            aiSelfHostedModelId: null,
            offeredModelRef: mockGitlabManagedModels[0].ref,
          },
        });
      });
    });
  });

  describe('when a model only fits some sub-features', () => {
    beforeEach(async () => {
      const partialFeature = {
        feature: 'partial_feature',
        title: 'Partial',
        validModels: { nodes: [] },
        validGitlabModels: { nodes: [] },
        defaultGitlabModel: null,
      };

      createComponent({
        props: { aiFeatureSettings: [...mockDuoChatFeatureSettings, partialFeature] },
      });

      selectModel('gid://gitlab/Ai::SelfHostedModel/1');
      await waitForPromises();
    });

    it('applies only to the compatible subset', () => {
      expect(updateSuccessHandler).toHaveBeenCalledWith({
        input: {
          features: ['DUO_CHAT_TROUBLESHOOT_JOB', 'DUO_CHAT', 'DUO_CHAT_EXPLAIN_CODE'],
          provider: 'SELF_HOSTED',
          aiSelfHostedModelId: 'gid://gitlab/Ai::SelfHostedModel/1',
          offeredModelRef: null,
        },
      });
    });

    it('shows a partial-apply toast', () => {
      expect(mockToastShow).toHaveBeenCalledWith('3 of 4 GitLab Duo Chat features updated');
    });
  });

  describe('reset to default', () => {
    it('renders the reset button when every sub-feature has a default GitLab model', () => {
      createComponent({ props: { aiFeatureSettings: mockInstanceModelSelectionFeatureSettings } });

      expect(findResetButton().exists()).toBe(true);
      expect(findResetButton().props('category')).toBe('tertiary');
    });

    it('does not render the reset button when a sub-feature has no default GitLab model', () => {
      createComponent();

      expect(findResetButton().exists()).toBe(false);
    });

    it('does not render the reset button when the user cannot manage instance model selection', () => {
      createComponent({
        props: { aiFeatureSettings: mockInstanceModelSelectionFeatureSettings },
        provide: { canManageInstanceModelSelection: false },
      });

      expect(findResetButton().exists()).toBe(false);
    });

    describe('when clicked', () => {
      beforeEach(async () => {
        createComponent({
          props: { aiFeatureSettings: mockInstanceModelSelectionFeatureSettings },
        });

        await findResetButton().vm.$emit('click');
      });

      it('opens the disclaimer modal instead of resetting immediately', () => {
        expect(updateSuccessHandler).not.toHaveBeenCalled();
      });

      describe('when the disclaimer is confirmed', () => {
        beforeEach(async () => {
          findDisclaimerModal().vm.$emit('confirm', '');
          await waitForPromises();
        });

        it('resets all sub-features to the GitLab default (vendored, empty ref)', () => {
          expect(updateSuccessHandler).toHaveBeenCalledWith({
            input: {
              features: mockInstanceModelSelectionFeatureSettings.map((fs) =>
                fs.feature.toUpperCase(),
              ),
              provider: 'VENDORED',
              aiSelfHostedModelId: null,
              offeredModelRef: '',
            },
          });
        });
      });
    });
  });

  describe('when the update fails', () => {
    it('shows an error alert on a network error', async () => {
      createComponent({
        apolloHandlers: [[updateAiFeatureSettings, jest.fn().mockRejectedValue('ERROR')]],
      });

      selectModel('gid://gitlab/Ai::SelfHostedModel/1');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message:
            'An error occurred while updating the GitLab Duo Chat sub-feature settings. Please try again.',
        }),
      );
    });

    it('shows an error alert on a business logic error', async () => {
      const errorHandler = jest.fn().mockResolvedValue({
        data: { aiFeatureSettingUpdate: { errors: ['nope'] } },
      });

      createComponent({ apolloHandlers: [[updateAiFeatureSettings, errorHandler]] });

      selectModel('gid://gitlab/Ai::SelfHostedModel/1');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message:
            'An error occurred while updating the GitLab Duo Chat sub-feature settings. Please try again.',
        }),
      );
    });
  });
});
