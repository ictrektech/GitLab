<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import AddScanProfileVariableModal from './add_scan_profile_variable_modal.vue';
import AdvancedConfigurationTable from './advanced_configuration_table.vue';
import { scanTypeSentenceCase } from './utils';
import { variableDefinitionsFor } from './variable_definitions';

const i18n = {
  heading: s__('ScanProfiles|Advanced configuration'),
  subheading: s__(
    'ScanProfiles|Variables passed to the analyzer that override its default behavior.',
  ),
  addVariable: s__('ScanProfiles|Add variable'),
  addVariableModalTitle: s__('ScanProfiles|Add %{scanner} variable'),
  addVariableDisabledTooltip: s__(
    'ScanProfiles|Enable a trigger that supports configuration to add a variable.',
  ),
};

export default {
  name: 'AdvancedConfigurationEditor',
  components: {
    GlButton,
    AddScanProfileVariableModal,
    AdvancedConfigurationTable,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    scanType: {
      type: String,
      required: true,
    },
    rows: {
      type: Array,
      required: false,
      default: () => [],
    },
    hasConfigurableTriggers: {
      type: Boolean,
      required: true,
    },
    configurableTriggers: {
      type: Array,
      required: true,
    },
  },
  emits: ['set-value'],
  data() {
    return {
      isModalVisible: false,
    };
  },
  computed: {
    variableDefinitions() {
      return variableDefinitionsFor(this.scanType);
    },
    addVariableModalTitle() {
      return sprintf(i18n.addVariableModalTitle, { scanner: scanTypeSentenceCase(this.scanType) });
    },
    configurableTriggerItems() {
      return this.configurableTriggers.map((triggerType) => ({
        value: triggerType,
      }));
    },
    existingSettings() {
      return this.rows.map((row) => row.setting);
    },
    addVariableTooltip() {
      return this.hasConfigurableTriggers ? '' : i18n.addVariableDisabledTooltip;
    },
  },
  methods: {
    openAddModal() {
      this.isModalVisible = true;
    },
    handleAdd({ setting, values }) {
      this.isModalVisible = false;
      Object.entries(values).forEach(([triggerType, value]) => {
        this.$emit('set-value', { setting, triggerType, value });
      });
    },
    handleCancelAdd() {
      this.isModalVisible = false;
    },
  },
  i18n,
};
</script>

<template>
  <div data-testid="advanced-configuration-editor">
    <div class="gl-mb-4 gl-flex gl-items-center gl-justify-between gl-gap-3">
      <div>
        <h4 class="gl-heading-4 gl-mb-1">{{ $options.i18n.heading }}</h4>
        <p class="gl-mb-3 gl-text-subtle">{{ $options.i18n.subheading }}</p>
      </div>
      <div
        v-gl-tooltip
        :title="addVariableTooltip"
        class="gl-shrink-0"
        data-testid="scan-profile-add-variable-wrapper"
      >
        <gl-button
          size="small"
          icon="plus"
          :disabled="!hasConfigurableTriggers"
          data-testid="scan-profile-add-variable-button"
          @click="openAddModal"
        >
          {{ $options.i18n.addVariable }}
        </gl-button>
      </div>
    </div>

    <advanced-configuration-table
      v-if="rows.length"
      editable
      :caption="$options.i18n.heading"
      :rows="rows"
      :variable-definitions="variableDefinitions"
      class="gl-mb-4"
      @update-value="$emit('set-value', $event)"
    />

    <add-scan-profile-variable-modal
      :visible="isModalVisible"
      :title="addVariableModalTitle"
      :variable-definitions="variableDefinitions"
      :existing-settings="existingSettings"
      :configurable-triggers="configurableTriggerItems"
      @add="handleAdd"
      @cancel="handleCancelAdd"
    />
  </div>
</template>
