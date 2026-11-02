import { nextTick } from 'vue';
import { GlExperimentBadge } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import FeatureSettingsTable from 'ee/ai/instance_model_selection/feature_settings/components/feature_settings_table.vue';
import BaseFeatureSettingsTable from 'ee/ai/shared/feature_settings/base_feature_settings_table.vue';
import ModelAllowListSelector from 'ee/ai/instance_model_selection/feature_settings/components/model_allow_list_selector.vue';
import AvailableModelsRow from 'ee/ai/shared/feature_settings/available_models_row.vue';
import ModelSelector from 'ee/ai/instance_model_selection/feature_settings/components/model_selector.vue';

import {
  mockCodeSuggestionsFeatureSettings,
  mockAgenticChatFeatureSetting,
  mockAiFeatureSettings,
  mockDefaultGitlabModel,
  mockDuoChatFeatureSettings,
  mockDuoDeveloperFeatureSetting,
  mockGitlabManagedModels,
  mockInstanceModelSelectionFeatureSettings,
} from './mock_data';

describe('FeatureSettingsTable', () => {
  let wrapper;

  const createComponent = (props = {}, provide = {}, mountOptions = {}) => {
    wrapper = mountExtended(FeatureSettingsTable, {
      provide: {
        canManageInstanceModelSelection: true,
        canManageSelfHostedModels: false,
        canManageDapSelfHostedModels: false,
        ...provide,
      },
      propsData: {
        featureSettings: mockCodeSuggestionsFeatureSettings,
        isLoading: false,
        ...props,
      },
      ...mountOptions,
    });
  };

  // Stubbing a directive interferes with `setProps` re-renders under Vue 3, so
  // only the tooltip assertions mount with the mock.
  const createComponentWithMockedTooltip = (props = {}) =>
    createComponent(props, {}, { directives: { GlTooltip: createMockDirective('gl-tooltip') } });

  const findFeatureSettingsTable = () => wrapper.findComponent(FeatureSettingsTable);
  const findBaseTable = () => wrapper.findComponent(BaseFeatureSettingsTable);
  const findTableRows = () => findFeatureSettingsTable().findAllComponents('tbody > tr');
  const findTableHeaders = () => findFeatureSettingsTable().findAllComponents('thead > tr');
  const findHeaderCells = () => findTableHeaders().at(0).findAll('th');
  const findManagedByCell = () => findTableRows().at(0).find('[data-testid="managed-by-cell"]');
  const findTooltipValue = () => getBinding(findManagedByCell().element, 'gl-tooltip').value;
  const findRowFeatureNameByIdx = (idx) => findTableRows().at(idx).findAll('td').at(0);
  const findModelSelectorByIdx = (idx) => findTableRows().at(idx).findComponent(ModelSelector);
  const findBadge = () => wrapper.findComponent(GlExperimentBadge);
  const findConfigureButton = () => wrapper.findByTestId('configure-button');
  const findAvailableModelsRow = () => wrapper.findComponent(AvailableModelsRow);
  const findModelAllowListSelector = () => wrapper.findComponent(ModelAllowListSelector);

  it('renders the component', () => {
    createComponent();

    expect(findFeatureSettingsTable().exists()).toBe(true);
  });

  describe('column headers', () => {
    describe('when `showAvailableModelsField` is false', () => {
      it('renders the default column headers', () => {
        createComponent();
        const headers = findTableHeaders().at(0).findAll('th');

        // Sortable columns also render the sort affordance text in their headers.
        expect(headers.at(0).text()).toContain('Feature');
        expect(headers.at(1).text()).toContain('Model');
      });
    });

    describe('when `showAvailableModelsField` is true', () => {
      it('renders the allowlist feature and default model column headers', () => {
        createComponent({ showAvailableModelsField: true });
        const headers = findTableHeaders().at(0).findAll('th');

        // The Feature column is sortable, so its header also contains the sort affordance text.
        expect(headers).toHaveLength(2);
        expect(headers.at(0).text()).toContain('Feature');
        expect(headers.at(1).text()).toBe('Default model');
      });
    });
  });

  describe('Managed by column', () => {
    const [codeGeneration, codeCompletion] = mockCodeSuggestionsFeatureSettings;
    const selfHostedFeatureSetting = mockDuoChatFeatureSettings[0]; // 'Troubleshoot Job'
    const gitlabManagedFeatureSetting = {
      ...codeGeneration,
      gitlabModel: mockGitlabManagedModels[0],
      defaultGitlabModel: mockDefaultGitlabModel,
    };
    const unassignedFeatureSetting = {
      ...codeGeneration,
      feature: 'code_explanation',
      title: 'Code Explanation',
      provider: 'unassigned',
      gitlabModel: null,
      defaultGitlabModel: mockDefaultGitlabModel,
    };

    describe('when `showManagedByColumn` is true', () => {
      it.each`
        showAvailableModelsField | expected
        ${false}                 | ${['Feature', 'Managed by', 'Model']}
        ${true}                  | ${['Feature', 'Managed by', 'Default model']}
      `(
        'renders the column after Feature when `showAvailableModelsField` is $showAvailableModelsField',
        ({ showAvailableModelsField, expected }) => {
          createComponent({ showManagedByColumn: true, showAvailableModelsField });

          expect(findHeaderCells()).toHaveLength(expected.length);
          expected.forEach((label, idx) => {
            expect(findHeaderCells().at(idx).text()).toContain(label);
          });
        },
      );

      it('makes the column sortable', () => {
        createComponent({ showManagedByColumn: true });

        expect(findBaseTable().props('fields')).toContainEqual(
          expect.objectContaining({ key: 'managedBy', sortable: true }),
        );
      });
    });

    describe('when `showManagedByColumn` is false', () => {
      beforeEach(() => {
        createComponent({
          featureSettings: [selfHostedFeatureSetting],
          showManagedByColumn: false,
        });
      });

      it('does not render the column', () => {
        expect(findHeaderCells()).toHaveLength(2);
        expect(findHeaderCells().at(0).text()).toContain('Feature');
        expect(findHeaderCells().at(1).text()).toContain('Model');
        expect(findManagedByCell().exists()).toBe(false);
      });
    });

    describe.each`
      scenario                                        | featureSetting                                           | text                | tooltip
      ${'a self-hosted model'}                        | ${selfHostedFeatureSetting}                              | ${'Self-hosted'}    | ${'This feature is using a self-hosted model, deployed on your own infrastructure.'}
      ${'a GitLab-managed model'}                     | ${gitlabManagedFeatureSetting}                           | ${'GitLab-managed'} | ${'This feature is using a GitLab-managed model, external to your infrastructure.'}
      ${'the GitLab default model'}                   | ${unassignedFeatureSetting}                              | ${'GitLab-managed'} | ${'This feature is using a GitLab-managed model, external to your infrastructure.'}
      ${'a vendored provider with no explicit model'} | ${{ ...gitlabManagedFeatureSetting, gitlabModel: null }} | ${'GitLab-managed'} | ${'This feature is using a GitLab-managed model, external to your infrastructure.'}
    `('when the feature uses $scenario', ({ featureSetting, text, tooltip }) => {
      beforeEach(() => {
        createComponentWithMockedTooltip({
          featureSettings: [featureSetting],
          showManagedByColumn: true,
        });
      });

      it('renders who manages the model', () => {
        expect(findManagedByCell().text()).toBe(text);
      });

      it('renders the value as a button so keyboard users can open the tooltip', () => {
        expect(findManagedByCell().element.tagName).toBe('BUTTON');
        expect(findManagedByCell().attributes('type')).toBe('button');
      });

      it('explains who manages the model in a tooltip', () => {
        expect(findTooltipValue()).toBe(tooltip);
      });

      it('includes the visible label and explanation in the accessible name', () => {
        expect(findManagedByCell().attributes('aria-label')).toBe(`${text}. ${tooltip}`);
      });
    });

    describe.each`
      scenario                                | featureSetting
      ${'is disabled'}                        | ${codeCompletion}
      ${'has no model and no GitLab default'} | ${{ ...unassignedFeatureSetting, defaultGitlabModel: null }}
    `('when the feature $scenario', ({ featureSetting }) => {
      beforeEach(() => {
        createComponent({ featureSettings: [featureSetting], showManagedByColumn: true });
      });

      it('renders an empty cell', () => {
        expect(findManagedByCell().exists()).toBe(false);
      });
    });

    describe('when the selected model changes', () => {
      it('updates the cell', async () => {
        createComponent({
          featureSettings: [gitlabManagedFeatureSetting],
          showManagedByColumn: true,
        });

        expect(findManagedByCell().text()).toBe('GitLab-managed');

        await wrapper.setProps({
          featureSettings: [
            { ...selfHostedFeatureSetting, feature: gitlabManagedFeatureSetting.feature },
          ],
        });

        expect(findManagedByCell().text()).toBe('Self-hosted');
      });
    });
  });

  describe('table items', () => {
    const unassigned = {
      ...mockCodeSuggestionsFeatureSettings[0],
      provider: 'unassigned',
      gitlabModel: null,
      selfHostedModel: null,
      defaultGitlabModel: mockDefaultGitlabModel, // 'Claude Sonnet 4.0'
    };

    it.each`
      description                              | featureSetting                                  | glFeatures                             | model                            | managedBy
      ${'a disabled feature'}                  | ${mockCodeSuggestionsFeatureSettings[1]}        | ${{}}                                  | ${'Disabled'}                    | ${''}
      ${'a self-hosted model'}                 | ${mockDuoChatFeatureSettings[0]}                | ${{}}                                  | ${'Model 1'}                     | ${'Self-hosted'}
      ${'a GitLab-managed model'}              | ${mockInstanceModelSelectionFeatureSettings[0]} | ${{}}                                  | ${'Claude Sonnet 4.0'}           | ${'GitLab-managed'}
      ${'the GitLab default model'}            | ${unassigned}                                   | ${{}}                                  | ${'Claude Sonnet 4.0 - Default'} | ${'GitLab-managed'}
      ${'Duo Developer with model routing'}    | ${mockDuoDeveloperFeatureSetting}               | ${{ duoDeveloperModelRouting: true }}  | ${'Auto'}                        | ${'GitLab-managed'}
      ${'Duo Developer without model routing'} | ${mockDuoDeveloperFeatureSetting}               | ${{ duoDeveloperModelRouting: false }} | ${'Claude Sonnet 4.0 - Default'} | ${'GitLab-managed'}
      ${'no selection and no default model'}   | ${{ ...unassigned, defaultGitlabModel: null }}  | ${{}}                                  | ${''}                            | ${''}
    `(
      'sets `model` and `managedBy` to the text shown in the table for $description',
      ({ featureSetting, glFeatures, model, managedBy }) => {
        createComponent({ featureSettings: [featureSetting] }, { glFeatures });

        expect(findBaseTable().props('items')[0]).toMatchObject({ model, managedBy });
      },
    );
  });

  describe('rows', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders row data for each feature setting', () => {
      expect(findTableRows()).toHaveLength(mockCodeSuggestionsFeatureSettings.length);
    });

    it('renders the feature name', () => {
      expect(findRowFeatureNameByIdx(0).text()).toBe('Code Generation');
      expect(findRowFeatureNameByIdx(1).text()).toBe('Code Completion');
    });

    describe('beta/experiment badges', () => {
      it('renders the beta badge for beta features', () => {
        const betaFeature = mockAiFeatureSettings[4];
        createComponent({ featureSettings: [betaFeature] });

        expect(findBadge().props('type')).toBe('beta');
      });

      it('renders the experiment badge for experiment features', () => {
        const experimentFeature = mockAiFeatureSettings[2];
        createComponent({ featureSettings: [experimentFeature] });

        expect(findBadge().props('type')).toBe('experiment');
      });

      it('does not render the badges for non-beta or non-experimental features', () => {
        createComponent();

        expect(findBadge().exists()).toBe(false);
      });
    });

    it('renders the model selector and passes the correct props', () => {
      [
        [0, ''],
        [1, 'Disabled'],
      ].forEach(([idx, model]) => {
        expect(findModelSelectorByIdx(idx).props()).toEqual({
          aiFeatureSetting: {
            ...mockCodeSuggestionsFeatureSettings[idx],
            model,
            managedBy: '',
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

    describe('available models field', () => {
      describe('when `showAvailableModelsField` is false', () => {
        it('does not render the `Configure` button or selector', () => {
          expect(findConfigureButton().exists()).toBe(false);
          expect(findModelAllowListSelector().exists()).toBe(false);
        });
      });

      describe('when `showAvailableModelsField` is true', () => {
        const createWithFeature = (overrides = {}) =>
          createComponent({
            featureSettings: [{ ...mockAgenticChatFeatureSetting, ...overrides }],
            showAvailableModelsField: true,
          });

        it('renders the `Configure` button and selector', () => {
          createWithFeature();

          expect(findConfigureButton().text()).toBe('Configure');
          expect(findModelAllowListSelector().exists()).toBe(true);
        });

        it('hides the allow-list modal by default', () => {
          createWithFeature();

          expect(findModelAllowListSelector().props('visible')).toBe(false);
        });

        it('hides the allow-list modal when selector emits `update:visible` with false', async () => {
          createWithFeature();

          await findConfigureButton().trigger('click');
          expect(findModelAllowListSelector().props('visible')).toBe(true);

          findModelAllowListSelector().vm.$emit('update:visible', false);
          await nextTick();

          expect(findModelAllowListSelector().props('visible')).toBe(false);
        });

        describe('available models row', () => {
          it('passes the feature `allowList` to the row', () => {
            createWithFeature();

            expect(findAvailableModelsRow().props('allowList')).toEqual(
              mockAgenticChatFeatureSetting.allowList,
            );
          });

          describe('when `Configure` button is clicked', () => {
            beforeEach(async () => {
              createWithFeature();

              await findConfigureButton().trigger('click');
            });

            it('passes the correct props to the allow-list selector', () => {
              expect(findModelAllowListSelector().props('visible')).toBe(true);
              expect(findModelAllowListSelector().props('aiFeatureSetting')).toEqual(
                mockAgenticChatFeatureSetting,
              );
            });
          });

          describe('`disabled` state', () => {
            it.each`
              scenario                                            | overrides                                                                 | expected
              ${'a GitLab-managed (vendored) model is selected'}  | ${{ provider: 'vendored' }}                                               | ${false}
              ${'provider is unassigned with a default model'}    | ${{ provider: 'unassigned', defaultGitlabModel: mockDefaultGitlabModel }} | ${false}
              ${'a self-hosted model is selected'}                | ${{ provider: 'self_hosted' }}                                            | ${true}
              ${'provider is disabled'}                           | ${{ provider: 'disabled' }}                                               | ${true}
              ${'provider is unassigned without a default model'} | ${{ provider: 'unassigned', defaultGitlabModel: null }}                   | ${true}
              ${'the feature has no allow-list'}                  | ${{ provider: 'vendored', allowList: null }}                              | ${true}
            `('passes `disabled` as $expected when $scenario', ({ overrides, expected }) => {
              createWithFeature(overrides);

              expect(findAvailableModelsRow().props('disabled')).toBe(expected);
            });

            it('is disabled while the feature is saving, even when the provider would normally enable it', async () => {
              createWithFeature({ provider: 'vendored' });

              expect(findAvailableModelsRow().props('disabled')).toBe(false);

              findModelSelectorByIdx(0).vm.$emit('update:is-saving', true);
              await nextTick();

              expect(findAvailableModelsRow().props('disabled')).toBe(true);
            });

            it('re-enables after saving completes when the provider still allows it', async () => {
              createWithFeature({ provider: 'vendored' });

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
              createWithFeature({ provider: 'vendored' });

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
                createWithFeature();

                findModelSelectorByIdx(0).vm.$emit('update:is-saving', isSaving);
                await nextTick();

                expect(findAvailableModelsRow().props('isLoading')).toBe(isSaving);
              },
            );
          });
        });
      });
    });
  });
});
