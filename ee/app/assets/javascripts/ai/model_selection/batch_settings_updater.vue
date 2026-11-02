<script>
import { GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__, sprintf } from '~/locale';
import BulkUpdateControls from 'ee/ai/shared/feature_settings/bulk_update_controls.vue';
import GitlabDefaultModelModal from './gitlab_default_model_modal.vue';
import updateAiNamespaceFeatureSettingsMutation from './graphql/update_ai_namespace_feature_settings.mutation.graphql';
import getAiNamespaceFeatureSettingsQuery from './graphql/get_ai_namepace_feature_settings.query.graphql';
import {
  GITLAB_DEFAULT_MODEL,
  SUPPRESS_DEFAULT_MODEL_MODAL_KEY,
  LOAD_BALANCED_MODEL_REF_PREFIX,
} from './constants';

export default {
  name: 'ModelSelectionBatchSettingsUpdater',
  components: {
    BulkUpdateControls,
    GitlabDefaultModelModal,
  },
  mixins: [GlToastMixin],
  inject: ['groupId'],
  props: {
    aiFeatureSettings: {
      type: Array,
      required: true,
    },
    mainFeature: {
      type: String,
      required: true,
    },
  },
  emits: ['update-batch-saving-state'],
  data() {
    return {
      isSaving: false,
    };
  },
  computed: {
    totalFeatures() {
      return this.aiFeatureSettings.length;
    },
    // Union of every model selectable by any sub-feature in the section, each annotated
    // with the sub-features it can apply to. Models that only fit some sub-features are
    // still offered, but applied to that compatible subset only.
    //
    // A feature's load-balanced default model (ref prefixed with `__default__`) is
    // skipped: it maps to the GitLab default, which the "Reset to default" action
    // already applies. Offering it as its own dropdown option is redundant and, because
    // it resolves to the empty GitLab-default ref, it would render as pre-selected and
    // do nothing when picked.
    unionModels() {
      const byRef = new Map();

      this.aiFeatureSettings.forEach((fs) => {
        (fs.selectableModels || []).forEach((model) => {
          if (!model?.ref) return;

          if (model.ref.startsWith(LOAD_BALANCED_MODEL_REF_PREFIX)) return;

          if (!byRef.has(model.ref)) {
            byRef.set(model.ref, {
              ref: model.ref,
              name: model.name,
              modelProvider: model.modelProvider,
              modelDescription: model.modelDescription,
              costIndicator: model.costIndicator,
              features: [],
            });
          }

          byRef.get(model.ref).features.push(fs.feature);
        });
      });

      return [...byRef.values()];
    },
    bulkUpdateItems() {
      return this.unionModels
        .map(({ ref, name, modelProvider, modelDescription, costIndicator }) => ({
          value: ref,
          text: name,
          provider: modelProvider,
          description: modelDescription,
          costIndicator,
        }))
        .sort((a, b) => a.text.localeCompare(b.text));
    },
    featuresByModelRef() {
      return Object.fromEntries(this.unionModels.map(({ ref, features }) => [ref, features]));
    },
    canResetToDefault() {
      return this.aiFeatureSettings.every((fs) => Boolean(fs.defaultModel));
    },
    errorMessage() {
      return sprintf(
        s__(
          'AdminSelfHostedModels|An error occurred while updating the %{mainFeature} sub-feature settings. Please try again.',
        ),
        { mainFeature: this.mainFeature },
        false,
      );
    },
  },
  methods: {
    successMessage(appliedCount) {
      if (appliedCount === this.totalFeatures) {
        return sprintf(
          s__('ModelSelection|All %{mainFeature} features updated'),
          { mainFeature: this.mainFeature },
          false,
        );
      }

      return sprintf(
        s__('ModelSelection|%{count} of %{total} %{mainFeature} features updated'),
        { count: appliedCount, total: this.totalFeatures, mainFeature: this.mainFeature },
        false,
      );
    },
    onSelectModel(ref) {
      const features = this.featuresByModelRef[ref];

      if (!features) return;

      this.applyModel(ref, features);
    },
    onResetToDefault() {
      const suppressModal = localStorage.getItem(SUPPRESS_DEFAULT_MODEL_MODAL_KEY) === 'true';

      if (!suppressModal) {
        this.$refs.defaultModelModal.showModal();
        return;
      }

      this.applyModel(GITLAB_DEFAULT_MODEL);
    },
    // features: the sub-features to apply to. Defaults to all (used by reset-to-default).
    async applyModel(offeredModelRef, features = this.aiFeatureSettings.map((fs) => fs.feature)) {
      this.isSaving = true;
      this.$emit('update-batch-saving-state', true);

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateAiNamespaceFeatureSettingsMutation,
          variables: {
            input: {
              features: features.map((feature) => feature.toUpperCase()),
              groupId: this.groupId,
              offeredModelRef,
            },
          },
          refetchQueries: [
            { query: getAiNamespaceFeatureSettingsQuery, variables: { groupId: this.groupId } },
          ],
        });

        if (data) {
          const { errors } = data.aiModelSelectionNamespaceUpdate;

          if (errors.length > 0) {
            throw new Error(errors[0]);
          }

          this.$toast.show(this.successMessage(features.length));
        }
      } catch (error) {
        createAlert({
          message: this.errorMessage,
          error,
          captureError: true,
        });
      } finally {
        this.isSaving = false;
        this.$emit('update-batch-saving-state', false);
      }
    },
  },
};
</script>
<template>
  <bulk-update-controls
    :items="bulkUpdateItems"
    :can-reset="canResetToDefault"
    :is-saving="isSaving"
    @select="onSelectModel"
    @reset="onResetToDefault"
  >
    <gitlab-default-model-modal ref="defaultModelModal" @confirm-submit="applyModel" />
  </bulk-update-controls>
</template>
