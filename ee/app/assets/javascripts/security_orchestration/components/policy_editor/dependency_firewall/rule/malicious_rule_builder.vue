<script>
import { s__ } from '~/locale';
import { EXCEPT_PACKAGES_FIELD } from '../constants';
import { EXCEPTION_KEY_PURL, exceptionsToLines, ruleWithExceptionsForKey } from '../utils';
import FieldRow from '../components/field_row.vue';
import NameListTextarea from './name_list_textarea.vue';

export default {
  name: 'MaliciousRuleBuilder',
  EXCEPT_PACKAGES_FIELD,
  components: { FieldRow, NameListTextarea },
  i18n: {
    blurb: s__('SecurityOrchestration|Deny packages flagged as malicious by GitLab.'),
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
  },
  emits: ['changed'],
  computed: {
    exceptionLines() {
      return exceptionsToLines(this.initRule.exceptions || []);
    },
  },
  methods: {
    handleExceptionsChange(lines) {
      this.$emit('changed', ruleWithExceptionsForKey(this.initRule, lines, EXCEPTION_KEY_PURL));
    },
  },
};
</script>

<template>
  <div class="gl-w-full">
    <p class="gl-mb-5 gl-text-subtle" data-testid="malicious-blurb">
      {{ $options.i18n.blurb }}
    </p>

    <field-row
      :label="$options.EXCEPT_PACKAGES_FIELD.label"
      :hint="$options.EXCEPT_PACKAGES_FIELD.hint"
      label-for="malicious-package-exceptions"
      last
    >
      <name-list-textarea
        id="malicious-package-exceptions"
        single-line
        :items="exceptionLines"
        :placeholder="$options.EXCEPT_PACKAGES_FIELD.placeholder"
        data-testid="package-exceptions"
        @input="handleExceptionsChange"
      />
    </field-row>
  </div>
</template>
