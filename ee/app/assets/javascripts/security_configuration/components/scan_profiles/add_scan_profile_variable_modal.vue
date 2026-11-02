<script>
import {
  GlBadge,
  GlModal,
  GlFormGroup,
  GlFormInput,
  GlFormRadioGroup,
  GlFormCheckbox,
  GlCollapsibleListbox,
} from '@gitlab/ui';
import { s__, __ } from '~/locale';
import { BOOLEAN_OPTIONS, SCAN_TRIGGER_DEFINITIONS } from '~/security_configuration/constants';
import {
  isSetConfigurationValue,
  isValidConfigurationValue,
  multiSelectToggleText,
  numberInvalidFeedback,
} from './utils';
import StringListTokenSelector from './string_list_token_selector.vue';
import {
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
  VALUE_TYPE_NUMBER,
  VALUE_TYPE_STRING_LIST,
} from './variable_definitions';

const i18n = {
  save: s__('ScanProfiles|Add variable'),
  cancel: __('Cancel'),
  variable: s__('ScanProfiles|Variable'),
  value: s__('ScanProfiles|Value'),
  valueByTrigger: s__('ScanProfiles|Value by trigger'),
  applyToAll: s__('ScanProfiles|Apply to all enabled triggers'),
  noVariablesMatchSearch: s__('ScanProfiles|No variables found.'),
  allVariablesAdded: s__('ScanProfiles|All available variables have already been added.'),
};

const emptyValueFor = (valueType) => {
  if (valueType === VALUE_TYPE_BOOLEAN || valueType === VALUE_TYPE_ENUM) return null;
  return valueType === VALUE_TYPE_STRING_LIST || valueType === VALUE_TYPE_MULTI_SELECT ? [] : '';
};

export default {
  name: 'AddScanProfileVariableModal',
  components: {
    GlBadge,
    GlModal,
    GlFormGroup,
    GlFormInput,
    GlFormRadioGroup,
    GlFormCheckbox,
    GlCollapsibleListbox,
    StringListTokenSelector,
  },
  props: {
    visible: {
      type: Boolean,
      required: false,
      default: false,
    },
    title: {
      type: String,
      required: true,
    },
    variableDefinitions: {
      type: Object,
      required: true,
    },
    existingSettings: {
      type: Array,
      required: false,
      default: () => [],
    },
    configurableTriggers: {
      type: Array,
      required: true,
    },
  },
  emits: ['add', 'cancel'],
  data() {
    return {
      selectedSetting: '',
      searchTerm: '',
      sharedValue: '',
      applyToAll: true,
      triggerValues: {},
    };
  },
  computed: {
    definition() {
      return this.variableDefinitions[this.selectedSetting];
    },
    unaddedVariables() {
      return Object.entries(this.variableDefinitions).filter(
        ([key]) => !this.existingSettings.includes(key),
      );
    },
    availableItems() {
      const term = this.searchTerm.trim().toLowerCase();
      return this.unaddedVariables
        .filter(
          ([key, def]) =>
            !term || def.label.toLowerCase().includes(term) || key.toLowerCase().includes(term),
        )
        .map(([key, def]) => ({
          value: key,
          text: def.label,
          envVar: def.envVar,
          description: def.description,
        }));
    },
    // Distinguishes "you've already added every variable there is" from "your search matched
    // none of the ones still available" - very different situations for the same empty list.
    noResultsText() {
      return this.unaddedVariables.length ? i18n.noVariablesMatchSearch : i18n.allVariablesAdded;
    },
    variableToggleText() {
      return this.definition?.label ?? s__('ScanProfiles|Select a variable');
    },
    showApplyToAllCheckbox() {
      return this.configurableTriggers.length > 1;
    },
    isSharedValueActive() {
      return !this.showApplyToAllCheckbox || this.applyToAll;
    },
    radioOptions() {
      if (!this.definition) return [];
      if (this.definition.valueType === VALUE_TYPE_BOOLEAN) {
        return BOOLEAN_OPTIONS;
      }
      return this.definition.options ?? [];
    },
    canSave() {
      if (!this.selectedSetting) return false;
      const valueType = this.definition?.valueType;
      if (this.isSharedValueActive) {
        return (
          isSetConfigurationValue(this.sharedValue, valueType) && this.isValid(this.sharedValue)
        );
      }
      const values = Object.values(this.triggerValues);
      return (
        values.some((value) => isSetConfigurationValue(value, valueType)) &&
        values.every((value) => this.isValid(value))
      );
    },
    sharedValueState() {
      return !this.isSharedValueActive || this.isValid(this.sharedValue) ? null : false;
    },
    invalidFeedback() {
      return this.isNumber(this.definition?.valueType)
        ? numberInvalidFeedback(this.definition.label, this.definition)
        : '';
    },
    actionPrimaryProps() {
      return {
        text: i18n.save,
        attributes: { variant: 'confirm', disabled: !this.canSave },
      };
    },
    actionCancelProps() {
      return { text: i18n.cancel };
    },
  },
  watch: {
    selectedSetting(setting) {
      const valueType = this.variableDefinitions[setting]?.valueType;
      this.sharedValue = emptyValueFor(valueType);
      this.triggerValues = Object.fromEntries(
        this.configurableTriggers.map(({ value }) => [value, emptyValueFor(valueType)]),
      );
    },
  },
  methods: {
    triggerLabel(triggerType) {
      return SCAN_TRIGGER_DEFINITIONS[triggerType]?.title ?? triggerType;
    },
    isStringList(valueType) {
      return valueType === VALUE_TYPE_STRING_LIST;
    },
    isMultiSelect(valueType) {
      return valueType === VALUE_TYPE_MULTI_SELECT;
    },
    isNumber(valueType) {
      return valueType === VALUE_TYPE_NUMBER;
    },
    valueToggleText(value) {
      return multiSelectToggleText(this.definition, value);
    },
    isValid(value) {
      return isValidConfigurationValue(this.definition, value);
    },
    valueState(value) {
      return this.isValid(value) ? null : false;
    },
    isEnumOrBoolean(valueType) {
      return valueType === VALUE_TYPE_BOOLEAN || valueType === VALUE_TYPE_ENUM;
    },
    setTriggerValue(triggerType, value) {
      this.triggerValues = { ...this.triggerValues, [triggerType]: value };
    },
    reset() {
      this.selectedSetting = '';
      this.searchTerm = '';
      this.sharedValue = '';
      this.applyToAll = true;
      this.triggerValues = {};
    },
    handleSave() {
      if (!this.canSave) return;
      const valueType = this.definition?.valueType;
      const values = this.isSharedValueActive
        ? Object.fromEntries(
            this.configurableTriggers.map(({ value }) => [value, this.sharedValue]),
          )
        : Object.fromEntries(
            Object.entries(this.triggerValues).filter(([, value]) =>
              isSetConfigurationValue(value, valueType),
            ),
          );

      this.$emit('add', { setting: this.selectedSetting, values });
      this.reset();
    },
    handleHide({ trigger }) {
      // GlModal's own `canceled` event only covers the explicit Cancel button, not the
      // header close button, ESC, or a backdrop click, so those closes never reset the
      // modal and it can't be reopened. `hide` fires for every close reason instead.
      if (trigger === 'ok') return;
      this.reset();
      this.$emit('cancel');
    },
  },
  i18n,
};
</script>

<template>
  <gl-modal
    :visible="visible"
    :title="title"
    modal-id="add-scan-profile-variable-modal"
    size="sm"
    :action-primary="actionPrimaryProps"
    :action-cancel="actionCancelProps"
    @primary="handleSave"
    @hide="handleHide"
  >
    <gl-form-group :label="$options.i18n.variable" label-for="scan-profile-variable-picker">
      <gl-collapsible-listbox
        id="scan-profile-variable-picker"
        block
        searchable
        panel-match-trigger-width
        :items="availableItems"
        :selected="selectedSetting"
        :toggle-text="variableToggleText"
        :search-term="searchTerm"
        :no-results-text="noResultsText"
        data-testid="scan-profile-variable-picker"
        @search="searchTerm = $event"
        @select="selectedSetting = $event"
      >
        <template #list-item="{ item }">
          <div class="gl-py-2">
            <div class="gl-mb-1 gl-flex gl-items-center gl-gap-2">
              <span class="gl-font-bold">{{ item.text }}</span>
              <gl-badge variant="neutral" size="sm" class="gl-font-monospace">{{
                item.envVar
              }}</gl-badge>
            </div>
            <div class="gl-text-sm gl-text-subtle">{{ item.description }}</div>
          </div>
        </template>
      </gl-collapsible-listbox>
    </gl-form-group>

    <template v-if="definition">
      <gl-form-group
        class="gl-mt-5"
        :label="$options.i18n.value"
        label-for="scan-profile-variable-value"
        :state="sharedValueState"
        :invalid-feedback="invalidFeedback"
      >
        <gl-form-radio-group
          v-if="isEnumOrBoolean(definition.valueType)"
          id="scan-profile-variable-value"
          v-model="sharedValue"
          :disabled="!isSharedValueActive"
          :options="radioOptions"
        />
        <string-list-token-selector
          v-else-if="isStringList(definition.valueType)"
          v-model="sharedValue"
          :aria-label="$options.i18n.value"
          :disabled="!isSharedValueActive"
          :placeholder="definition.placeholder"
          :text-input-attrs="{ id: 'scan-profile-variable-value' }"
        />
        <gl-collapsible-listbox
          v-else-if="isMultiSelect(definition.valueType)"
          v-model="sharedValue"
          toggle-id="scan-profile-variable-value"
          multiple
          :disabled="!isSharedValueActive"
          :items="definition.options"
          :toggle-text="valueToggleText(sharedValue)"
        />
        <gl-form-input
          v-else-if="isNumber(definition.valueType)"
          id="scan-profile-variable-value"
          v-model="sharedValue"
          type="number"
          :disabled="!isSharedValueActive"
          :min="definition.min"
          :max="definition.max"
          :placeholder="definition.placeholder"
          :state="sharedValueState"
        />
        <gl-form-input
          v-else
          id="scan-profile-variable-value"
          v-model="sharedValue"
          :disabled="!isSharedValueActive"
          :placeholder="definition.placeholder"
        />
        <gl-form-checkbox
          v-if="showApplyToAllCheckbox"
          v-model="applyToAll"
          class="gl-mt-3"
          data-testid="scan-profile-variable-apply-to-all"
        >
          {{ $options.i18n.applyToAll }}
        </gl-form-checkbox>
      </gl-form-group>

      <div
        v-if="showApplyToAllCheckbox && !applyToAll"
        class="gl-mt-5"
        data-testid="scan-profile-variable-per-trigger"
      >
        <h5 class="gl-heading-5 gl-mb-4 gl-mt-0">{{ $options.i18n.valueByTrigger }}</h5>
        <gl-form-group
          v-for="trigger in configurableTriggers"
          :key="trigger.value"
          :label="triggerLabel(trigger.value)"
          :label-for="`scan-profile-variable-value-${trigger.value}`"
          :state="valueState(triggerValues[trigger.value])"
          :invalid-feedback="invalidFeedback"
        >
          <gl-form-radio-group
            v-if="isEnumOrBoolean(definition.valueType)"
            :id="`scan-profile-variable-value-${trigger.value}`"
            :checked="triggerValues[trigger.value]"
            :options="radioOptions"
            @input="setTriggerValue(trigger.value, $event)"
          />
          <string-list-token-selector
            v-else-if="isStringList(definition.valueType)"
            :value="triggerValues[trigger.value]"
            :aria-label="triggerLabel(trigger.value)"
            :placeholder="definition.placeholder"
            :text-input-attrs="{ id: `scan-profile-variable-value-${trigger.value}` }"
            @input="setTriggerValue(trigger.value, $event)"
          />
          <gl-collapsible-listbox
            v-else-if="isMultiSelect(definition.valueType)"
            :toggle-id="`scan-profile-variable-value-${trigger.value}`"
            multiple
            :items="definition.options"
            :selected="triggerValues[trigger.value]"
            :toggle-text="valueToggleText(triggerValues[trigger.value])"
            @select="setTriggerValue(trigger.value, $event)"
          />
          <gl-form-input
            v-else-if="isNumber(definition.valueType)"
            :id="`scan-profile-variable-value-${trigger.value}`"
            type="number"
            :value="triggerValues[trigger.value]"
            :min="definition.min"
            :max="definition.max"
            :placeholder="definition.placeholder"
            :state="valueState(triggerValues[trigger.value])"
            @input="setTriggerValue(trigger.value, $event)"
          />
          <gl-form-input
            v-else
            :id="`scan-profile-variable-value-${trigger.value}`"
            :value="triggerValues[trigger.value]"
            :placeholder="definition.placeholder"
            @input="setTriggerValue(trigger.value, $event)"
          />
        </gl-form-group>
      </div>
    </template>
  </gl-modal>
</template>
