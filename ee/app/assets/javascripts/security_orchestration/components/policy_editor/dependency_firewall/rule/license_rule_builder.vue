<script>
import { GlAlert } from '@gitlab/ui';
import { s__ } from '~/locale';
import { EXCEPT_PACKAGES_FIELD } from '../constants';
import {
  EXCEPTION_KEY_PURL,
  getRuleListKey,
  getRuleList,
  namesToItems,
  itemsToNames,
  exceptionsToLines,
  ruleWithExceptionsForKey,
} from '../utils';
import RuleMultiSelect from '../../rule_multi_select.vue';
import FieldRow from '../components/field_row.vue';
import NameListTextarea from './name_list_textarea.vue';

export default {
  name: 'LicenseRuleBuilder',
  EXCEPT_PACKAGES_FIELD,
  components: { GlAlert, RuleMultiSelect, FieldRow, NameListTextarea },
  inject: ['parsedSoftwareLicenses'],
  i18n: {
    denyBlurb: s__('SecurityOrchestration|Deny packages based on the selected software license.'),
    allowBlurb: s__('SecurityOrchestration|Allow packages based on the selected software license.'),
    licensesLabel: s__('SecurityOrchestration|Block packages declaring'),
    licensesItemTypeName: s__('SecurityOrchestration|Licenses'),
    allowListExplanation: s__(
      'SecurityOrchestration|This rule is an allow list. New license rules can only deny; to change this rule back to a deny list, edit the policy YAML directly.',
    ),
    missingLicenses: s__('SecurityOrchestration|Select at least one license to finish this rule.'),
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
    // True once the card's checkbox is on, at which point an empty license list is a real
    // problem rather than just an untouched default.
    isActive: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['changed'],
  computed: {
    listKey() {
      return getRuleListKey(this.initRule);
    },
    isAllowList() {
      return this.listKey === 'allowed';
    },
    blurb() {
      return this.isAllowList ? this.$options.i18n.allowBlurb : this.$options.i18n.denyBlurb;
    },
    names() {
      return itemsToNames(getRuleList(this.initRule));
    },
    showMissingLicenses() {
      return this.isActive && this.names.length === 0;
    },
    licenseItems() {
      return Object.fromEntries(
        this.parsedSoftwareLicenses.map(({ value, text }) => [value, text]),
      );
    },
    exceptionLines() {
      return exceptionsToLines(this.initRule.exceptions || []);
    },
  },
  methods: {
    handleNamesChange(names) {
      this.$emit('changed', { ...this.initRule, [this.listKey]: namesToItems(names) });
    },
    handleExceptionsChange(lines) {
      this.$emit('changed', ruleWithExceptionsForKey(this.initRule, lines, EXCEPTION_KEY_PURL));
    },
  },
};
</script>

<template>
  <div class="gl-w-full">
    <p class="gl-mb-5 gl-text-subtle" data-testid="license-blurb">{{ blurb }}</p>

    <gl-alert v-if="isAllowList" :dismissible="false" variant="info" class="gl-mb-5">
      {{ $options.i18n.allowListExplanation }}
    </gl-alert>

    <field-row :label="$options.i18n.licensesLabel" label-id="license-names-label">
      <!-- Not a declared RuleMultiSelect prop: falls through onto its root
           gl-collapsible-listbox, which does declare it, and labels the toggle button
           itself rather than the wrapper (aria-labelledby would land on the wrapper). -->
      <rule-multi-select
        :item-type-name="$options.i18n.licensesItemTypeName"
        :items="licenseItems"
        :value="names"
        fluid-width
        searchable
        toggle-aria-labelled-by="license-names-label"
        @input="handleNamesChange"
      />
      <p
        v-if="showMissingLicenses"
        id="license-names-missing"
        role="alert"
        class="gl-mb-0 gl-mt-2 gl-text-danger"
        data-testid="missing-licenses"
      >
        {{ $options.i18n.missingLicenses }}
      </p>
    </field-row>

    <field-row
      :label="$options.EXCEPT_PACKAGES_FIELD.label"
      :hint="$options.EXCEPT_PACKAGES_FIELD.hint"
      label-for="license-package-exceptions"
      last
    >
      <name-list-textarea
        id="license-package-exceptions"
        single-line
        :items="exceptionLines"
        :placeholder="$options.EXCEPT_PACKAGES_FIELD.placeholder"
        data-testid="package-exceptions"
        @input="handleExceptionsChange"
      />
    </field-row>
  </div>
</template>
