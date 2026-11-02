import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';

import { createAlert } from '~/alert';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import FeatureSettings from 'ee/ai/instance_model_selection/feature_settings/components/feature_settings.vue';
import getAiFeatureSettingsQuery from 'ee/ai/instance_model_selection/feature_settings/graphql/queries/get_ai_feature_settings.query.graphql';
import getSelfHostedModelsQuery from 'ee/ai/instance_model_selection/self_hosted_models/graphql/queries/get_self_hosted_models.query.graphql';
import BetaFeaturesAlert from 'ee/ai/instance_model_selection/shared/components/beta_features_alert.vue';
import FeatureSettingsTableHeader from 'ee/ai/shared/feature_settings/feature_settings_table_header.vue';
import InstanceModelSelectionBatchSettingsUpdater from 'ee/ai/instance_model_selection/feature_settings/components/batch_settings_updater.vue';
import { mockSelfHostedModelsList } from '../self_hosted_models/mock_data';

import {
  mockAiFeatureSettings,
  mockDuoChatFeatureSettings,
  mockCodeSuggestionsFeatureSettings,
} from './mock_data';

Vue.use(VueApollo);

jest.mock('~/alert');

describe('FeatureSettings', () => {
  let wrapper;

  const getAiFeatureSettingsSuccessHandler = jest.fn().mockResolvedValue({
    data: {
      aiFeatureSettings: {
        nodes: mockAiFeatureSettings,
        errors: [],
      },
    },
  });

  const getSelfHostedModelsEmptyHandler = jest.fn().mockResolvedValue({
    data: {
      aiSelfHostedModels: {
        nodes: [],
      },
    },
  });

  const createComponent = ({
    apolloHandlers = [
      [getAiFeatureSettingsQuery, getAiFeatureSettingsSuccessHandler],
      [getSelfHostedModelsQuery, getSelfHostedModelsEmptyHandler],
    ],
    injectedProps = {},
  } = {}) => {
    const mockApollo = createMockApollo([...apolloHandlers]);

    wrapper = shallowMountExtended(FeatureSettings, {
      apolloProvider: mockApollo,
      provide: {
        betaModelsEnabled: true,
        canManageSelfHostedModels: true,
        canManageDapSelfHostedModels: true,
        modelSelectionAllowlistAvailable: false,
        ...injectedProps,
      },
    });
  };

  const findFeatureSettings = () => wrapper.findComponent(FeatureSettings);
  const findDuoChatTable = () => wrapper.findComponentByTestId('duo-chat-table');
  const findCodeSuggestionsTable = () => wrapper.findComponentByTestId('code-suggestions-table');
  const findOtherDuoFeaturesTable = () => wrapper.findComponentByTestId('other-duo-features-table');
  const findDuoMergeRequestTable = () => wrapper.findComponentByTestId('duo-merge-requests-table');
  const findDuoIssuesTable = () => wrapper.findComponentByTestId('duo-issues-table');
  const findDuoAgentPlatformTable = () => wrapper.findComponentByTestId('duo-agent-platform-table');
  const findAgenticChatTable = () => wrapper.findComponentByTestId('duo-agentic-chat-table');
  const findAllHeaders = () => wrapper.findAllComponents(FeatureSettingsTableHeader);
  const findHeaderByTitle = (title) =>
    findAllHeaders().wrappers.find((header) => header.props('title') === title);
  const findBetaAlert = () => wrapper.findComponent(BetaFeaturesAlert);

  beforeEach(async () => {
    createComponent();

    await waitForPromises();
  });

  it('renders the component', () => {
    expect(findFeatureSettings().exists()).toBe(true);
  });

  it('renders the sections in the expected order', () => {
    expect(findAllHeaders().wrappers.map((header) => header.props('title'))).toEqual([
      'GitLab Duo Agent Platform',
      'GitLab Duo Chat',
      'Code Suggestions',
      'GitLab Duo for merge requests',
      'GitLab Duo for issues',
      'Other GitLab Duo features',
    ]);
  });

  describe('when feature settings data is loading', () => {
    it('passes the correct loading state to FeatureSettingsTable', () => {
      createComponent();

      [findCodeSuggestionsTable, findDuoChatTable].forEach((findTableFn) => {
        expect(findTableFn().props('isLoading')).toBe(true);
      });
    });
  });

  describe('when feature settings query is successful', () => {
    beforeEach(async () => {
      createComponent({
        injectedProps: {
          modelSelectionAllowlistAvailable: true,
        },
      });
      await waitForPromises();
    });

    describe.each`
      section                         | expectedSectionTitle               | expectedDescription                                                                                                        | findSectionTableFn           | expectedTitlesAndReleaseStates
      ${'GitLab Duo Agent Platform'}  | ${'GitLab Duo Agent Platform'}     | ${'Multiple AI agents that work in parallel to help you create code, research results, and perform tasks simultaneously.'} | ${findDuoAgentPlatformTable} | ${[['GitLab Duo Agent Platform - all agents', 'EXPERIMENT']]}
      ${'Agentic Chat'}               | ${'GitLab Duo Agentic Chat'}       | ${'An AI chat assistant that autonomously uses tools and performs multi-step tasks to answer complex questions.'}          | ${findAgenticChatTable}      | ${[['GitLab Duo Agentic Chat', 'GA']]}
      ${'Duo Chat'}                   | ${'GitLab Duo Chat'}               | ${'An AI assistant that helps users accelerate software development using real-time conversational AI.'}                   | ${findDuoChatTable}          | ${[['General Chat', 'GA'], ['Explain Code', 'BETA'], ['Troubleshoot Job', 'EXPERIMENT']]}
      ${'Code Suggestions'}           | ${'Code Suggestions'}              | ${'Assists developers by generating and completing code in real-time.'}                                                    | ${findCodeSuggestionsTable}  | ${[['Code Completion', 'GA'], ['Code Generation', 'GA']]}
      ${'Duo merge request features'} | ${'GitLab Duo for merge requests'} | ${'AI-native features that help users accomplish tasks during the lifecycle of a merge request.'}                          | ${findDuoMergeRequestTable}  | ${[['Code Review Summary', 'BETA'], ['Merge Commit Message Generation', 'BETA']]}
      ${'Duo issues'}                 | ${'GitLab Duo for issues'}         | ${'An AI-native feature that generates a summary of discussions on an issue.'}                                             | ${findDuoIssuesTable}        | ${[['Discussion Summary', 'BETA']]}
      ${'Other Duo features'}         | ${'Other GitLab Duo features'}     | ${'AI-native features that support users outside of Chat or Code Suggestions.'}                                            | ${findOtherDuoFeaturesTable} | ${[['GitLab Duo for CLI', 'BETA']]}
    `(
      '$section',
      ({
        expectedSectionTitle,
        expectedDescription,
        findSectionTableFn,
        expectedTitlesAndReleaseStates,
      }) => {
        it('renders section and table', () => {
          const header = findHeaderByTitle(expectedSectionTitle);

          expect(header).toBeDefined();

          const msg = header.props('description');
          expect(msg).toContain(expectedDescription);
          if (expectedSectionTitle === 'GitLab Duo Chat') {
            expect(msg).toContain('This setting is for regular Duo Chat only.');
          }
          expect(findSectionTableFn().exists()).toBe(true);
        });

        it('passes feature settings sorted by release state, then alphabetically by title', () => {
          expect(
            findSectionTableFn()
              .props('featureSettings')
              .map((fs) => [fs.title, fs.releaseState]),
          ).toEqual(expectedTitlesAndReleaseStates);
        });
      },
    );

    describe('when the user can not manage DAP self-hosted models', () => {
      it('does not show the `GitLab Duo Agent Platform` or `GitLab Duo Agentic Chat` sections', () => {
        createComponent({
          injectedProps: {
            canManageDapSelfHostedModels: false,
          },
        });

        expect(findDuoAgentPlatformTable().exists()).toBe(false);
        expect(findAgenticChatTable().exists()).toBe(false);
      });
    });

    describe('when the model selection allowlist is unavailable', () => {
      // This is the case for self-managed offline instances: with no online
      // cloud license the backend policy resolves `modelSelectionAllowlistAvailable`
      // to false, so the `Available models` column must not be shown at all.
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('does not show the `GitLab Duo Agentic Chat` section', () => {
        expect(findAgenticChatTable().exists()).toBe(false);
      });

      it('includes agentic chat feature in the `GitLab Duo Agent Platform` section', () => {
        expect(
          findDuoAgentPlatformTable()
            .props('featureSettings')
            .map((fs) => fs.feature),
        ).toContain('duo_agent_platform_agentic_chat');
      });
    });

    describe('when the model selection allowlist is available', () => {
      beforeEach(async () => {
        createComponent({
          injectedProps: {
            modelSelectionAllowlistAvailable: true,
          },
        });
        await waitForPromises();
      });

      it('shows the `Agentic Chat` section separately', () => {
        expect(findAgenticChatTable().exists()).toBe(true);
      });

      it('renders table sections in the expected order', () => {
        expect(findAllHeaders().wrappers.map((header) => header.props('title'))).toEqual([
          'GitLab Duo Agent Platform',
          'GitLab Duo Agentic Chat',
          'GitLab Duo Chat',
          'Code Suggestions',
          'GitLab Duo for merge requests',
          'GitLab Duo for issues',
          'Other GitLab Duo features',
        ]);
      });

      it('excludes agentic chat from the `GitLab Duo Agent Platform` section', () => {
        expect(
          findDuoAgentPlatformTable()
            .props('featureSettings')
            .map((fs) => fs.feature),
        ).not.toContain('duo_agent_platform_agentic_chat');
      });

      it('passes showAvailableModelsField=true only to the `GitLab Duo Agentic Chat` table', () => {
        expect(findAgenticChatTable().props('showAvailableModelsField')).toBe(true);
        expect(findDuoAgentPlatformTable().props('showAvailableModelsField')).toBe(false);
        expect(findCodeSuggestionsTable().props('showAvailableModelsField')).toBe(false);
      });
    });

    it('does not render optional sections when they have no feature settings', async () => {
      const alwaysShownFeatureSettings = [
        ...mockDuoChatFeatureSettings,
        ...mockCodeSuggestionsFeatureSettings,
      ];
      const getFeatureSettingsExcludingOtherDuoSuccessHandler = jest.fn().mockResolvedValue({
        data: {
          aiFeatureSettings: {
            nodes: alwaysShownFeatureSettings,
            errors: [],
          },
        },
      });

      createComponent({
        apolloHandlers: [
          [getAiFeatureSettingsQuery, getFeatureSettingsExcludingOtherDuoSuccessHandler],
          [getSelfHostedModelsQuery, getSelfHostedModelsEmptyHandler],
        ],
      });
      await waitForPromises();

      expect(findAllHeaders()).toHaveLength(2);
      expect(findOtherDuoFeaturesTable().exists()).toBe(false);
      expect(findDuoAgentPlatformTable().exists()).toBe(false);
      expect(findDuoIssuesTable().exists()).toBe(false);
      expect(findDuoMergeRequestTable().exists()).toBe(false);
    });
  });

  describe('bulk update action', () => {
    const findUpdaterInHeader = (title) =>
      findHeaderByTitle(title).findComponent(InstanceModelSelectionBatchSettingsUpdater);

    beforeEach(async () => {
      createComponent({ injectedProps: { modelSelectionAllowlistAvailable: true } });
      await waitForPromises();
    });

    it('renders a batch updater in the header for multi-feature sections', () => {
      expect(findUpdaterInHeader('GitLab Duo Chat').exists()).toBe(true);
    });

    it('does not render a batch updater for single-feature sections', () => {
      expect(findUpdaterInHeader('GitLab Duo for issues').exists()).toBe(false);
    });

    it('does not render a batch updater for the available-models (agentic chat) section', () => {
      expect(findUpdaterInHeader('GitLab Duo Agentic Chat').exists()).toBe(false);
    });

    it('passes the section title as mainFeature and its features to the updater', () => {
      const updater = findUpdaterInHeader('GitLab Duo Chat');

      expect(updater.props('mainFeature')).toBe('GitLab Duo Chat');
      expect(updater.props('aiFeatureSettings')).toEqual(
        findDuoChatTable().props('featureSettings'),
      );
    });

    it('forwards the updater saving state to the section table', async () => {
      expect(findDuoChatTable().props('batchUpdateIsSaving')).toBe(false);

      findUpdaterInHeader('GitLab Duo Chat').vm.$emit('update-batch-saving-state', true);
      await nextTick();

      expect(findDuoChatTable().props('batchUpdateIsSaving')).toBe(true);
    });
  });

  describe('beta features alert', () => {
    describe.each`
      betaModelsEnabled | canManageSelfHostedModels | visible
      ${false}          | ${true}                   | ${true}
      ${false}          | ${false}                  | ${false}
      ${true}           | ${true}                   | ${false}
      ${true}           | ${false}                  | ${false}
    `(
      'betaModelsEnabled=$betaModelsEnabled, canManageSelfHostedModels=$canManageSelfHostedModels',
      ({ betaModelsEnabled, canManageSelfHostedModels, visible }) => {
        it(`${visible ? 'displays' : 'hides'} beta features alert`, () => {
          createComponent({
            injectedProps: {
              betaModelsEnabled,
              canManageSelfHostedModels,
            },
          });

          if (visible) {
            expect(findBetaAlert().exists()).toBe(true);
            expect(findBetaAlert().props('message')).toBe(
              'More features are available in beta. You can %{linkStart}turn on AI-native beta features%{linkEnd}.',
            );
          } else {
            expect(findBetaAlert().exists()).toBe(false);
          }
        });
      },
    );
  });

  describe('when the API request is unsuccessful', () => {
    describe('due to a general error', () => {
      it('displays an error message for feature settings', async () => {
        createComponent({
          apolloHandlers: [
            [getAiFeatureSettingsQuery, jest.fn().mockRejectedValue('ERROR')],
            [getSelfHostedModelsQuery, getSelfHostedModelsEmptyHandler],
          ],
        });

        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'An error occurred while loading the AI feature settings. Please try again.',
          }),
        );
      });
    });

    describe('due to a business logic error', () => {
      const getAiFeatureSettingsErrorHandler = jest.fn().mockResolvedValue({
        data: {
          aiFeatureSettings: {
            errors: ['An error occured'],
          },
        },
      });

      it('displays an error message for feature settings', async () => {
        createComponent({
          apolloHandlers: [
            [getAiFeatureSettingsQuery, getAiFeatureSettingsErrorHandler],
            [getSelfHostedModelsQuery, getSelfHostedModelsEmptyHandler],
          ],
        });

        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'An error occurred while loading the AI feature settings. Please try again.',
          }),
        );
      });
    });
  });

  describe('Managed by column', () => {
    const selfHostedModelsSuccessHandler = jest.fn().mockResolvedValue({
      data: { aiSelfHostedModels: { nodes: mockSelfHostedModelsList } },
    });
    const selfHostedModelsErrorHandler = jest.fn().mockRejectedValue(new Error('failed'));
    const buildFeatureSettingsHandler = (nodes) =>
      jest.fn().mockResolvedValue({ data: { aiFeatureSettings: { nodes, errors: [] } } });
    const featureSettingsWithGitlabModelsHandler =
      buildFeatureSettingsHandler(mockAiFeatureSettings);
    // Offline instances have no GitLab-managed models.
    const offlineFeatureSettingsHandler = buildFeatureSettingsHandler(
      mockAiFeatureSettings.map((setting) => ({
        ...setting,
        defaultGitlabModel: null,
        validGitlabModels: { nodes: [] },
      })),
    );

    const createWithHandlers = (featureSettingsHandler, selfHostedModelsHandler) =>
      createComponent({
        apolloHandlers: [
          [getAiFeatureSettingsQuery, featureSettingsHandler],
          [getSelfHostedModelsQuery, selfHostedModelsHandler],
        ],
      });

    describe('while loading', () => {
      beforeEach(() => {
        createWithHandlers(featureSettingsWithGitlabModelsHandler, selfHostedModelsSuccessHandler);
      });

      it('hides the column', () => {
        expect(findCodeSuggestionsTable().props('isLoading')).toBe(true);
        expect(findCodeSuggestionsTable().props('showManagedByColumn')).toBe(false);
      });
    });

    it.each`
      scenario                                                     | featureSettingsHandler                    | selfHostedModelsHandler            | expected
      ${'there are self-hosted and GitLab-managed models'}         | ${featureSettingsWithGitlabModelsHandler} | ${selfHostedModelsSuccessHandler}  | ${true}
      ${'there are only self-hosted models, such as when offline'} | ${offlineFeatureSettingsHandler}          | ${selfHostedModelsSuccessHandler}  | ${false}
      ${'there are only GitLab-managed models'}                    | ${featureSettingsWithGitlabModelsHandler} | ${getSelfHostedModelsEmptyHandler} | ${false}
      ${'the self-hosted models query fails'}                      | ${featureSettingsWithGitlabModelsHandler} | ${selfHostedModelsErrorHandler}    | ${false}
    `(
      'sets showManagedByColumn=$expected when $scenario',
      async ({ featureSettingsHandler, selfHostedModelsHandler, expected }) => {
        createWithHandlers(featureSettingsHandler, selfHostedModelsHandler);
        await waitForPromises();

        expect(findCodeSuggestionsTable().props('isLoading')).toBe(false);
        expect(findCodeSuggestionsTable().props('showManagedByColumn')).toBe(expected);
      },
    );
  });
});
