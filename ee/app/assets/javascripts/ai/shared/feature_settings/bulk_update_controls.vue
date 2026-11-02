<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { s__ } from '~/locale';
import ModelSelectDropdown from './model_select_dropdown.vue';

export default {
  name: 'BulkUpdateControls',
  components: {
    GlButton,
    ModelSelectDropdown,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    items: {
      type: Array,
      required: true,
    },
    canReset: {
      type: Boolean,
      required: true,
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
    headerText: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['select', 'reset'],
  computed: {
    hasModels() {
      return this.items.length > 0;
    },
    tooltip() {
      return this.hasModels ? '' : s__('ModelSelection|No models are available for this section');
    },
  },
};
</script>
<template>
  <div class="gl-flex gl-items-center gl-gap-3">
    <slot></slot>
    <gl-button
      v-if="canReset"
      data-testid="reset-to-default-button"
      category="tertiary"
      :disabled="isSaving"
      @click="$emit('reset')"
    >
      {{ s__('ModelSelection|Reset to default') }}
    </gl-button>
    <span v-gl-tooltip="tooltip" class="gl-inline-block" data-testid="bulk-update-tooltip">
      <model-select-dropdown
        :block="false"
        :header-text="headerText"
        :selected-option="null"
        :items="items"
        :placeholder-dropdown-text="s__('ModelSelection|Bulk update')"
        :disabled="!hasModels || isSaving"
        :is-loading="isSaving"
        @select="$emit('select', $event)"
      />
    </span>
  </div>
</template>
