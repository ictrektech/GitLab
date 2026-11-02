<script>
import { GlButton, GlTableLite } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { SCAN_TRIGGER_DEFINITIONS } from '~/security_configuration/constants';
import AdvancedConfigurationValueField from './advanced_configuration_value_field.vue';
import { displayConfigurationValue, isValidConfigurationValue } from './utils';

export default {
  name: 'AdvancedConfigurationTable',
  components: {
    GlButton,
    GlTableLite,
    AdvancedConfigurationValueField,
  },
  props: {
    caption: {
      type: String,
      required: true,
    },
    rows: {
      type: Array,
      required: false,
      default: () => [],
    },
    editable: {
      type: Boolean,
      required: false,
      default: false,
    },
    variableDefinitions: {
      type: Object,
      required: true,
    },
  },
  emits: ['update-value'],
  data() {
    return {
      expandedVariables: [],
    };
  },
  computed: {
    items() {
      return this.rows.map((row) => ({
        ...row,
        _showDetails: this.isExpanded(row.setting) || this.hasInvalidValue(row),
      }));
    },
  },
  methods: {
    isExpanded(setting) {
      return this.expandedVariables.includes(setting);
    },
    hasInvalidValue({ setting, triggerValues }) {
      return (
        this.editable &&
        triggerValues.some(
          ({ value }) => !isValidConfigurationValue(this.definitionFor(setting), value),
        )
      );
    },
    toggleVariable(setting) {
      this.expandedVariables = this.isExpanded(setting)
        ? this.expandedVariables.filter((expanded) => expanded !== setting)
        : [...this.expandedVariables, setting];
    },
    triggerTitle(triggerType) {
      return SCAN_TRIGGER_DEFINITIONS[triggerType]?.title ?? triggerType;
    },
    toggleLabel(setting) {
      return sprintf(s__('ScanProfiles|Show %{variable} for each trigger'), {
        variable: this.definitionFor(setting).label ?? setting,
      });
    },
    removeLabel(setting, triggerType) {
      return sprintf(s__('ScanProfiles|Remove %{variable} from %{trigger}'), {
        variable: this.definitionFor(setting).label ?? setting,
        trigger: this.triggerTitle(triggerType),
      });
    },
    fieldLabel(setting, triggerType) {
      return sprintf(s__('ScanProfiles|%{variable} for %{trigger}'), {
        variable: this.definitionFor(setting).label ?? setting,
        trigger: this.triggerTitle(triggerType),
      });
    },
    definitionFor(setting) {
      return this.variableDefinitions[setting] ?? {};
    },
    displayValue(setting, value) {
      return displayConfigurationValue(this.definitionFor(setting), value);
    },
    updateTriggerValue(setting, triggerType, value) {
      if (!this.isExpanded(setting)) {
        this.expandedVariables = [...this.expandedVariables, setting];
      }
      this.$emit('update-value', { setting, triggerType, value });
    },
  },
  fields: [
    { key: 'toggle', label: '', thClass: 'gl-w-8', tdClass: '!gl-pt-4' },
    { key: 'variable', label: s__('ScanProfiles|Variable'), thClass: 'gl-w-8/20' },
    { key: 'value', label: s__('ScanProfiles|Value') },
  ],
};
</script>
<template>
  <gl-table-lite
    v-if="rows.length"
    :items="items"
    :fields="$options.fields"
    fixed
    stacked="sm"
    table-class="gl-mb-0"
    details-td-class="!gl-p-0"
    :aria-label="caption"
    data-testid="advanced-configuration-table"
  >
    <template #cell(toggle)="{ item }">
      <gl-button
        category="tertiary"
        size="small"
        :icon="item._showDetails ? 'chevron-down' : 'chevron-right'"
        :aria-expanded="item._showDetails.toString()"
        :aria-label="toggleLabel(item.setting)"
        :disabled="hasInvalidValue(item)"
        @click="toggleVariable(item.setting)"
      />
    </template>
    <template #cell(variable)="{ item }">
      <code>{{ item.setting }}</code>
    </template>
    <template #cell(value)="{ item }">
      <gl-button
        v-if="item.varies"
        variant="link"
        :disabled="hasInvalidValue(item)"
        @click="toggleVariable(item.setting)"
      >
        {{ s__('ScanProfiles|Differs by trigger') }}
      </gl-button>
      <span v-else class="gl-break-anywhere">{{ displayValue(item.setting, item.value) }}</span>
    </template>
    <template #row-details="{ item }">
      <div class="gl-py-3" data-testid="trigger-values">
        <div
          v-for="triggerValue in item.triggerValues"
          :key="triggerValue.triggerType"
          class="gl-flex gl-items-center"
        >
          <span class="gl-ml-8 gl-w-8/20 gl-p-4 gl-text-subtle">{{
            triggerTitle(triggerValue.triggerType)
          }}</span>
          <advanced-configuration-value-field
            v-if="editable"
            class="gl-flex-1 gl-p-4"
            :value="triggerValue.value"
            :definition="definitionFor(item.setting)"
            :field-label="fieldLabel(item.setting, triggerValue.triggerType)"
            :remove-label="removeLabel(item.setting, triggerValue.triggerType)"
            :value-data-testid="`advanced-configuration-value-input-${item.setting}-${triggerValue.triggerType}`"
            :remove-data-testid="`advanced-configuration-remove-button-${item.setting}-${triggerValue.triggerType}`"
            @update="updateTriggerValue(item.setting, triggerValue.triggerType, $event)"
          />
          <span v-else class="gl-flex-1 gl-p-4 gl-break-anywhere">{{
            displayValue(item.setting, triggerValue.value)
          }}</span>
        </div>
      </div>
    </template>
  </gl-table-lite>
</template>
