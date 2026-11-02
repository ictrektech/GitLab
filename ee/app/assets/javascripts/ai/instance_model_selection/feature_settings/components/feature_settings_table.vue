<script>
import { GlExperimentBadge, GlTooltipDirective } from '@gitlab/ui';
import BaseFeatureSettingsTable from 'ee/ai/shared/feature_settings/base_feature_settings_table.vue';
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  FEATURE_SETTINGS_FIXED_LOADER_WIDTH,
  FEATURE_SETTINGS_VARIABLE_LOADER_WIDTHS,
} from 'ee/ai/shared/feature_settings/constants';
import { RELEASE_STATES } from 'ee/ai/instance_model_selection/constants';
import AvailableModelsRow from 'ee/ai/shared/feature_settings/available_models_row.vue';
import {
  buildAutoModelOption,
  formatDefaultModelData,
  isDuoDeveloperAutoRouted,
} from 'ee/ai/shared/utils/model_selection_utils';
import { PROVIDERS } from '../constants';
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

// No loader: the column is only shown once both queries have loaded.
const MANAGED_BY_FIELD = {
  key: 'managedBy',
  label: s__('AdminAIPoweredFeatures|Managed by'),
  thClass: 'gl-whitespace-nowrap',
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
  name: 'FeatureSettingsTable',
  components: {
    AvailableModelsRow,
    BaseFeatureSettingsTable,
    GlExperimentBadge,
    ModelAllowListSelector,
    ModelSelector,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
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
    showManagedByColumn: {
      type: Boolean,
      required: false,
      default: false,
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
      return [
        SUB_FEATURE_FIELD,
        ...(this.showManagedByColumn ? [MANAGED_BY_FIELD] : []),
        this.showAvailableModelsField ? DEFAULT_MODEL_FIELD : MODEL_FIELD,
      ];
    },
    tableItems() {
      return this.featureSettings.map((item) => ({
        ...item,
        model: this.modelName(item),
        managedBy: this.managedByText(item)?.label ?? '',
      }));
    },
    activeFeatureSetting() {
      return this.featureSettings.find((fs) => fs.feature === this.activeFeature) ?? null;
    },
  },
  methods: {
    isSelfHosted({ provider }) {
      return provider === PROVIDERS.SELF_HOSTED;
    },
    isGitlabManaged({ provider, gitlabModel, defaultGitlabModel }) {
      const isGitlabModelSelected = provider === PROVIDERS.VENDORED && gitlabModel?.ref;
      // With no explicit model, the feature falls back to the GitLab default model.
      const isGitlabDefaultModelSelected =
        defaultGitlabModel &&
        ((provider === PROVIDERS.VENDORED && !gitlabModel) || provider === PROVIDERS.UNASSIGNED);

      return Boolean(isGitlabModelSelected || isGitlabDefaultModelSelected);
    },
    managedByText(item) {
      if (this.isSelfHosted(item)) {
        return {
          label: s__('AdminAIPoweredFeatures|Self-hosted'),
          tooltip: s__(
            'AdminSelfHostedModels|This feature is using a self-hosted model, deployed on your own infrastructure.',
          ),
        };
      }
      if (this.isGitlabManaged(item)) {
        return {
          label: s__('AdminAIPoweredFeatures|GitLab-managed'),
          tooltip: s__(
            'AdminSelfHostedModels|This feature is using a GitLab-managed model, external to your infrastructure.',
          ),
        };
      }

      return null;
    },
    modelName(item) {
      if (item.provider === PROVIDERS.DISABLED) return s__('AdminAIPoweredFeatures|Disabled');

      const selectedName = item.selfHostedModel?.name ?? item.gitlabModel?.name;
      if (selectedName) return selectedName;

      if (isDuoDeveloperAutoRouted(this.glFeatures, item.feature)) {
        return buildAutoModelOption().text;
      }

      return item.defaultGitlabModel ? formatDefaultModelData(item.defaultGitlabModel).text : '';
    },
    getBadgeType(releaseState) {
      if (releaseState === RELEASE_STATES.BETA) {
        return 'beta';
      }
      if (releaseState === RELEASE_STATES.EXPERIMENT) {
        return 'experiment';
      }

      return '';
    },
    canConfigureAvailableModels(feature) {
      if (!this.showAvailableModelsField) return false;

      const isVendored = feature.provider === PROVIDERS.VENDORED;
      const isUnassignedWithDefault =
        feature.provider === PROVIDERS.UNASSIGNED && feature.defaultGitlabModel;

      return (isVendored || isUnassignedWithDefault) && Boolean(feature.allowList);
    },
    isConfigureButtonDisabled(item) {
      return this.savingFeatures[item.feature] || !this.canConfigureAvailableModels(item);
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
    <base-feature-settings-table :fields="tableFields" :items="tableItems" :is-loading="isLoading">
      <template #cell(title)="{ item }">
        <span>{{ item.title }}</span>
        <gl-experiment-badge
          v-if="getBadgeType(item.releaseState)"
          class="gl-ml-3"
          data-testid="feature-badge"
          :type="getBadgeType(item.releaseState)"
        />
      </template>
      <template #cell(managedBy)="{ item }">
        <button
          v-if="item.managedBy"
          v-gl-tooltip="managedByText(item).tooltip"
          :aria-label="`${item.managedBy}. ${managedByText(item).tooltip}`"
          type="button"
          class="gl-whitespace-nowrap gl-border-0 gl-bg-transparent gl-p-0 gl-text-default gl-underline gl-decoration-dotted gl-underline-offset-4"
          data-testid="managed-by-cell"
        >
          {{ item.managedBy }}
        </button>
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
