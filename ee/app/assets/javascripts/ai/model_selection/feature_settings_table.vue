<script>
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import BaseFeatureSettingsTable from 'ee/ai/shared/feature_settings/base_feature_settings_table.vue';
import AvailableModelsRow from 'ee/ai/shared/feature_settings/available_models_row.vue';
import {
  FEATURE_SETTINGS_FIXED_LOADER_WIDTH,
  FEATURE_SETTINGS_VARIABLE_LOADER_WIDTHS,
} from 'ee/ai/shared/feature_settings/constants';
import {
  buildAutoModelOption,
  formatDefaultModelData,
  isDuoDeveloperAutoRouted,
} from 'ee/ai/shared/utils/model_selection_utils';

import ModelAllowListSelector from './model_allow_list_selector.vue';
import ModelSelector from './model_selector.vue';

const SUB_FEATURE_FIELD = {
  key: 'title',
  label: s__('AdminAIPoweredFeatures|Feature'),
  thClass: 'gl-w-full',
  loaderClass: 'gl-w-48 [&_svg]:gl-w-full',
  loaderWidths: FEATURE_SETTINGS_VARIABLE_LOADER_WIDTHS,
  sortable: true,
};

const MODEL_FIELD = {
  key: 'model',
  label: s__('AdminAIPoweredFeatures|Model'),
  thClass: 'gl-w-34 lg:gl-w-48',
  loaderClass: 'gl-w-34 [&_svg]:gl-w-full lg:gl-w-48',
  loaderWidths: [FEATURE_SETTINGS_FIXED_LOADER_WIDTH],
  sortable: true,
};

const DEFAULT_MODEL_FIELD = {
  ...MODEL_FIELD,
  label: s__('AdminAIPoweredFeatures|Default model'),
  thClass: 'gl-w-1/3',
  sortable: false,
};

export default {
  name: 'ModelSelectionFeatureSettingsTable',
  components: {
    AvailableModelsRow,
    BaseFeatureSettingsTable,
    ModelAllowListSelector,
    ModelSelector,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    featureSettings: {
      type: Array,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    batchUpdateIsSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
    showAvailableModelsField: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      savingFeatures: {},
      activeFeature: null,
      isAllowlistModalVisible: false,
    };
  },
  computed: {
    tableFields() {
      return this.showAvailableModelsField
        ? [SUB_FEATURE_FIELD, DEFAULT_MODEL_FIELD]
        : [SUB_FEATURE_FIELD, MODEL_FIELD];
    },
    tableItems() {
      return this.featureSettings.map((item) => ({ ...item, model: this.modelName(item) }));
    },
    activeFeatureSetting() {
      return this.featureSettings.find((s) => s.feature === this.activeFeature) ?? null;
    },
  },
  methods: {
    modelName(item) {
      if (item.selectedModel?.ref) return item.selectedModel.name;

      if (isDuoDeveloperAutoRouted(this.glFeatures, item.feature)) {
        return buildAutoModelOption().text;
      }

      return item.defaultModel ? formatDefaultModelData(item.defaultModel).text : '';
    },
    isConfigureButtonDisabled(item) {
      return this.savingFeatures[item.feature] || !item.allowList;
    },
    showModal(item) {
      if (this.savingFeatures[item.feature]) return;
      this.activeFeature = item.feature;
      this.isAllowlistModalVisible = true;
    },
    onSave(feature, isSaving) {
      this.savingFeatures = { ...this.savingFeatures, [feature]: isSaving };
    },
  },
};
</script>
<template>
  <div>
    <base-feature-settings-table :items="tableItems" :is-loading="isLoading" :fields="tableFields">
      <template #cell(title)="{ item }">
        {{ item.title }}
      </template>
      <template #cell(model)="{ item }">
        <div class="gl-flex gl-flex-col gl-gap-2">
          <model-selector
            :ai-feature-setting="item"
            :batch-update-is-saving="batchUpdateIsSaving"
            @update:is-saving="(value) => onSave(item.feature, value)"
          />
          <available-models-row
            v-if="showAvailableModelsField"
            :disabled="isConfigureButtonDisabled(item)"
            :is-loading="savingFeatures[item.feature]"
            :allow-list="item.allowList"
            @click="showModal(item)"
          />
        </div>
      </template>
    </base-feature-settings-table>
    <model-allow-list-selector
      v-if="showAvailableModelsField"
      :ai-feature-setting="activeFeatureSetting"
      :visible="isAllowlistModalVisible"
      @update:visible="isAllowlistModalVisible = $event"
    />
  </div>
</template>
