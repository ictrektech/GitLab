<script>
import { isEqual } from 'lodash-es';
import {
  GlButton,
  GlForm,
  GlFormGroup,
  GlFormInput,
  GlFormTextarea,
  GlIcon,
  GlToggle,
} from '@gitlab/ui';
import { s__, __ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { SCAN_TRIGGER_DEFINITIONS } from '~/security_configuration/constants';
import { readScanProfileTriggers } from 'ee/security_configuration/graphql/scan_profiles/map_scan_profile_variables';
import AdvancedConfigurationEditor from './advanced_configuration_editor.vue';
import TriggerInfoPopover from './trigger_info_popover.vue';
import TriggerVariableTable from './trigger_variable_table.vue';
import {
  allowedTriggersFor,
  buildEditableConfigurationRows,
  isPushProtectionTrigger,
  isTriggerConfigurable,
  isValidConfigurationValue,
  scanTypeHelpLink,
} from './utils';
import { variableDefinitionsFor } from './variable_definitions';

const i18n = {
  name: __('Name'),
  description: __('Description'),
  scanTriggers: s__('ScanProfiles|Scan triggers'),
  scanTriggersInfo: s__(
    'ScanProfiles|Toggle which triggers are enabled and customize their settings.',
  ),
  save: s__('ScanProfiles|Save changes'),
  create: s__('SecurityConfiguration|Create profile'),
  cancel: __('Cancel'),
};

export default {
  name: 'ScanProfileEditForm',
  components: {
    CrudComponent,
    GlButton,
    GlForm,
    GlFormGroup,
    GlFormInput,
    GlFormTextarea,
    GlIcon,
    GlToggle,
    AdvancedConfigurationEditor,
    TriggerInfoPopover,
    TriggerVariableTable,
  },
  props: {
    profile: {
      type: Object,
      required: true,
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['save', 'cancel'],
  data() {
    const initialTriggers = [...(this.profile.triggers ?? [])];
    const { triggerConfigurations } = readScanProfileTriggers(this.profile.triggerSettings ?? []);
    return {
      form: {
        name: this.profile.name ?? '',
        description: this.profile.description ?? '',
        enabledTriggers: initialTriggers,
      },
      triggerConfigurations,
      initialTriggerConfigurations: triggerConfigurations,
      initialTriggers,
      collapsed: true,
    };
  },
  computed: {
    isEdit() {
      return Boolean(this.profile.id);
    },
    triggerOptions() {
      return allowedTriggersFor(this.profile.scanType)
        .map((triggerType) => {
          const definition = SCAN_TRIGGER_DEFINITIONS[triggerType];
          if (!definition) return null;
          return { value: triggerType, ...definition };
        })
        .filter(Boolean);
    },
    hasValidationErrors() {
      return (
        this.form.name.trim().length === 0 ||
        this.form.enabledTriggers.length === 0 ||
        this.hasInvalidConfigurationValues
      );
    },
    hasInvalidConfigurationValues() {
      return this.advancedConfiguration.rows.some(({ setting, triggerValues }) =>
        triggerValues.some(
          ({ value }) => !isValidConfigurationValue(this.variableDefinitions[setting], value),
        ),
      );
    },
    isFormValid() {
      return !this.hasValidationErrors;
    },
    triggersChanged() {
      const before = [...this.initialTriggers].sort();
      const after = [...this.form.enabledTriggers].sort();
      const enabledTriggersChanged =
        before.length !== after.length || before.some((t, i) => t !== after[i]);
      // A config-only edit (no trigger toggled) still needs to reach the update mutation,
      // since the drawer only sends triggerConfigurations when this flag is true.
      const configurationChanged = !isEqual(
        this.triggerConfigurations,
        this.initialTriggerConfigurations,
      );
      return enabledTriggersChanged || configurationChanged;
    },
    variableDefinitions() {
      return variableDefinitionsFor(this.profile.scanType);
    },
    advancedConfiguration() {
      return buildEditableConfigurationRows({
        scanType: this.profile.scanType,
        enabledTriggers: this.form.enabledTriggers,
        triggerConfigurations: this.triggerConfigurations,
      });
    },
    hasEnabledTriggers() {
      return this.form.enabledTriggers.length > 0;
    },
    hasConfigurableTriggers() {
      return this.advancedConfiguration.configurableTriggers.length > 0;
    },
  },
  methods: {
    handleSubmit() {
      this.$emit('save', {
        profileId: this.profile.id,
        scanType: this.profile.scanType,
        name: this.form.name.trim(),
        description: this.form.description.trim(),
        enabledTriggers: this.form.enabledTriggers,
        triggerConfigurations: this.triggerConfigurations,
        triggersChanged: this.triggersChanged,
      });
    },
    handleCancel() {
      this.$emit('cancel');
    },
    learnMoreLink(option) {
      return option.helpLink || scanTypeHelpLink(this.profile.scanType);
    },
    isPushProtection(option) {
      return isPushProtectionTrigger({ triggerType: option.value });
    },
    isTriggerEnabled(triggerType) {
      return this.form.enabledTriggers.includes(triggerType);
    },
    variableRows(triggerType) {
      return this.advancedConfiguration.rowsByTrigger.get(triggerType) ?? [];
    },
    toggleTrigger(triggerType, enabled) {
      if (enabled) {
        // Give the newly enabled trigger the same values the other enabled triggers already
        // share, so it starts in sync rather than unconfigured (and the row doesn't suddenly
        // read as "varies" just because the new trigger has nothing set yet).
        const sharedValues = Object.fromEntries(
          this.advancedConfiguration.rows
            .filter((row) => !row.varies)
            .map((row) => [row.setting, row.value]),
        );
        this.form.enabledTriggers = [...this.form.enabledTriggers, triggerType];
        if (
          Object.keys(sharedValues).length &&
          isTriggerConfigurable(this.profile.scanType, triggerType)
        ) {
          this.triggerConfigurations = {
            ...this.triggerConfigurations,
            [triggerType]: { ...sharedValues, ...this.triggerConfigurations[triggerType] },
          };
        }
      } else {
        this.form.enabledTriggers = this.form.enabledTriggers.filter((t) => t !== triggerType);
      }
    },
    setConfigurationValue({ setting, triggerType, value }) {
      const configuration = { ...this.triggerConfigurations[triggerType] };
      // null/undefined means "remove this setting" (the table's remove button), so drop the key
      // entirely rather than sending an explicit null the backend's input type may reject.
      if (value === null || value === undefined) {
        delete configuration[setting];
      } else {
        configuration[setting] = value;
      }
      this.triggerConfigurations = {
        ...this.triggerConfigurations,
        [triggerType]: configuration,
      };
    },
  },
  i18n,
};
</script>

<template>
  <gl-form data-testid="scan-profile-edit-form" @submit.prevent="handleSubmit">
    <div class="gl-mb-4 gl-flex gl-items-center gl-justify-end gl-gap-3">
      <gl-button data-testid="scan-profile-edit-cancel" :disabled="isSaving" @click="handleCancel">
        {{ $options.i18n.cancel }}
      </gl-button>
      <gl-button
        type="submit"
        variant="confirm"
        :loading="isSaving"
        :disabled="!isFormValid"
        data-testid="scan-profile-edit-save"
      >
        {{ isEdit ? $options.i18n.save : $options.i18n.create }}
      </gl-button>
    </div>

    <gl-form-group :label="$options.i18n.name" label-for="scan-profile-name">
      <gl-form-input
        id="scan-profile-name"
        v-model="form.name"
        data-testid="scan-profile-name-input"
        autocomplete="off"
        maxlength="255"
      />
    </gl-form-group>

    <gl-form-group :label="$options.i18n.description" label-for="scan-profile-description">
      <gl-form-textarea
        id="scan-profile-description"
        v-model="form.description"
        data-testid="scan-profile-description-input"
        :no-resize="false"
        rows="3"
        maxlength="2047"
      />
    </gl-form-group>

    <h4 class="gl-heading-4 gl-mb-1">{{ $options.i18n.scanTriggers }}</h4>
    <p class="gl-mb-3 gl-text-subtle">{{ $options.i18n.scanTriggersInfo }}</p>

    <gl-form-group class="gl-mb-4">
      <crud-component
        v-for="option in triggerOptions"
        :key="option.anchor"
        :is-collapsible="true"
        :collapsed="collapsed"
        :anchor-id="option.anchor"
        plain-toggle
        title-tag="h5"
        class="hover:!gl-bg-neutral-100 dark:hover:!gl-bg-neutral-800"
        :style="{
          '--gl-toggle-switch-track-color-checked-default': 'var(--gl-color-green-500)',
          '--gl-toggle-switch-track-border-color-checked-default': 'var(--gl-color-green-500)',
        }"
        :data-testid="`scan-profile-trigger-${option.anchor}`"
        body-class="!gl-p-3"
      >
        <template #title>
          <span :data-testid="`scan-profile-trigger-title-${option.anchor}`">
            <gl-icon v-if="option.icon" :name="option.icon" />
            {{ option.title }}
          </span>
          <trigger-info-popover
            :anchor="option.anchor"
            :title="option.title"
            :description="option.infoDescription"
            :help-link="learnMoreLink(option)"
          />
        </template>
        <template #actions>
          <gl-toggle
            :value="isTriggerEnabled(option.value)"
            :label="option.title"
            label-position="hidden"
            class="gl-self-center"
            :data-testid="`scan-profile-trigger-toggle-${option.anchor}`"
            @change="toggleTrigger(option.value, $event)"
          />
        </template>

        <div
          v-if="option.targetBranch || option.results"
          class="gl-mb-4 gl-flex gl-flex-col gl-gap-1"
        >
          <div v-if="option.targetBranch" class="gl-grid gl-grid-cols-5 gl-gap-3">
            <span class="gl-text-subtle">{{ s__('ScanProfiles|Target branch') }}</span>
            <span class="gl-col-span-4 gl-font-semibold">{{ option.targetBranch }}</span>
          </div>
          <div v-if="option.results" class="gl-grid gl-grid-cols-5 gl-gap-3">
            <span class="gl-text-subtle">{{ s__('ScanProfiles|Results') }}</span>
            <span class="gl-col-span-4 gl-font-semibold">{{ option.results }}</span>
          </div>
        </div>

        <template v-if="variableRows(option.value).length || isPushProtection(option)">
          <h6 class="gl-heading-5 gl-mb-2">
            {{ s__('ScanProfiles|Advanced configuration for this trigger') }}
          </h6>
          <trigger-variable-table
            v-if="variableRows(option.value).length"
            :trigger-title="option.title"
            :rows="variableRows(option.value)"
            :variable-definitions="variableDefinitions"
          />
          <p v-else class="gl-mb-4 gl-text-subtle">
            {{ s__("ScanProfiles|Push protection can't carry analyzer configuration.") }}
          </p>
        </template>
      </crud-component>
    </gl-form-group>

    <advanced-configuration-editor
      v-if="hasEnabledTriggers"
      :scan-type="profile.scanType"
      :rows="advancedConfiguration.rows"
      :configurable-triggers="advancedConfiguration.configurableTriggers"
      :has-configurable-triggers="hasConfigurableTriggers"
      @set-value="setConfigurationValue"
    />
  </gl-form>
</template>
