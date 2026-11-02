<script>
import { GlFormSelect } from '@gitlab/ui';
import { s__ } from '~/locale';
import { fieldProps } from './field_props';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'SelectField',
  components: { FieldWrapper, GlFormSelect },
  props: {
    ...fieldProps,
    value: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
  computed: {
    placeholder() {
      return this.field.placeholder || s__('PolicyStore|Select...');
    },
  },
};
</script>

<template>
  <field-wrapper :field="field" :invalid-feedback="error">
    <template #default="{ inputId, state, describedBy }">
      <gl-form-select
        :id="inputId"
        :state="state"
        :aria-describedby="describedBy"
        :value="value"
        @change="$emit('input', $event)"
      >
        <option value="">{{ placeholder }}</option>
        <option v-for="option in field.options" :key="option.id" :value="option.id">
          {{ option.label }}
        </option>
      </gl-form-select>
    </template>
  </field-wrapper>
</template>
