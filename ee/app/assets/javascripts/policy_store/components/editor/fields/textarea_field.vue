<script>
import { GlFormTextarea } from '@gitlab/ui';
import { fieldProps } from './field_props';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'TextareaField',
  components: { FieldWrapper, GlFormTextarea },
  props: {
    ...fieldProps,
    value: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
};
</script>

<template>
  <field-wrapper :field="field" :invalid-feedback="error">
    <template #default="{ inputId, state, describedBy }">
      <gl-form-textarea
        :id="inputId"
        :state="state"
        :aria-describedby="describedBy"
        :value="value"
        :placeholder="field.placeholder"
        @input="$emit('input', $event)"
      />
    </template>
  </field-wrapper>
</template>
