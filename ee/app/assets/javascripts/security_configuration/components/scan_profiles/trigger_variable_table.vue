<script>
import { GlTableLite } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { displayConfigurationValue } from './utils';

export default {
  name: 'TriggerVariableTable',
  components: {
    GlTableLite,
  },
  props: {
    triggerTitle: {
      type: String,
      required: true,
    },
    rows: {
      type: Array,
      required: false,
      default: () => [],
    },
    variableDefinitions: {
      type: Object,
      required: true,
    },
  },
  computed: {
    ariaLabel() {
      return sprintf(s__('ScanProfiles|Analyzer settings for %{trigger}'), {
        trigger: this.triggerTitle,
      });
    },
  },
  methods: {
    displayValue(item) {
      return displayConfigurationValue(this.variableDefinitions[item.setting] ?? {}, item.value);
    },
  },
  fields: [
    { key: 'setting', label: s__('ScanProfiles|Variable') },
    { key: 'value', label: s__('ScanProfiles|Value') },
  ],
};
</script>

<template>
  <div
    v-if="rows.length"
    class="gl-border gl-mb-4 gl-overflow-hidden gl-rounded-base gl-bg-default"
  >
    <gl-table-lite
      :items="rows"
      :fields="$options.fields"
      stacked="sm"
      table-class="!gl-mb-0"
      :aria-label="ariaLabel"
      data-testid="trigger-variables-table"
    >
      <template #cell(setting)="{ item }">
        <code>{{ item.setting }}</code>
      </template>
      <template #cell(value)="{ item }">
        <span class="gl-break-anywhere">{{ displayValue(item) }}</span>
      </template>
    </gl-table-lite>
  </div>
</template>
