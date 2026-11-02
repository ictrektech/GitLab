<script>
import { GlFormCheckbox, GlFormGroup } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { fieldProps } from './field_props';

export default {
  name: 'CheckboxField',
  components: { GlFormCheckbox, GlFormGroup },
  props: {
    ...fieldProps,
    // `null` means "never touched" so `isChecked` can fall back to the catalog
    // default. Vue skips type validation for nullish values on non-required
    // props, so the Boolean constraint never fires on the null default.
    value: {
      type: Boolean,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  data() {
    return {
      feedbackId: uniqueId('policy-store-field-error-'),
    };
  },
  computed: {
    // GlFormCheckbox carries its own label, so this control does not use FieldWrapper. It
    // still needs the group, which is what renders the message `error` carries.
    isChecked() {
      return this.value ?? this.field.default ?? false;
    },
    // `null`, not `true`: a checkbox with nothing to report stays neutral rather than
    // drawing itself as validated. Same rule as FieldWrapper's.
    state() {
      return this.error ? false : null;
    },
    describedBy() {
      return this.error ? this.feedbackId : null;
    },
  },
};
</script>

<template>
  <gl-form-group :state="state" class="gl-mb-0">
    <gl-form-checkbox
      :checked="isChecked"
      :state="state"
      :aria-describedby="describedBy"
      @change="$emit('input', $event)"
    >
      {{ field.label }}
    </gl-form-checkbox>
    <!-- Rendered here rather than through `invalid-feedback` so the id is ours and the
         checkbox can point `aria-describedby` at it, matching what FieldWrapper does. -->
    <span
      v-if="error"
      :id="feedbackId"
      class="invalid-feedback !gl-block"
      aria-live="assertive"
      aria-atomic="true"
      >{{ error }}</span
    >
  </gl-form-group>
</template>
