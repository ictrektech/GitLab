<script>
import { GlButton, GlFormTextarea } from '@gitlab/ui';
import RegoTemplatesModal from '../rego_templates_modal.vue';
import { fieldProps } from './field_props';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'CodeField',
  components: { FieldWrapper, GlButton, GlFormTextarea, RegoTemplatesModal },
  props: {
    ...fieldProps,
    value: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
  data() {
    return { templatesVisible: false };
  },
};
</script>

<template>
  <field-wrapper :field="field" :invalid-feedback="error">
    <template #label-actions>
      <gl-button
        category="secondary"
        variant="default"
        size="small"
        icon="documents"
        @click="templatesVisible = true"
      >
        {{ s__('PolicyStore|Browse templates') }}
      </gl-button>
    </template>
    <template #default="{ inputId, labelTextId, state, describedBy }">
      <gl-form-textarea
        :id="inputId"
        :aria-labelledby="labelTextId"
        :aria-describedby="describedBy"
        :state="state"
        :value="value"
        :placeholder="field.placeholder"
        :rows="10"
        :maxlength="field.maxLength"
        class="gl-border gl-rounded-lg gl-border-subtle gl-bg-subtle gl-font-monospace gl-text-sm"
        spellcheck="false"
        @input="$emit('input', $event)"
      />
      <rego-templates-modal
        :visible="templatesVisible"
        @select="$emit('input', $event)"
        @hide="templatesVisible = false"
      />
    </template>
  </field-wrapper>
</template>
