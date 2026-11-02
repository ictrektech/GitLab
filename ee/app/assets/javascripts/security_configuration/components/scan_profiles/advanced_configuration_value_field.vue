<script>
import {
  GlButton,
  GlCollapsibleListbox,
  GlFormGroup,
  GlFormInput,
  GlFormRadioGroup,
  GlFormSelect,
} from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { BOOLEAN_OPTIONS } from '~/security_configuration/constants';
import StringListTokenSelector from './string_list_token_selector.vue';
import { isValidConfigurationValue, multiSelectToggleText, numberInvalidFeedback } from './utils';
import {
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
  VALUE_TYPE_NUMBER,
  VALUE_TYPE_STRING_LIST,
} from './variable_definitions';

export default {
  name: 'AdvancedConfigurationValueField',
  components: {
    GlButton,
    GlCollapsibleListbox,
    GlFormGroup,
    GlFormInput,
    GlFormRadioGroup,
    GlFormSelect,
    StringListTokenSelector,
  },
  props: {
    value: {
      type: [String, Number, Boolean, Array],
      required: false,
      default: null,
    },
    definition: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    fieldLabel: {
      type: String,
      required: true,
    },
    removeLabel: {
      type: String,
      required: true,
    },
    valueDataTestid: {
      type: String,
      required: true,
    },
    removeDataTestid: {
      type: String,
      required: true,
    },
  },
  emits: ['update'],
  data() {
    return {
      labelId: uniqueId('advanced-configuration-value-label-'),
      toggleId: uniqueId('advanced-configuration-value-toggle-'),
      inputId: uniqueId('advanced-configuration-value-input-'),
    };
  },
  computed: {
    isBoolean() {
      return this.definition.valueType === VALUE_TYPE_BOOLEAN;
    },
    isEnum() {
      return this.definition.valueType === VALUE_TYPE_ENUM;
    },
    isMultiSelect() {
      return this.definition.valueType === VALUE_TYPE_MULTI_SELECT;
    },
    isNumber() {
      return this.definition.valueType === VALUE_TYPE_NUMBER;
    },
    isStringList() {
      return this.definition.valueType === VALUE_TYPE_STRING_LIST;
    },
    options() {
      return this.definition.options ?? [];
    },
    // Native <select> visually falls back to its first option when :value doesn't match any of
    // them (e.g. imageSuffix's placeholder null for a trigger with nothing configured yet), which
    // would misleadingly look like that option is selected. A genuinely blank one fixes that.
    selectOptions() {
      if (this.value === null || this.value === undefined) {
        return [{ value: null, text: '' }, ...this.options];
      }
      return this.options;
    },
    selectedOptions() {
      return this.value ?? [];
    },
    toggleText() {
      return multiSelectToggleText(this.definition, this.value);
    },
    numberState() {
      return isValidConfigurationValue(this.definition, this.value) ? null : false;
    },
    invalidFeedback() {
      return this.isNumber ? numberInvalidFeedback(this.definition.label, this.definition) : '';
    },
  },
  methods: {
    textInputValue(value) {
      return value === null || value === undefined ? '' : String(value);
    },
  },
  booleanOptions: BOOLEAN_OPTIONS,
};
</script>

<template>
  <gl-form-group
    class="gl-mb-0"
    :label-for="inputId"
    :state="numberState"
    :invalid-feedback="invalidFeedback"
  >
    <div class="gl-flex gl-items-center gl-justify-between gl-gap-2">
      <gl-form-radio-group
        v-if="isBoolean"
        :checked="value"
        :options="$options.booleanOptions"
        :aria-label="fieldLabel"
        :data-testid="valueDataTestid"
        @input="$emit('update', $event)"
      />
      <gl-form-select
        v-else-if="isEnum"
        :value="value"
        :options="selectOptions"
        :aria-label="fieldLabel"
        :data-testid="valueDataTestid"
        @input="$emit('update', $event)"
      />
      <div v-else-if="isMultiSelect">
        <span :id="labelId" class="gl-sr-only">{{ fieldLabel }}</span>
        <gl-collapsible-listbox
          multiple
          :items="options"
          :selected="selectedOptions"
          :toggle-id="toggleId"
          :toggle-text="toggleText"
          :toggle-aria-labelled-by="`${labelId} ${toggleId}`"
          :data-testid="valueDataTestid"
          @select="$emit('update', $event)"
        />
      </div>
      <gl-form-input
        v-else-if="isNumber"
        :id="inputId"
        type="number"
        :value="value"
        :min="definition.min"
        :max="definition.max"
        :state="numberState"
        :aria-label="fieldLabel"
        :data-testid="valueDataTestid"
        @change="$emit('update', $event)"
      />
      <string-list-token-selector
        v-else-if="isStringList"
        :value="value"
        :aria-label="fieldLabel"
        :text-input-attrs="{ 'data-testid': valueDataTestid }"
        @input="$emit('update', $event)"
      />
      <gl-form-input
        v-else
        :value="textInputValue(value)"
        :aria-label="fieldLabel"
        :data-testid="valueDataTestid"
        @change="$emit('update', $event)"
      />
      <gl-button
        category="tertiary"
        icon="remove"
        size="small"
        :aria-label="removeLabel"
        :data-testid="removeDataTestid"
        @click="$emit('update', null)"
      />
    </div>
  </gl-form-group>
</template>
