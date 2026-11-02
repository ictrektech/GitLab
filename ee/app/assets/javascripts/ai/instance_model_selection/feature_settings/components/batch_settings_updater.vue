<script>
import { GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__, sprintf } from '~/locale';
import { getTypeFromGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_AI_SELF_HOSTED_MODEL } from 'ee_else_ce/graphql_shared/constants';
import { LOAD_BALANCED_MODEL_REF_PREFIX } from 'ee/ai/model_selection/constants';
import BulkUpdateControls from 'ee/ai/shared/feature_settings/bulk_update_controls.vue';
import { RELEASE_STATES } from 'ee/ai/instance_model_selection/constants';
import updateAiFeatureSettings from '../graphql/mutations/update_ai_feature_setting.mutation.graphql';
import getAiFeatureSettingsQuery from '../graphql/queries/get_ai_feature_settings.query.graphql';
import { GITLAB_DEFAULT_MODEL, PROVIDERS } from '../constants';
import GitlabManagedModelsDisclaimerModal from './gitlab_managed_models_disclaimer_modal.vue';

export default {
  name: 'InstanceModelSelectionBatchSettingsUpdater',
  components: {
    BulkUpdateControls,
    GitlabManagedModelsDisclaimerModal,
  },
  mixins: [GlToastMixin],
  inject: ['canManageInstanceModelSelection'],
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
      pendingGitlabManagedFeatures: [],
      isSaving: false,
    };
  },
  computed: {
    totalFeatures() {
      return this.aiFeatureSettings.length;
    },
    // Union of every self-hosted model valid for any sub-feature (keyed by id), each
    // annotated with the sub-features it can apply to.
    unionSelfHostedModels() {
      const byId = new Map();

      this.aiFeatureSettings.forEach((fs) => {
        (fs.validModels?.nodes ?? []).forEach((model) => {
          if (!byId.has(model.id)) {
            byId.set(model.id, {
              id: model.id,
              text: `${model.name} (${model.modelDisplayName})`,
              releaseState: model.releaseState,
              features: [],
            });
          }

          byId.get(model.id).features.push(fs.feature);
        });
      });

      const models = [...byId.values()];
      const ga = models.filter(({ releaseState }) => releaseState === RELEASE_STATES.GA);
      const beta = models.filter(({ releaseState }) => releaseState === RELEASE_STATES.BETA);

      return [...ga, ...beta];
    },
    // Union of every GitLab-managed model valid for any sub-feature (keyed by ref).
    //
    // A feature's load-balanced default model (ref prefixed with `__default__`) is
    // skipped: it maps to the GitLab default, which the "Reset to default" action
    // already applies. Offering it as its own dropdown option is redundant and, because
    // it resolves to the empty GitLab-default ref, it would render as pre-selected and
    // do nothing when picked.
    unionGitlabManagedModels() {
      const byRef = new Map();

      this.aiFeatureSettings.forEach((fs) => {
        (fs.validGitlabModels?.nodes ?? []).forEach((model) => {
          if (model.ref?.startsWith(LOAD_BALANCED_MODEL_REF_PREFIX)) return;

          if (!byRef.has(model.ref)) {
            byRef.set(model.ref, {
              ref: model.ref,
              text: model.name,
              provider: model.modelProvider,
              description: model.modelDescription,
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
      const items = [];

      if (this.unionSelfHostedModels.length) {
        items.push({
          text: s__('AdminSelfHostedModels|Self-hosted models'),
          // Self-hosted models carry releaseState so the dropdown can badge Beta models,
          // but not provider/description/costIndicator (only GitLab-managed models do).
          options: this.unionSelfHostedModels.map(({ id, text, releaseState }) => ({
            value: id,
            text,
            releaseState,
          })),
        });
      }

      if (this.unionGitlabManagedModels.length) {
        items.push({
          text: s__('AdminSelfHostedModels|GitLab-managed models'),
          options: this.unionGitlabManagedModels.map(
            ({ ref, text, provider, description, costIndicator }) => ({
              value: ref,
              text,
              provider,
              description,
              costIndicator,
            }),
          ),
        });
      }

      return items;
    },
    // Maps a dropdown item value (self-hosted id or GitLab-managed ref) to its model
    // name and the compatible sub-feature subset, for use on select.
    modelByValue() {
      const map = {};

      this.unionSelfHostedModels.forEach(({ id, text, features }) => {
        map[id] = { text, features };
      });
      this.unionGitlabManagedModels.forEach(({ ref, text, features }) => {
        map[ref] = { text, features };
      });

      return map;
    },
    // Resetting to the GitLab default assigns a GitLab-managed model, which the backend
    // gates on `manage_instance_model_selection`; hide it when the user lacks that ability
    // so self-hosted-only admins don't hit a permission error.
    canResetToDefault() {
      return (
        this.canManageInstanceModelSelection &&
        this.aiFeatureSettings.every((fs) => Boolean(fs.defaultGitlabModel))
      );
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
    getProvider(value) {
      return getTypeFromGraphQLId(value) === TYPENAME_AI_SELF_HOSTED_MODEL
        ? PROVIDERS.SELF_HOSTED
        : PROVIDERS.VENDORED;
    },
    onSelectModel(value) {
      const model = this.modelByValue[value];

      if (!model) return;

      if (this.getProvider(value) === PROVIDERS.SELF_HOSTED) {
        this.applyModel({
          provider: PROVIDERS.SELF_HOSTED,
          modelId: value,
          features: model.features,
        });
        return;
      }

      this.onSelectGitlabManagedModel({ text: model.text, value }, model.features);
    },
    onSelectGitlabManagedModel(model, features) {
      this.pendingGitlabManagedFeatures = features;
      this.$refs.disclaimerModal.showModal(model);
    },
    onConfirmGitlabManagedModel(ref) {
      this.applyModel({
        provider: PROVIDERS.VENDORED,
        modelRef: ref,
        features: this.pendingGitlabManagedFeatures,
      });
    },
    onResetToDefault() {
      // Resetting assigns a GitLab-managed model, so route through the same consent
      // disclaimer used everywhere else a GitLab-managed model is applied. GitLab
      // default is `''`, not `null`, so the mutation's manage-permission guard applies
      // consistently with the per-row default path.
      this.onSelectGitlabManagedModel(
        { text: s__('ModelSelection|GitLab default'), value: GITLAB_DEFAULT_MODEL },
        this.aiFeatureSettings.map((fs) => fs.feature),
      );
    },
    async applyModel({ provider, modelId = null, modelRef = null, features }) {
      this.isSaving = true;
      this.$emit('update-batch-saving-state', true);

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateAiFeatureSettings,
          variables: {
            input: {
              features: features.map((feature) => feature.toUpperCase()),
              provider: provider.toUpperCase(),
              aiSelfHostedModelId: modelId,
              offeredModelRef: modelRef,
            },
          },
          refetchQueries: [{ query: getAiFeatureSettingsQuery }],
        });

        if (data) {
          const { errors } = data.aiFeatureSettingUpdate;

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
    :header-text="s__('AdminAIPoweredFeatures|Compatible models')"
    @select="onSelectModel"
    @reset="onResetToDefault"
  >
    <gitlab-managed-models-disclaimer-modal
      ref="disclaimerModal"
      @confirm="onConfirmGitlabManagedModel"
    />
  </bulk-update-controls>
</template>
