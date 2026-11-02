<script>
import { GlFormGroup, GlFormInput, GlFormTextarea, GlButton, GlIcon, GlSprintf } from '@gitlab/ui';
import csrf from '~/lib/utils/csrf';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import VisibilityLevelRadioButtons from '~/visibility_level/components/visibility_level_radio_buttons.vue';
import {
  VISIBILITY_LEVEL_LABELS,
  VISIBILITY_LEVELS_INTEGER_TO_STRING,
  VISIBILITY_TYPE_ICON,
} from '~/visibility_level/constants';
import { checkGroupNameRules } from '~/groups/group_name_rules';
import AvatarUploadDropzone from '~/vue_shared/components/avatar_upload_dropzone.vue';
import RepositorySizeLimitRegistrationCta from '~/groups_projects/components/repository_size_limit_registration_cta.vue';
import GroupSettingsReadme from './group_settings_readme.vue';

// Matches `Namespace` name validation.
const MAX_NAME_LENGTH = 255;

// An empty input and an unset limit both mean "no limit", so treat `''`,
// `null` and `undefined` the same when deciding whether the value changed.
const normalizeRepositorySizeLimit = (value) =>
  value === '' || value === null || value === undefined ? null : Number(value);

export default {
  name: 'GroupGeneralSettings',
  components: {
    GlFormGroup,
    GlFormInput,
    GlFormTextarea,
    GlButton,
    GlIcon,
    GlSprintf,
    HelpPageLink,
    AvatarUploadDropzone,
    RepositorySizeLimitRegistrationCta,
    GroupSettingsReadme,
    VisibilityLevelRadioButtons,
    RepositorySizeLimitField: () =>
      import('ee_component/groups_projects/components/repository_size_limit_field.vue'),
  },
  MAX_NAME_LENGTH,
  props: {
    groupId: {
      type: [String, Number],
      required: true,
    },
    groupName: {
      type: String,
      required: true,
    },
    groupDescription: {
      type: String,
      required: false,
      default: '',
    },
    groupAvatarUrl: {
      type: String,
      required: false,
      default: '',
    },
    groupAvatarRemovable: {
      type: Boolean,
      required: false,
      default: false,
    },
    maxDescriptionLength: {
      type: Number,
      required: true,
    },
    formAction: {
      type: String,
      required: true,
    },
    groupPath: {
      type: String,
      required: true,
    },
    groupReadmePath: {
      type: String,
      required: false,
      default: '',
    },
    readmeProjectPath: {
      type: String,
      required: false,
      default: '',
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
    visibilityLevel: {
      type: Number,
      required: true,
    },
    canChangeVisibilityLevel: {
      type: Boolean,
      required: false,
      default: false,
    },
    visibilityLevels: {
      type: Array,
      required: false,
      default: () => [],
    },
    visibilityLevelDescriptions: {
      type: Object,
      required: false,
      default: () => ({}),
      validator: (val) =>
        Object.keys(val).every((k) =>
          Object.values(VISIBILITY_LEVELS_INTEGER_TO_STRING).includes(k),
        ),
    },
    // Disabled visibility levels mapped to the reason they are disabled.
    disabledVisibilityLevels: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  data() {
    return {
      name: this.groupName,
      description: this.groupDescription,
      avatar: this.groupAvatarUrl,
      repositorySizeLimit: this.repositorySizeLimitValue,
      visibility: this.visibilityLevel,
      isSubmitting: false,
    };
  },
  computed: {
    csrfToken() {
      return csrf.token;
    },
    groupIdString() {
      return String(this.groupId);
    },
    isDescriptionOverLimit() {
      return (this.description || '').length > this.maxDescriptionLength;
    },
    isAvatarRemoved() {
      return this.avatar === null && this.groupAvatarRemovable;
    },
    avatarInputFieldName() {
      // While a removal is pending, the hidden `group[avatar]` field with an
      // empty value performs the removal, so the file input is unnamed.
      return this.isAvatarRemoved ? '' : 'group[avatar]';
    },
    nameValidationMessage() {
      return checkGroupNameRules(this.name) || '';
    },
    isNameValid() {
      return this.nameValidationMessage === '';
    },
    groupEntity() {
      return {
        id: this.groupId,
        name: this.name,
        avatarUrl: this.groupAvatarUrl,
      };
    },
    currentVisibilityLevelString() {
      return VISIBILITY_LEVELS_INTEGER_TO_STRING[this.visibilityLevel];
    },
    currentVisibilityLevelLabel() {
      return VISIBILITY_LEVEL_LABELS[this.currentVisibilityLevelString];
    },
    currentVisibilityLevelIcon() {
      return VISIBILITY_TYPE_ICON[this.currentVisibilityLevelString];
    },
    currentVisibilityLevelDescription() {
      return this.visibilityLevelDescriptions[this.currentVisibilityLevelString];
    },
    isFormDirty() {
      const nameChanged = this.name !== this.groupName;
      const descriptionChanged = (this.description || '') !== (this.groupDescription || '');
      const avatarChanged = this.avatar !== this.groupAvatarUrl;
      const repositorySizeLimitChanged =
        this.canEditRepositorySizeLimit &&
        normalizeRepositorySizeLimit(this.repositorySizeLimit) !==
          normalizeRepositorySizeLimit(this.repositorySizeLimitValue);
      const visibilityChanged =
        this.canChangeVisibilityLevel && this.visibility !== this.visibilityLevel;

      return (
        nameChanged ||
        descriptionChanged ||
        avatarChanged ||
        repositorySizeLimitChanged ||
        visibilityChanged
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
        this.avatar = this.groupAvatarUrl;
        return;
      }

      this.avatar = newValue;
    },
    handleSubmit(event) {
      // Defence in depth: the submit button is already disabled in these
      // states via `isSubmitDisabled`.
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
    data-testid="group-general-settings-form"
    @submit="handleSubmit"
  >
    <!-- Hidden form fields for Rails -->
    <input type="hidden" name="authenticity_token" :value="csrfToken" />
    <input type="hidden" name="_method" value="put" />
    <input type="hidden" name="update_section" value="js-general-settings" />

    <!-- Hidden field for avatar removal -->
    <input v-if="isAvatarRemoved" type="hidden" name="group[avatar]" value="" />

    <div class="row">
      <gl-form-group
        :label="s__('Groups|Group name')"
        label-for="group_name_edit"
        class="gl-col-md-5"
        :description="s__('Groups|Start with a letter, digit, basic emoji, or underscore.')"
        :state="isNameValid"
        :invalid-feedback="nameValidationMessage"
      >
        <gl-form-input
          id="group_name_edit"
          v-model="name"
          name="group[name]"
          :maxlength="$options.MAX_NAME_LENGTH"
          data-testid="group-name-field"
          :state="isNameValid"
          required
        />
      </gl-form-group>

      <gl-form-group
        :label="s__('Groups|Group ID')"
        label-for="group_general_settings_id"
        class="gl-col-md-4"
      >
        <gl-form-input id="group_general_settings_id" :value="groupId" readonly />
      </gl-form-group>
    </div>

    <div class="gl-mt-3">
      <avatar-upload-dropzone
        :value="avatar"
        :entity="groupEntity"
        :label="s__('Groups|Group avatar')"
        :input-field-name="avatarInputFieldName"
        :can-remove="groupAvatarRemovable"
        @input="handleAvatarInput"
      />
    </div>

    <div class="row gl-mt-6">
      <gl-form-group
        :label="s__('Groups|Group description (optional)')"
        label-for="group_description"
        class="gl-col-md-9"
      >
        <gl-form-textarea
          id="group_description"
          v-model="description"
          name="group[description]"
          rows="4"
          :character-count-limit="maxDescriptionLength"
        >
          <template #remaining-character-count-text="{ count }">
            {{ n__('%d character remaining', '%d characters remaining', count) }}
          </template>
          <template #character-count-over-limit-text="{ count }">
            {{ n__('%d character over limit', '%d characters over limit', count) }}
          </template>
        </gl-form-textarea>
      </gl-form-group>
    </div>

    <!-- Repository size limit: licensed field (EE-only component) -->
    <div v-if="canEditRepositorySizeLimit" class="row">
      <repository-size-limit-field
        v-model.number="repositorySizeLimit"
        field-name-prefix="group"
        :help-text="repositorySizeLimitHelpText"
      />
    </div>

    <!-- Registration features CTA (CE-visible) -->
    <div v-else-if="showRepositorySizeLimitCta" class="row">
      <repository-size-limit-registration-cta
        field-name-prefix="group"
        :service-ping-settings-path="servicePingSettingsPath"
      />
    </div>

    <div class="row">
      <gl-form-group :label="s__('Groups|Group README')" class="gl-col-md-5">
        <group-settings-readme
          :group-readme-path="groupReadmePath"
          :readme-project-path="readmeProjectPath"
          :group-path="groupPath"
          :group-id="groupIdString"
        />
      </gl-form-group>
    </div>

    <gl-form-group
      :label="__('Visibility level')"
      class="gl-mt-3"
      data-testid="group-visibility-level-field"
    >
      <template #label-description>
        {{ __('Who can see this group?') }}
        <help-page-link href="user/public_access" target="_blank">{{
          __('Learn about visibility levels.')
        }}</help-page-link>
      </template>

      <visibility-level-radio-buttons
        v-if="canChangeVisibilityLevel"
        :checked="visibility"
        name="group[visibility_level]"
        :visibility-levels="visibilityLevels"
        :visibility-level-descriptions="visibilityLevelDescriptions"
        :disabled-visibility-levels="disabledVisibilityLevels"
        @input="visibility = $event"
      >
        <template #disabled-reason="{ reason }">
          <gl-sprintf v-if="reason" :message="reason">
            <template #link="{ content }">
              <help-page-link href="user/public_access" target="_blank">{{
                content
              }}</help-page-link>
            </template>
          </gl-sprintf>
        </template>
      </visibility-level-radio-buttons>

      <div v-else data-testid="group-visibility-level-readonly">
        <gl-icon :name="currentVisibilityLevelIcon" />
        <strong>{{ currentVisibilityLevelLabel }}</strong>
        <p class="gl-mb-0 gl-text-subtle">{{ currentVisibilityLevelDescription }}</p>
      </div>
    </gl-form-group>

    <gl-button
      type="submit"
      variant="confirm"
      class="js-no-auto-disable"
      :loading="isSubmitting"
      :disabled="isSubmitDisabled"
      data-testid="save-group-general-settings-button"
    >
      {{ isSubmitting ? __('Saving changes') : s__('Groups|Save changes') }}
    </gl-button>
  </form>
</template>
