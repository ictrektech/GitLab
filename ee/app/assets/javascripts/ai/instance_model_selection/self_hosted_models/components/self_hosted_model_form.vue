<script>
import { GlButton, GlCard, GlForm, GlFormFields, GlLink, GlSprintf } from '@gitlab/ui';
import { formValidators } from '@gitlab/ui/src/utils';
import { omit } from 'lodash-es';
import { helpPagePath } from '~/helpers/help_page_helper';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { visitUrlWithAlerts } from '~/lib/utils/url_utility';
import { s__, sprintf } from '~/locale';
import { createAlert } from '~/alert';

import InputCopyToggleVisibility from '~/vue_shared/components/input_copy_toggle_visibility/input_copy_toggle_visibility.vue';
import {
  SELF_HOSTED_MODEL_PLATFORMS,
  BEDROCK_DUMMY_ENDPOINT,
  VERTEX_DUMMY_ENDPOINT,
  CLOUD_PROVIDER_MODELS,
} from '../constants';
import BetaFeaturesAlert from '../../shared/components/beta_features_alert.vue';
import TestConnectionButton from './test_connection_button.vue';
import ModelSelector from './model_selector.vue';
import PlatformSelector from './platform_selector.vue';

const identifierPrefixByPlatform = {
  [SELF_HOSTED_MODEL_PLATFORMS.BEDROCK]: 'bedrock/',
  [SELF_HOSTED_MODEL_PLATFORMS.VERTEX_AI]: 'vertex_ai/',
};

const identifierPrefixForPlatform = (platform) => identifierPrefixByPlatform[platform] || '';
const baseFormFieldClasses = ['gl-w-full', 'gl-mb-5'];
const nameFormField = {
  name: {
    label: s__('AdminSelfHostedModels|Deployment name'),
    validators: [
      formValidators.required(s__('AdminSelfHostedModels|Please enter a deployment name.')),
    ],
  },
};
const modelFormField = {
  model: {
    label: s__('AdminSelfHostedModels|Model family'),
    validators: [formValidators.required(s__('AdminSelfHostedModels|Please select a model.'))],
    groupAttrs: {
      class: baseFormFieldClasses,
    },
  },
};
const apiFormFields = {
  endpoint: {
    label: s__('AdminSelfHostedModels|Endpoint'),
    validators: [formValidators.required(s__('AdminSelfHostedModels|Please enter an endpoint.'))],
    groupAttrs: {
      class: baseFormFieldClasses,
    },
  },
  identifier: {
    label: s__('AdminSelfHostedModels|Model identifier'),
    validators: [
      formValidators.required(s__('AdminSelfHostedModels|Please enter a model identifier.')),
      formValidators.factory(
        s__('AdminSelfHostedModels|Model identifier must be less than 255 characters.'),
        (val) => val.length <= 255,
      ),
    ],
    groupAttrs: {
      class: baseFormFieldClasses,
    },
  },
};
// Role names cannot contain a slash and are at most 64 characters. Keep this in sync with
// Ai::SelfHostedModel::IAM_ROLE_ARN_REGEX.
const IAM_ROLE_ARN_REGEX =
  /^arn:aws(-cn|-us-gov)?:iam::\d{12}:role\/(?:[\w+=,.@-]+\/)*[\w+=,.@-]{1,64}$/;
// The maximum length AWS documents for an IAM role ARN.
const IAM_ROLE_MAX_LENGTH = 2048;
const IAM_ROLE_PLACEHOLDER = 'arn:aws:iam::123456789012:role/role-name';
const isValidIamRole = (val) => val.length <= IAM_ROLE_MAX_LENGTH && IAM_ROLE_ARN_REGEX.test(val);
const bedrockFormFields = {
  iamRole: {
    label: s__('AdminSelfHostedModels|IAM role to assume'),
    validators: [
      formValidators.factory(
        s__(
          'AdminSelfHostedModels|Enter a valid role ARN (for example, arn:aws:iam::123456789012:role/role-name).',
        ),
        (val) => val === '' || isValidIamRole(val),
      ),
    ],
    groupAttrs: {
      class: baseFormFieldClasses,
    },
    inputAttrs: {
      placeholder: IAM_ROLE_PLACEHOLDER,
    },
  },
};
const cloudPlatformFormFields = (identifierPrefix) => ({
  identifier: {
    label: s__('AdminSelfHostedModels|Model identifier'),
    validators: [
      formValidators.required(s__('AdminSelfHostedModels|Please enter a model identifier.')),
      formValidators.factory(
        sprintf(
          s__('AdminSelfHostedModels|Model identifier must start with "%{identifierPrefix}"'),
          { identifierPrefix },
        ),
        (val) => val.startsWith(identifierPrefix),
      ),
      formValidators.factory(
        s__('AdminSelfHostedModels|Model identifier must be less than 255 characters.'),
        (val) => val.length <= 255,
      ),
    ],
    groupAttrs: {
      class: baseFormFieldClasses,
    },
  },
});

export default {
  name: 'SelfHostedModelForm',
  components: {
    GlButton,
    GlCard,
    GlForm,
    GlFormFields,
    GlLink,
    GlSprintf,
    BetaFeaturesAlert,
    InputCopyToggleVisibility,
    ModelSelector,
    PlatformSelector,
    TestConnectionButton,
  },
  inject: ['basePath', 'betaModelsEnabled', 'instanceId'],
  props: {
    submitButtonText: {
      type: String,
      required: false,
      default: s__('AdminSelfHostedModels|Add self-hosted model'),
    },
    mutationData: {
      type: Object,
      required: true,
    },
    initialFormValues: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  i18n: {
    defaultError: s__(
      'AdminSelfHostedModels|There was an error saving the self-hosted model. Please try again.',
    ),
    nonUniqueDeploymentNameError: s__(
      'AdminSelfHostedModels|Please enter a unique deployment name.',
    ),
    invalidEndpointError: s__('AdminSelfHostedModels|Please add a valid endpoint.'),
    awsSetupMessage: s__(
      'AdminSelfHostedModels|To fully set up AWS credentials for this model please refer to the %{linkStart}AWS Bedrock Configuration Guide%{linkEnd}',
    ),
    vertexAiSetupMessage: s__(
      'AdminSelfHostedModels|To fully set up Google Cloud credentials for this model please refer to the %{linkStart}Google Vertex AI Configuration Guide%{linkEnd}',
    ),
  },
  formId: 'self-hosted-model-form',
  iamRoleHelpUrl: helpPagePath(
    'administration/gitlab_duo_self_hosted/supported_llm_serving_platforms',
    {
      anchor: 'assume-an-iam-role-with-aws-bedrock',
    },
  ),
  cloudPlatformSetupUrl: helpPagePath(
    'administration/gitlab_duo_self_hosted/supported_llm_serving_platforms',
    {
      anchor: 'cloud-hosted-model-deployments',
    },
  ),
  nameFormField,
  data() {
    const {
      name = '',
      model = '',
      endpoint = '',
      identifier = '',
      iamRole = '',
      apiToken = '',
      provider = SELF_HOSTED_MODEL_PLATFORMS.API,
    } = this.initialFormValues;

    return {
      baseFormValues: {
        name,
        endpoint,
        identifier,
        iamRole: iamRole || '',
        model: model.toUpperCase(),
      },
      platform: provider,
      apiToken,
      serverValidations: {},
      isSaving: false,
    };
  },
  computed: {
    cloudPlatformIdentifierPrefix() {
      return identifierPrefixForPlatform(this.platform);
    },
    cloudPlatformFields() {
      return cloudPlatformFormFields(this.cloudPlatformIdentifierPrefix);
    },
    platformFormFields() {
      const platformFields = this.isApiPlatform ? apiFormFields : this.cloudPlatformFields;
      const fields = {
        ...modelFormField,
        ...platformFields,
        ...(this.isBedrockPlatform ? bedrockFormFields : {}),
      };

      fields.identifier.inputAttrs = {
        placeholder: this.identifierPlaceholder,
      };

      return fields;
    },
    hasValidInput() {
      const { name, model, endpoint, identifier, iamRole } = this.baseFormValues;

      if (name === '' || model === '' || identifier === '') {
        return false;
      }

      if (this.isApiPlatform) {
        return endpoint !== '' && identifier.length <= 255;
      }

      if (this.isBedrockPlatform && iamRole && !isValidIamRole(iamRole)) {
        return false;
      }

      return identifier.startsWith(this.cloudPlatformIdentifierPrefix) && identifier.length <= 255;
    },
    isEditing() {
      return Boolean(this.initialFormValues.id);
    },
    isApiPlatform() {
      return this.platform === SELF_HOSTED_MODEL_PLATFORMS.API;
    },
    isBedrockPlatform() {
      return this.platform === SELF_HOSTED_MODEL_PLATFORMS.BEDROCK;
    },
    successMessage() {
      if (this.isEditing) {
        return s__('AdminSelfHostedModels|The self-hosted model was successfully saved.');
      }

      return s__('AdminSelfHostedModels|Model added. Select it for a feature to start using it.');
    },
    platformSetupMessage() {
      return this.platform === SELF_HOSTED_MODEL_PLATFORMS.BEDROCK
        ? this.$options.i18n.awsSetupMessage
        : this.$options.i18n.vertexAiSetupMessage;
    },
    formValues() {
      /*
        Endpoint and api tokens aren't used for Bedrock models. There is currently a non-null constraint
        on the endpoint column so so we still need to send a placeholder. This is a workaround for
        going GA in 17.9 - the columns should be made nullable as a more permanent solution.
        https://gitlab.com/gitlab-org/gitlab/-/issues/507966
      */
      const valuesWithoutIamRole = omit(this.baseFormValues, 'iamRole');

      if (!this.isApiPlatform) {
        const endpoint =
          this.platform === SELF_HOSTED_MODEL_PLATFORMS.VERTEX_AI
            ? VERTEX_DUMMY_ENDPOINT
            : BEDROCK_DUMMY_ENDPOINT;

        return {
          ...valuesWithoutIamRole,
          ...this.iamRoleValues,
          endpoint,
          apiToken: '',
          provider: this.platform,
        };
      }

      return {
        apiToken: this.apiToken,
        provider: this.platform,
        ...valuesWithoutIamRole,
        ...this.iamRoleValues,
      };
    },
    // Only Bedrock models use an IAM role. When the platform changes away from Bedrock on a
    // model that has a stored role, send an empty value so the role is cleared.
    iamRoleValues() {
      if (this.isBedrockPlatform) return { iamRole: this.baseFormValues.iamRole };
      if (this.initialFormValues.iamRole) return { iamRole: '' };

      return {};
    },
    identifierPlaceholder() {
      if (!this.isApiPlatform) {
        return this.cloudPlatformIdentifierPrefix;
      }

      const { model } = this.baseFormValues;
      if (model && !Object.values(CLOUD_PROVIDER_MODELS).includes(model)) {
        return 'custom_openai/';
      }

      return '';
    },
    identifierLabelDescription() {
      let identifierLabel = 'provider/model-name';
      if (this.identifierPlaceholder.length > 0) {
        identifierLabel = `${this.identifierPlaceholder}model-name`;
      }

      return sprintf(
        s__('AdminSelfHostedModels|Provide the model identifier in the form of %{identifierLabel}'),
        { identifierLabel },
      );
    },
  },
  methods: {
    async onSubmit() {
      if (!this.hasValidInput) return;

      const { mutation } = this.mutationData;

      const mutationInput = {
        ...this.formValues,
        ...(this.isEditing
          ? {
              id: convertToGraphQLId('Ai::SelfHostedModel', this.initialFormValues.id),
            }
          : {}),
      };

      this.isSaving = true;
      try {
        const { data } = await this.$apollo.mutate({
          mutation,
          variables: {
            input: {
              ...mutationInput,
            },
          },
        });
        if (data) {
          const { errors } = data[this.mutationData.name];
          if (errors.length > 0) {
            this.onError(errors);
            this.isSaving = false;
            return;
          }

          this.isSaving = false;
          visitUrlWithAlerts(this.basePath, [
            {
              message: this.successMessage,
              variant: 'success',
            },
          ]);
        }
      } catch (error) {
        createAlert({
          message: this.$options.i18n.defaultError,
          error,
          captureError: true,
        });
        this.isSaving = false;
      }
    },
    onModelUpdate(selectedModel) {
      this.onInputField({ name: 'model' });
      this.baseFormValues.model = selectedModel;
    },
    // The name field and the platform-dependent fields render in separate
    // GlFormFields instances that share baseFormValues, so merge each instance's
    // emitted values instead of replacing the object (which would drop the
    // other instance's fields).
    onFormValuesInput(values) {
      this.baseFormValues = { ...this.baseFormValues, ...values };
    },
    // clears the validation error
    onInputField({ name }) {
      delete this.serverValidations[name];
    },
    onClick(event) {
      event.currentTarget.blur();
    },
    onPlatformUpdate(value) {
      this.platform = value;
    },
    onError(errors) {
      // TODO: Delegate sorting of errors to the back-end - the client should only need to consume these
      const error = errors[0];
      const SERVER_VALIDATION_ERRORS = {
        /* eslint-disable @gitlab/require-i18n-strings */
        name: 'Name has already been taken',
        endpoint: 'Endpoint is blocked',
        /* eslint-enable @gitlab/require-i18n-strings */
      };

      if (error.includes(SERVER_VALIDATION_ERRORS.endpoint)) {
        this.serverValidations = {
          ...this.serverValidations,
          endpoint: this.$options.i18n.invalidEndpointError,
        };
      }
      if (error.includes(SERVER_VALIDATION_ERRORS.name)) {
        this.serverValidations = {
          ...this.serverValidations,
          name: this.$options.i18n.nonUniqueDeploymentNameError,
        };
      }

      // Unrecognised error, display generic error message
      if (
        !error.includes(SERVER_VALIDATION_ERRORS.name) &&
        !error.includes(SERVER_VALIDATION_ERRORS.endpoint)
      ) {
        throw new Error(error);
      }
    },
  },
};
</script>
<template>
  <gl-form :id="$options.formId" @submit.prevent="onSubmit">
    <gl-form-fields
      :values="baseFormValues"
      :fields="$options.nameFormField"
      :form-id="$options.formId"
      :server-validations="serverValidations"
      @input="onFormValuesInput"
      @input-field="onInputField"
    >
      <template #group(name)-label-description>
        {{ s__('AdminSelfHostedModels|A unique and descriptive name for your deployment.') }}
      </template>
    </gl-form-fields>

    <gl-card class="gl-mb-5" header-class="gl-flex gl-items-center gl-justify-between">
      <template #header>
        <span id="platform-selector-label" class="gl-font-bold">{{
          s__('AdminSelfHostedModels|Platform')
        }}</span>
        <platform-selector
          :platform="platform"
          label-id="platform-selector-label"
          @update:platform="onPlatformUpdate"
        />
      </template>

      <beta-features-alert
        v-if="!betaModelsEnabled"
        class="gl-mb-5"
        :message="
          s__(
            'AdminSelfHostedModels|More models are available in beta. You can %{linkStart}turn on self-hosted model beta features%{linkEnd}.',
          )
        "
      />

      <gl-form-fields
        :key="`${platform}-form-fields`"
        :values="baseFormValues"
        :fields="platformFormFields"
        :form-id="$options.formId"
        :server-validations="serverValidations"
        @input="onFormValuesInput"
        @input-field="onInputField"
      >
        <template #group(model)-label-description>
          {{
            s__(
              'AdminSelfHostedModels|Select an appropriate model family from the list of approved GitLab models.',
            )
          }}
        </template>

        <template #input(model)>
          <model-selector
            :selected-model="baseFormValues.model"
            :is-loading="isSaving"
            @update:model="onModelUpdate"
          />
        </template>

        <template #group(endpoint)-label-description>
          {{
            s__(
              'AdminSelfHostedModels|Specify the URL endpoint where your self-hosted model is accessible',
            )
          }}
        </template>

        <template #group(identifier)-label-description>
          {{ identifierLabelDescription }}
        </template>

        <template #group(iamRole)-label-description>
          <gl-sprintf
            :message="
              s__(
                'AdminSelfHostedModels|Optional. Enter the ARN of an IAM role the AI Gateway assumes through AWS Security Token Service (STS) %{codeStart}AssumeRole%{codeEnd} to call Amazon Bedrock. The role\'s trust policy must require your GitLab instance ID, %{instanceId}, as %{codeStart}sts:ExternalId%{codeEnd}. %{linkStart}How do I configure LLM platforms%{linkEnd}?',
              )
            "
          >
            <template #instanceId>
              <code>{{ instanceId }}</code>
            </template>
            <template #code="{ content }">
              <code>{{ content }}</code>
            </template>
            <template #link="{ content }">
              <gl-link :href="$options.iamRoleHelpUrl" target="_blank">{{ content }}</gl-link>
            </template>
          </gl-sprintf>
        </template>
      </gl-form-fields>
      <input-copy-toggle-visibility
        v-if="isApiPlatform"
        v-model="apiToken"
        :value="apiToken"
        :label="s__('AdminSelfHostedModels|API Key (optional)')"
        :initial-visibility="false"
        :disabled="isSaving"
        :show-copy-button="false"
        :label-description="
          s__(
            'AdminSelfHostedModels|If required, provide the API token that grants access to your self-hosted model deployment.',
          )
        "
      />
      <gl-sprintf v-else :message="platformSetupMessage">
        <template #link="{ content }">
          <gl-link :href="$options.cloudPlatformSetupUrl" target="_blank">{{ content }} </gl-link>
        </template>
      </gl-sprintf>
    </gl-card>

    <div class="gl-pt-3">
      <gl-button
        type="submit"
        variant="confirm"
        class="js-no-auto-disable gl-mr-2"
        :loading="isSaving"
        @click="onClick"
      >
        {{ submitButtonText }}
      </gl-button>
      <test-connection-button
        class="gl-mr-2"
        :disabled="!hasValidInput"
        :connection-test-input="formValues"
      />
      <gl-button :href="basePath">
        {{ __('Cancel') }}
      </gl-button>
    </div>
  </gl-form>
</template>
