import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ModelSelectionFeatureSettingsTable from 'ee/ai/model_selection/feature_settings_table.vue';
import ModelAllowListSelector from 'ee/ai/model_selection/model_allow_list_selector.vue';
import ModelSelector from 'ee/ai/model_selection/model_selector.vue';
import AvailableModelsRow from 'ee/ai/shared/feature_settings/available_models_row.vue';
import BaseFeatureSettingsTable from 'ee/ai/shared/feature_settings/base_feature_settings_table.vue';

import {
  mockCodeSuggestionsFeatureSettings,
  mockAgenticChatFeatureSetting,
  mockDuoDeveloperFeatureSetting,
} from './mock_data';

describe('ModelSelectionFeatureSettingsTable', () => {
  let wrapper;
  const groupId = 'gid://gitlab/Group/1';

  const createComponent = (props = {}, provide = {}) => {
    wrapper = mountExtended(ModelSelectionFeatureSettingsTable, {
      propsData: {
        featureSettings: mockCodeSuggestionsFeatureSettings,
        isLoading: false,
        ...props,
      },
      provide: {
        groupId,
        ...provide,
      },
    });
  };

  const findFeatureSettingsTable = () => wrapper.findComponent(ModelSelectionFeatureSettingsTable);
  const findBaseTable = () => wrapper.findComponent(BaseFeatureSettingsTable);
  const findTableRows = () => findFeatureSettingsTable().findAllComponents('tbody > tr');
  const findTableHeaders = () => findFeatureSettingsTable().findAllComponents('thead > tr');
  const findRowFeatureNameByIdx = (idx) => findTableRows().at(idx).findAll('td').at(0);
  const findModelSelectorByIdx = (idx) => findTableRows().at(idx).findComponent(ModelSelector);
  const findAvailableModelsRow = () => wrapper.findComponent(AvailableModelsRow);
  const findModelAllowListSelector = () => wrapper.findComponent(ModelAllowListSelector);

  it('renders the component', () => {
    createComponent();

    expect(findFeatureSettingsTable().exists()).toBe(true);
  });

  describe('table items', () => {
    const findItemModel = () => findBaseTable().props('items')[0].model;

    const featureSetting = mockCodeSuggestionsFeatureSettings[0]; // selects the default 'Claude Sonnet 3.7'
    // A reset-to-default selection comes back with an empty ref and name, not null.
    const resetToDefault = { ...featureSetting, selectedModel: { ref: '', name: '' } };

    it.each`
      description                              | setting                                      | glFeatures                             | expected
      ${'a selected model'}                    | ${featureSetting}                            | ${{}}                                  | ${'Claude Sonnet 3.7'}
      ${'the GitLab default model'}            | ${resetToDefault}                            | ${{}}                                  | ${'Claude Sonnet 3.7 - Default'}
      ${'Duo Developer with model routing'}    | ${mockDuoDeveloperFeatureSetting}            | ${{ duoDeveloperModelRouting: true }}  | ${'Auto'}
      ${'Duo Developer without model routing'} | ${mockDuoDeveloperFeatureSetting}            | ${{ duoDeveloperModelRouting: false }} | ${'Claude Sonnet 4.0 - Default'}
      ${'no selection and no default model'}   | ${{ ...resetToDefault, defaultModel: null }} | ${{}}                                  | ${''}
    `(
      'sets `model` to the text shown in the model selector for $description',
      ({ setting, glFeatures, expected }) => {
        createComponent({ featureSettings: [setting] }, { glFeatures });

        expect(findItemModel()).toBe(expected);
      },
    );
  });

  describe('rows', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders column headers', () => {
      const headers = findTableHeaders().at(0).findAll('th');

      // The Feature and Model columns are sortable, so their headers also contain the sort affordance text.
      expect(headers.at(0).text()).toContain('Feature');
      expect(headers.at(1).text()).toContain('Model');
    });

    it('renders row data for each feature setting', () => {
      expect(findTableRows()).toHaveLength(mockCodeSuggestionsFeatureSettings.length);
    });

    it('renders the feature name', () => {
      expect(findRowFeatureNameByIdx(0).text()).toBe('Code Completion');
      expect(findRowFeatureNameByIdx(1).text()).toBe('Code Generation');
    });

    it('renders the model select dropdown and passes the correct props', () => {
      ['Claude Sonnet 3.7', 'Claude Sonnet 3.7 - Default'].forEach((model, idx) => {
        expect(findModelSelectorByIdx(idx).props()).toEqual({
          aiFeatureSetting: {
            ...mockCodeSuggestionsFeatureSettings[idx],
            model,
          },
          batchUpdateIsSaving: false,
        });
      });
    });

    it('forwards the batchUpdateIsSaving prop to each model selector', () => {
      createComponent({ batchUpdateIsSaving: true });

      [0, 1].forEach((idx) => {
        expect(findModelSelectorByIdx(idx).props('batchUpdateIsSaving')).toBe(true);
      });
    });
  });

  describe('available models field', () => {
    describe('when `showAvailableModelsField` is false (default)', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders only the feature and model columns', () => {
        const headers = findTableHeaders().at(0).findAll('th');

        // The Feature and Model columns are sortable, so their headers also contain the sort affordance text.
        expect(headers.at(0).text()).toContain('Feature');
        expect(headers.at(1).text()).toContain('Model');
      });

      it('does not render the configure button or selector', () => {
        expect(findAvailableModelsRow().exists()).toBe(false);
        expect(findModelAllowListSelector().exists()).toBe(false);
      });
    });

    describe('when `showAvailableModelsField` is true', () => {
      beforeEach(() => {
        createComponent({
          showAvailableModelsField: true,
          featureSettings: [mockAgenticChatFeatureSetting],
        });
      });

      it('renders the allowlist feature and default model column headers', () => {
        const headers = findTableHeaders().at(0).findAll('th');

        // The Feature column is sortable, so its header also contains the sort affordance text.
        expect(headers).toHaveLength(2);
        expect(headers.at(0).text()).toContain('Feature');
        expect(headers.at(1).text()).toBe('Default model');
      });

      describe('available models row', () => {
        it('renders the configure button', () => {
          expect(findAvailableModelsRow().exists()).toBe(true);
        });

        it('passes the feature `allowList` to the row', () => {
          expect(findAvailableModelsRow().props('allowList')).toEqual(
            mockAgenticChatFeatureSetting.allowList,
          );
        });

        describe('`disabled` state', () => {
          it('is not disabled when the feature has an allow-list', () => {
            expect(findAvailableModelsRow().props('disabled')).toBe(false);
          });

          it('is disabled when the feature has no allow-list', () => {
            createComponent({
              showAvailableModelsField: true,
              featureSettings: [{ ...mockAgenticChatFeatureSetting, allowList: null }],
            });

            expect(findAvailableModelsRow().props('disabled')).toBe(true);
          });

          it('is disabled while the feature is saving, even when the feature has an allow-list', async () => {
            expect(findAvailableModelsRow().props('disabled')).toBe(false);

            findModelSelectorByIdx(0).vm.$emit('update:is-saving', true);
            await nextTick();

            expect(findAvailableModelsRow().props('disabled')).toBe(true);
          });

          it('re-enables after saving completes when the feature still has an allow-list', async () => {
            findModelSelectorByIdx(0).vm.$emit('update:is-saving', true);
            await nextTick();
            expect(findAvailableModelsRow().props('disabled')).toBe(true);

            findModelSelectorByIdx(0).vm.$emit('update:is-saving', false);
            await nextTick();
            expect(findAvailableModelsRow().props('disabled')).toBe(false);
          });
        });

        describe('showModal guard', () => {
          it('does not open the modal while the feature is saving', async () => {
            findModelSelectorByIdx(0).vm.$emit('update:is-saving', true);
            await nextTick();

            await findAvailableModelsRow().vm.$emit('click');

            expect(findModelAllowListSelector().props('visible')).toBe(false);
          });
        });

        describe('`isLoading` state', () => {
          it.each([false, true])(
            'passes `isLoading` as %s when isSaving is %s',
            async (isSaving) => {
              findModelSelectorByIdx(0).vm.$emit('update:is-saving', isSaving);
              await nextTick();

              expect(findAvailableModelsRow().props('isLoading')).toBe(isSaving);
            },
          );
        });

        it('renders the ModelAllowListSelector with the active feature setting when configure is clicked', async () => {
          expect(findModelAllowListSelector().props()).toMatchObject({
            aiFeatureSetting: null,
            visible: false,
          });

          await findAvailableModelsRow().vm.$emit('click');

          expect(findModelAllowListSelector().props()).toMatchObject({
            aiFeatureSetting: mockAgenticChatFeatureSetting,
            visible: true,
          });
        });

        it('updates `isAllowlistModalVisible` when the selector emits `update:visible`', async () => {
          await findAvailableModelsRow().vm.$emit('click');

          expect(findModelAllowListSelector().props('visible')).toBe(true);

          findModelAllowListSelector().vm.$emit('update:visible', false);
          await nextTick();

          expect(findModelAllowListSelector().props('visible')).toBe(false);
        });
      });
    });
  });
});
