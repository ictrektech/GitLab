<script>
import { GlFormGroup, GlFormInput, GlFormTextarea, GlButton } from '@gitlab/ui';
import { n__, __, s__ } from '~/locale';
import csrf from '~/lib/utils/csrf';
import { checkRules } from '~/projects/project_name_rules';
import AvatarUploadDropzone from '~/vue_shared/components/avatar_upload_dropzone.vue';
import RepositorySizeLimitRegistrationCta from '~/groups_projects/components/repository_size_limit_registration_cta.vue';
import TopicsTokenSelector from '~/projects/settings/topics/components/topics_token_selector.vue';

export default {
  name: 'ProjectGeneralSettings',
  components: {
    GlFormGroup,
    GlFormInput,
    GlFormTextarea,
    GlButton,
    AvatarUploadDropzone,
    RepositorySizeLimitRegistrationCta,
    TopicsTokenSelector,
    RepositorySizeLimitField: () =>
      import('ee_component/groups_projects/components/repository_size_limit_field.vue'),
  },
  i18n: {
    projectName: __('Project name'),
    projectNameHelp: __('Start with a letter, digit, emoji, or underscore.'),
    projectId: __('Project ID'),
    projectAvatar: __('Project avatar'),
    projectDescription: s__('ProjectSettings|Project description (optional)'),
    classificationLabel: __('Classification Label (optional)'),
    saveChanges: __('Save changes'),
    saveChangesAriaLabel: s__('ProjectSettings|Save changes for naming, description, topics'),
    savingChanges: __('Saving changes'),
    charactersRemaining: (char) => n__('%d character remaining', '%d characters remaining', char),
    charactersOverLimit: (char) => n__('%d character over limit', '%d characters over limit', char),
  },
  props: {
    projectId: {
      type: [String, Number],
      required: true,
    },
    projectName: {
      type: String,
      required: true,
    },
    projectDescription: {
      type: String,
      required: false,
      default: '',
    },
    projectAvatarUrl: {
      type: String,
      required: false,
      default: '',
    },
    // Whether the project has an uploaded avatar that can be removed. False
    // e.g. when the avatar comes from a `logo` file committed to the
    // repository.
    projectAvatarRemovable: {
      type: Boolean,
      required: false,
      default: false,
    },
    projectTopics: {
      type: Array,
      required: false,
      default: () => [],
    },
    maxDescriptionLength: {
      type: Number,
      required: true,
    },
    formAction: {
      type: String,
      required: true,
    },
    organizationId: {
      type: String,
      required: true,
    },
    canEditRepositorySizeLimit: {
      type: Boolean,
      required: false,
      default: false,
    },
    repositorySizeLimitValue: {
      type: [Number, String],
      required: false,
      default: null,
    },
    repositorySizeLimitHelpText: {
      type: String,
      required: false,
      default: '',
    },
    showRepositorySizeLimitCta: {
      type: Boolean,
      required: false,
      default: false,
    },
    servicePingSettingsPath: {
      type: String,
      required: false,
      default: '',
    },
    externalAuthorizationEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    externalAuthorizationClassificationLabel: {
      type: String,
      required: false,
      default: '',
    },
    externalAuthorizationHelpText: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      name: this.projectName,
      description: this.projectDescription,
      avatar: this.projectAvatarUrl,
      topics: this.projectTopics,
      repositorySizeLimit: this.repositorySizeLimitValue,
      classificationLabel: this.externalAuthorizationClassificationLabel,
      isSubmitting: false,
    };
  },
  computed: {
    csrfToken() {
      return csrf.token;
    },
    isDescriptionOverLimit() {
      return (this.description || '').length > this.maxDescriptionLength;
    },
    isAvatarRemoved() {
      return this.avatar === null && this.projectAvatarRemovable;
    },
    avatarInputFieldName() {
      // While a removal is pending, the hidden `project[avatar]` field with
      // an empty value performs the removal. An empty file input could not
      // override it anyway (its multipart part carries no filename, so Rack
      // drops it before Rails sees it); unnaming the input here is defence
      // in depth against middleware or proxy quirks.
      return this.isAvatarRemoved ? '' : 'project[avatar]';
    },
    nameValidationMessage() {
      return checkRules(this.name);
    },
    isNameValid() {
      return this.nameValidationMessage === '';
    },
    projectEntity() {
      return {
        id: this.projectId,
        name: this.name,
        avatarUrl: this.projectAvatarUrl,
      };
    },
    submitButtonText() {
      return this.isSubmitting ? this.$options.i18n.savingChanges : this.$options.i18n.saveChanges;
    },
    topicsString() {
      return this.topics.map((topic) => topic.name).join(', ');
    },
    initialTopicsString() {
      return this.projectTopics.map((topic) => topic.name).join(', ');
    },
    isFormDirty() {
      // Check if any field has changed from its initial value
      const nameChanged = this.name !== this.projectName;
      const descriptionChanged = (this.description || '') !== (this.projectDescription || '');
      const avatarChanged = this.avatar !== this.projectAvatarUrl;
      const topicsChanged = this.topicsString !== this.initialTopicsString;
      const repositorySizeLimitChanged =
        this.canEditRepositorySizeLimit &&
        this.repositorySizeLimit !== this.repositorySizeLimitValue;
      const classificationLabelChanged =
        this.externalAuthorizationEnabled &&
        (this.classificationLabel || '') !== (this.externalAuthorizationClassificationLabel || '');

      return (
        nameChanged ||
        descriptionChanged ||
        avatarChanged ||
        topicsChanged ||
        repositorySizeLimitChanged ||
        classificationLabelChanged
      );
    },
    isSubmitDisabled() {
      return (
        !this.isFormDirty || this.isDescriptionOverLimit || !this.isNameValid || this.isSubmitting
      );
    },
  },
  methods: {
    handleAvatarInput(newValue) {
      if (newValue === null && this.avatar instanceof File) {
        // Discarding a locally staged file restores the persisted avatar.
        // `null` (avatar removal) is reserved for explicitly removing a
        // removable persisted avatar.
        this.avatar = this.projectAvatarUrl;
        return;
      }

      this.avatar = newValue;
    },
    handleTopicsUpdate(selectedTopics) {
      this.topics = selectedTopics;
    },
    handleSubmit(event) {
      // Defence in depth: the submit button is already disabled in these
      // states via `isSubmitDisabled`. The button opts out of the global
      // auto-disable in main.js with the `js-no-auto-disable` class, so a
      // cancelled submission cannot leave it disabled.
      if (this.isDescriptionOverLimit || !this.isNameValid) {
        event.preventDefault();
        this.isSubmitting = false;
        return;
      }

      this.isSubmitting = true;
    },
  },
};
</script>

<template>
  <form
    :action="formAction"
    method="post"
    enctype="multipart/form-data"
    class="js-general-settings-form"
    data-testid="general-settings-form"
    @submit="handleSubmit"
  >
    <!-- Hidden form fields for Rails -->
    <input type="hidden" name="authenticity_token" :value="csrfToken" />
    <input type="hidden" name="_method" value="put" />
    <input type="hidden" name="update_section" value="js-general-settings" />

    <!-- Hidden field for topics -->
    <input
      id="project_topic_list_field"
      type="hidden"
      name="project[topics]"
      :value="topicsString"
    />

    <!-- Hidden field for avatar removal -->
    <input v-if="isAvatarRemoved" type="hidden" name="project[avatar]" value="" />

    <div class="row">
      <gl-form-group
        :label="$options.i18n.projectName"
        label-for="project_name_edit"
        class="gl-col-md-5"
        :description="$options.i18n.projectNameHelp"
        :state="isNameValid"
        :invalid-feedback="nameValidationMessage"
      >
        <gl-form-input
          id="project_name_edit"
          v-model="name"
          name="project[name]"
          data-testid="project-name-field"
          :state="isNameValid"
          required
        />
      </gl-form-group>

      <gl-form-group :label="$options.i18n.projectId" label-for="project_id" class="gl-col-md-4">
        <gl-form-input id="project_id" :value="projectId" readonly />
      </gl-form-group>
    </div>

    <div class="gl-mt-3">
      <avatar-upload-dropzone
        :value="avatar"
        :entity="projectEntity"
        :label="$options.i18n.projectAvatar"
        :input-field-name="avatarInputFieldName"
        :can-remove="projectAvatarRemovable"
        @input="handleAvatarInput"
      />
    </div>

    <div class="row gl-mt-6">
      <gl-form-group
        :label="$options.i18n.projectDescription"
        label-for="project_description"
        class="gl-col-md-9"
      >
        <gl-form-textarea
          id="project_description"
          v-model="description"
          name="project[description]"
          rows="4"
          :character-count-limit="maxDescriptionLength"
        >
          <template #remaining-character-count-text="{ count }">
            {{ $options.i18n.charactersRemaining(count) }}
          </template>
          <template #character-count-over-limit-text="{ count }">
            {{ $options.i18n.charactersOverLimit(count) }}
          </template>
        </gl-form-textarea>
      </gl-form-group>
    </div>

    <!-- Classification Label (EE feature for external authorization) -->
    <div v-if="externalAuthorizationEnabled" class="row">
      <gl-form-group
        :label="$options.i18n.classificationLabel"
        label-for="project_external_authorization_classification_label"
        class="gl-col-md-9"
      >
        <gl-form-input
          id="project_external_authorization_classification_label"
          v-model="classificationLabel"
          type="text"
          name="project[external_authorization_classification_label]"
          data-testid="classification-label-field"
        />
        <template v-if="externalAuthorizationHelpText" #description>
          <span>{{ externalAuthorizationHelpText }}</span>
        </template>
      </gl-form-group>
    </div>

    <!-- Repository size limit: licensed field (EE-only component) -->
    <div v-if="canEditRepositorySizeLimit" class="row">
      <repository-size-limit-field
        v-model.number="repositorySizeLimit"
        field-name-prefix="project"
        :help-text="repositorySizeLimitHelpText"
      />
    </div>

    <!-- Registration features CTA (CE-visible) -->
    <div v-else-if="showRepositorySizeLimitCta" class="row">
      <repository-size-limit-registration-cta
        field-name-prefix="project"
        :service-ping-settings-path="servicePingSettingsPath"
      />
    </div>

    <div class="row">
      <div class="gl-col-md-9">
        <topics-token-selector
          :selected="topics"
          :organization-id="organizationId"
          @update="handleTopicsUpdate"
        />
      </div>
    </div>

    <gl-button
      type="submit"
      variant="confirm"
      class="js-no-auto-disable"
      :loading="isSubmitting"
      :disabled="isSubmitDisabled"
      data-testid="save-naming-topics-avatar-button"
      :aria-label="$options.i18n.saveChangesAriaLabel"
    >
      {{ submitButtonText }}
    </gl-button>
  </form>
</template>
