<script>
import { GlFormGroup, GlFormInput } from '@gitlab/ui';
import { __ } from '~/locale';
import SafeHtml from '~/vue_shared/directives/safe_html';
import { FIELD_NAME_PREFIXES } from '~/groups_projects/constants';

export default {
  name: 'RepositorySizeLimitField',
  components: {
    GlFormGroup,
    GlFormInput,
  },
  directives: {
    SafeHtml,
  },
  i18n: {
    repositorySizeLimit: __('Repository size limit (MiB)'),
  },
  props: {
    // Rails param namespace of the surrounding form, e.g. `project` or `group`.
    fieldNamePrefix: {
      type: String,
      required: true,
      validator: (value) => FIELD_NAME_PREFIXES.includes(value),
    },
    value: {
      type: [Number, String],
      required: false,
      default: null,
    },
    helpText: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
  computed: {
    inputId() {
      return `${this.fieldNamePrefix}_repository_size_limit`;
    },
    inputName() {
      return `${this.fieldNamePrefix}[repository_size_limit]`;
    },
  },
};
</script>

<template>
  <gl-form-group
    :label="$options.i18n.repositorySizeLimit"
    :label-for="inputId"
    class="gl-col-md-9"
  >
    <gl-form-input
      :id="inputId"
      :value="value"
      type="number"
      :name="inputName"
      :min="0"
      data-testid="repository-size-limit-field"
      @input="$emit('input', $event)"
    />
    <template v-if="helpText" #description>
      <span v-safe-html="helpText"></span>
    </template>
  </gl-form-group>
</template>
