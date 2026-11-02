import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FeatureSettingsTableHeader from 'ee/ai/shared/feature_settings/feature_settings_table_header.vue';
import ModelSelectionBatchSettingsUpdater from 'ee/ai/model_selection/batch_settings_updater.vue';
import FeatureSettings from 'ee/ai/model_selection/feature_settings.vue';

import {
  mockCodeSuggestionsFeatureSettings,
  mockDuoChatFeatureSettings,
  mockMergeRequestFeatureSettings,
  mockIssueFeatureSettings,
  mockOtherDuoFeaturesSettings,
  mockAiFeatureSettings,
  mockAiFeatureSettingsWithAgenticChat,
  mockDuoAgentPlatformSettings,
  mockAgenticChatFeatureSetting,
} from './mock_data';

describe('FeatureSettings', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(FeatureSettings, {
      propsData: {
        featureSettings: mockAiFeatureSettings,
        isLoading: false,
        ...props,
      },
      provide: {
        modelSelectionAllowlistAvailable: false,
        ...provide,
      },
    });
  };

  const findFeatureSettings = () => wrapper.findComponent(FeatureSettings);
  const findAllHeaders = () => wrapper.findAllComponents(FeatureSettingsTableHeader);
  const findHeaderByTitle = (title) =>
    findAllHeaders().wrappers.find((header) => header.props('title') === title);
  const findDuoChatTable = () => wrapper.findComponentByTestId('duo-chat-table');
  const findCodeSuggestionsTable = () => wrapper.findComponentByTestId('code-suggestions-table');
  const findOtherDuoFeaturesTable = () => wrapper.findComponentByTestId('other-duo-features-table');
  const findDuoIssuesTable = () => wrapper.findComponentByTestId('duo-issues-table');
  const findDuoMergeRequestTable = () => wrapper.findComponentByTestId('duo-merge-requests-table');
  const findDuoAgentPlatformTable = () => wrapper.findComponentByTestId('duo-agent-platform-table');
  const findAgenticChatTable = () => wrapper.findComponentByTestId('duo-agentic-chat-table');

  it('renders the component', () => {
    createComponent();

    expect(findFeatureSettings().exists()).toBe(true);
  });

  it('renders the sections in the expected order', () => {
    createComponent();

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
    it('passes the correct loading state to `FeatureSettingsTableRows`', () => {
      createComponent({ props: { isLoading: true } });

      expect(findCodeSuggestionsTable().props('isLoading')).toBe(true);
      expect(findDuoChatTable().props('isLoading')).toBe(true);
      expect(findDuoMergeRequestTable().props('isLoading')).toBe(true);
      expect(findDuoIssuesTable().props('isLoading')).toBe(true);
      expect(findDuoAgentPlatformTable().props('isLoading')).toBe(true);
      expect(findOtherDuoFeaturesTable().props('isLoading')).toBe(true);
    });
  });

  describe.each`
    section                         | expectedTitle                      | expectedDescription                                                                                                        | findSectionTableFn           | expectedFeatureSettings
    ${'GitLab Duo Agent Platform'}  | ${'GitLab Duo Agent Platform'}     | ${'Multiple AI agents that work in parallel to help you create code, research results, and perform tasks simultaneously.'} | ${findDuoAgentPlatformTable} | ${mockDuoAgentPlatformSettings}
    ${'Duo Chat'}                   | ${'GitLab Duo Chat'}               | ${'An AI assistant that helps users accelerate software development using real-time conversational AI.'}                   | ${findDuoChatTable}          | ${mockDuoChatFeatureSettings}
    ${'Code Suggestions'}           | ${'Code Suggestions'}              | ${'Assists developers by generating and completing code in real-time.'}                                                    | ${findCodeSuggestionsTable}  | ${mockCodeSuggestionsFeatureSettings}
    ${'Duo merge request features'} | ${'GitLab Duo for merge requests'} | ${'AI-native features that help users accomplish tasks during the lifecycle of a merge request.'}                          | ${findDuoMergeRequestTable}  | ${mockMergeRequestFeatureSettings}
    ${'Duo issues'}                 | ${'GitLab Duo for issues'}         | ${'An AI-native feature that generates a summary of discussions on an issue.'}                                             | ${findDuoIssuesTable}        | ${mockIssueFeatureSettings}
    ${'Other Duo features'}         | ${'Other GitLab Duo features'}     | ${'AI-native features that support users outside of Chat or Code Suggestions.'}                                            | ${findOtherDuoFeaturesTable} | ${mockOtherDuoFeaturesSettings}
  `(
    '$section',
    ({ expectedTitle, expectedDescription, findSectionTableFn, expectedFeatureSettings }) => {
      beforeEach(() => {
        createComponent();
      });

      it('renders section and table', () => {
        const header = findHeaderByTitle(expectedTitle);

        expect(header).toBeDefined();
        expect(header.props('description')).toContain(expectedDescription);
        expect(findSectionTableFn().exists()).toBe(true);
      });

      it('passes correct featureSettings to section table', () => {
        expect(findSectionTableFn().props('featureSettings')).toEqual(expectedFeatureSettings);
      });
    },
  );

  describe('feature setting order', () => {
    const buildSetting = (title) => ({ feature: title, title, mainFeature: 'Code Suggestions' });

    const findCodeSuggestionsTitles = () =>
      findCodeSuggestionsTable()
        .props('featureSettings')
        .map((fs) => fs.title);

    it('orders the feature settings within a section alphabetically by title', () => {
      createComponent({
        props: {
          featureSettings: [buildSetting('Code Generation'), buildSetting('Code Completion')],
        },
      });

      expect(findCodeSuggestionsTitles()).toEqual(['Code Completion', 'Code Generation']);
    });
  });

  describe('Agentic Chat section', () => {
    describe('when the model selection allowlist is available', () => {
      beforeEach(() => {
        createComponent({
          props: { featureSettings: mockAiFeatureSettingsWithAgenticChat },
          provide: { modelSelectionAllowlistAvailable: true },
        });
      });

      it('renders the Agentic Chat section table', () => {
        expect(findAgenticChatTable().exists()).toBe(true);
        expect(findAgenticChatTable().props('featureSettings')).toEqual([
          mockAgenticChatFeatureSetting,
        ]);
        expect(findAgenticChatTable().props('showAvailableModelsField')).toBe(true);
      });

      it('renders the sections in the expected order', () => {
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

      it('excludes the Agentic Chat feature from the Agent Platform section', () => {
        expect(findDuoAgentPlatformTable().props('featureSettings')).toEqual(
          mockDuoAgentPlatformSettings,
        );
      });
    });

    describe('when the model selection allowlist is not available', () => {
      beforeEach(() => {
        createComponent({
          props: { featureSettings: mockAiFeatureSettingsWithAgenticChat },
          provide: { modelSelectionAllowlistAvailable: false },
        });
      });

      it('does not render the Agentic Chat section', () => {
        expect(findAgenticChatTable().exists()).toBe(false);
      });

      it('keeps the Agentic Chat feature in the Agent Platform section', () => {
        expect(findDuoAgentPlatformTable().props('featureSettings')).toEqual([
          ...mockDuoAgentPlatformSettings,
          mockAgenticChatFeatureSetting,
        ]);
      });
    });
  });

  describe('bulk update action', () => {
    it('renders a batch updater in the header for multi-feature sections', () => {
      createComponent();

      const codeSuggestionsHeader = findHeaderByTitle('Code Suggestions');

      expect(codeSuggestionsHeader.findComponent(ModelSelectionBatchSettingsUpdater).exists()).toBe(
        true,
      );
    });

    it('does not render a batch updater for single-feature sections', () => {
      createComponent();

      const duoChatHeader = findHeaderByTitle('GitLab Duo Chat');

      expect(duoChatHeader.findComponent(ModelSelectionBatchSettingsUpdater).exists()).toBe(false);
    });

    it('passes the section title as mainFeature and its features to the updater', () => {
      createComponent();

      const updater = findHeaderByTitle('Code Suggestions').findComponent(
        ModelSelectionBatchSettingsUpdater,
      );

      expect(updater.props('mainFeature')).toBe('Code Suggestions');
      expect(updater.props('aiFeatureSettings')).toEqual(mockCodeSuggestionsFeatureSettings);
    });
  });
});
