<script>
import { uniqBy } from 'lodash-es';
import { GlButton, GlCollapsibleListbox, GlFormInput, GlSprintf } from '@gitlab/ui';
import { s__, __ } from '~/locale';
import {
  RISK_SEVERITY_LISTBOX_ITEMS,
  DEFAULT_RISK_SEVERITY_THRESHOLD,
  EXCEPT_PACKAGES_FIELD,
  EXCEPT_VULNERABILITIES_FIELD,
} from '../constants';
import { enforceIntValue } from '../../utils';
import {
  EXCEPTION_KEY_ID,
  EXCEPTION_KEY_PURL,
  exceptionsToLines,
  linesToExceptions,
  ruleWithExceptions,
} from '../utils';
import FieldRow from '../components/field_row.vue';
import NameListTextarea from './name_list_textarea.vue';

const stripAllowed = (rule) => {
  const { allowed, ...rest } = rule;
  return rest;
};

export default {
  name: 'RiskSeverityRuleBuilder',
  EXCEPT_PACKAGES_FIELD,
  EXCEPT_VULNERABILITIES_FIELD,
  components: {
    GlButton,
    GlCollapsibleListbox,
    GlFormInput,
    GlSprintf,
    FieldRow,
    NameListTextarea,
  },
  i18n: {
    blurb: s__(
      'SecurityOrchestration|Deny packages that exceed a specified number of vulnerabilities.',
    ),
    blockPrefix: s__('SecurityOrchestration|Block packages that have'),
    // One sentence, not separate "more than" / "vulnerabilities" translation calls, so
    // translators can reorder the count/severity fragments to match their language's
    // grammar (the leading "Block packages that have" is the field-row label, to its left).
    // The remove button is glued to the %{suffix} text so it never wraps onto a line alone.
    rowSentence: s__(
      'SecurityOrchestration|more than %{thresholdStart}%{thresholdEnd} %{severityStart}%{severityEnd} %{suffixStart}vulnerabilities%{suffixEnd}',
    ),
    thresholdAriaLabel: s__('SecurityOrchestration|Vulnerability count threshold'),
    severityAriaLabel: s__('SecurityOrchestration|Severity'),
    addSeverityText: s__('SecurityOrchestration|Add severity'),
    severityPlaceholder: s__('SecurityOrchestration|Select'),
    missingSeverity: s__('SecurityOrchestration|Select a severity to finish this rule.'),
    removeLabel: __('Remove'),
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
    // True once the card's checkbox is on, at which point an unfinished row is a real
    // problem rather than just an untouched default.
    isActive: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['changed'],
  computed: {
    deniedList() {
      return uniqBy(this.initRule.denied || [], 'severity');
    },
    usedSeverities() {
      return this.deniedList.map(({ severity }) => severity).filter(Boolean);
    },
    hasUnselectedRow() {
      return this.deniedList.some(({ severity }) => !severity);
    },
    // Only one placeholder row at a time: a second would collapse into the first, since
    // rows are de-duplicated by severity.
    canAddRow() {
      return (
        this.usedSeverities.length < RISK_SEVERITY_LISTBOX_ITEMS.length && !this.hasUnselectedRow
      );
    },
    // A ticked card needs at least one complete row - an unselected severity, or no rows
    // at all, are both shapes the schema rejects.
    showMissingSeverity() {
      return this.isActive && (this.hasUnselectedRow || this.deniedList.length === 0);
    },
    // The design splits the single `exceptions:` array across two fields, keyed on which
    // shape each entry has: `{ id }` for advisory identifiers, `{ purl }` for packages.
    vulnerabilityExceptionLines() {
      return exceptionsToLines((this.initRule.exceptions || []).filter(({ purl }) => !purl));
    },
    packageExceptionLines() {
      return exceptionsToLines((this.initRule.exceptions || []).filter(({ purl }) => purl));
    },
  },
  methods: {
    severityLabel(value) {
      if (!value) {
        return this.$options.i18n.severityPlaceholder;
      }

      return RISK_SEVERITY_LISTBOX_ITEMS.find((item) => item.value === value)?.text ?? value;
    },
    // Excludes severities used by other rows, but keeps this row's own current severity so
    // its listbox still shows a selection.
    availableSeveritiesFor(index) {
      const usedByOtherRows = this.deniedList
        .filter((_, i) => i !== index)
        .map(({ severity }) => severity)
        .filter(Boolean);
      return RISK_SEVERITY_LISTBOX_ITEMS.filter(({ value }) => !usedByOtherRows.includes(value));
    },
    emitDenied(denied) {
      this.$emit('changed', { ...stripAllowed(this.initRule), denied });
    },
    addRow() {
      if (!this.canAddRow) {
        return;
      }

      this.emitDenied([...this.deniedList, { threshold: DEFAULT_RISK_SEVERITY_THRESHOLD }]);
    },
    updateSeverity(index, severity) {
      const updated = this.deniedList.map((entry, i) =>
        i === index ? { ...entry, severity } : entry,
      );
      this.emitDenied(updated);
    },
    normalizeThreshold(value) {
      const parsed = enforceIntValue(value);
      return Number.isNaN(parsed) ? DEFAULT_RISK_SEVERITY_THRESHOLD : Math.max(0, parsed);
    },
    formatThreshold(value) {
      return String(this.normalizeThreshold(value));
    },
    updateThreshold(index, value) {
      const threshold = this.normalizeThreshold(value);
      const updated = this.deniedList.map((entry, i) =>
        i === index ? { ...entry, threshold } : entry,
      );
      this.emitDenied(updated);
    },
    removeAriaLabel(entry) {
      return entry.severity
        ? `${this.$options.i18n.removeLabel} ${this.severityLabel(entry.severity)}`
        : this.$options.i18n.removeLabel;
    },
    thresholdAriaLabel(entry) {
      return `${this.$options.i18n.thresholdAriaLabel} (${this.severityLabel(entry.severity)})`;
    },
    isRowInvalid(entry) {
      return this.isActive && !entry.severity;
    },
    removeSeverity(index) {
      this.emitDenied(this.deniedList.filter((_, i) => i !== index));
    },
    handleVulnerabilityExceptionsChange(lines) {
      this.emitExceptions(lines, this.packageExceptionLines);
    },
    handlePackageExceptionsChange(lines) {
      this.emitExceptions(this.vulnerabilityExceptionLines, lines);
    },
    emitExceptions(idLines, purlLines) {
      this.$emit(
        'changed',
        ruleWithExceptions(stripAllowed(this.initRule), [
          ...linesToExceptions(idLines, EXCEPTION_KEY_ID),
          ...linesToExceptions(purlLines, EXCEPTION_KEY_PURL),
        ]),
      );
    },
  },
};
</script>

<template>
  <div class="gl-w-full">
    <p class="gl-mb-5 gl-text-subtle" data-testid="risk-severity-blurb">
      {{ $options.i18n.blurb }}
    </p>

    <field-row
      :label="$options.i18n.blockPrefix"
      label-id="risk-severity-threshold-label"
      data-testid="threshold-field"
    >
      <div
        class="gl-flex gl-flex-col gl-gap-3"
        role="group"
        aria-labelledby="risk-severity-threshold-label"
      >
        <div v-for="(entry, index) in deniedList" :key="index">
          <span :id="`risk-severity-select-label-${index}`" class="gl-sr-only">{{
            $options.i18n.severityAriaLabel
          }}</span>
          <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-4">
            <gl-sprintf :message="$options.i18n.rowSentence">
              <template #threshold>
                <gl-form-input
                  type="number"
                  min="0"
                  :value="entry.threshold"
                  :formatter="formatThreshold"
                  lazy-formatter
                  :aria-label="thresholdAriaLabel(entry)"
                  class="df-thr-count !gl-shrink-0 !gl-text-center"
                  :data-testid="`risk-severity-threshold-${index}`"
                  @input="updateThreshold(index, $event)"
                />
              </template>
              <template #severity>
                <gl-collapsible-listbox
                  :items="availableSeveritiesFor(index)"
                  :selected="entry.severity"
                  :toggle-text="severityLabel(entry.severity)"
                  :toggle-aria-labelled-by="`risk-severity-select-label-${index}`"
                  :aria-invalid="isRowInvalid(entry) ? 'true' : null"
                  :aria-describedby="isRowInvalid(entry) ? 'risk-severity-missing' : null"
                  block
                  class="df-thr-sev gl-shrink-0"
                  :data-testid="`risk-severity-select-${index}`"
                  @select="updateSeverity(index, $event)"
                />
              </template>
              <template #suffix="{ content }">
                <span class="gl-inline-flex gl-items-center gl-gap-4 gl-whitespace-nowrap">
                  {{ content }}
                  <gl-button
                    icon="close"
                    category="tertiary"
                    :aria-label="removeAriaLabel(entry)"
                    data-testid="remove-severity-row"
                    @click="removeSeverity(index)"
                  />
                </span>
              </template>
            </gl-sprintf>
          </div>
        </div>

        <gl-button
          v-if="canAddRow"
          icon="plus"
          category="tertiary"
          data-testid="add-severity-row"
          @click="addRow"
        >
          {{ $options.i18n.addSeverityText }}
        </gl-button>

        <p
          v-if="showMissingSeverity"
          id="risk-severity-missing"
          role="alert"
          class="gl-mb-0 gl-text-danger"
          data-testid="missing-severity"
        >
          {{ $options.i18n.missingSeverity }}
        </p>
      </div>
    </field-row>

    <field-row
      :label="$options.EXCEPT_VULNERABILITIES_FIELD.label"
      :hint="$options.EXCEPT_VULNERABILITIES_FIELD.hint"
      label-for="risk-severity-vulnerability-exceptions"
    >
      <name-list-textarea
        id="risk-severity-vulnerability-exceptions"
        single-line
        :items="vulnerabilityExceptionLines"
        :placeholder="$options.EXCEPT_VULNERABILITIES_FIELD.placeholder"
        data-testid="vulnerability-exceptions"
        @input="handleVulnerabilityExceptionsChange"
      />
    </field-row>

    <field-row
      :label="$options.EXCEPT_PACKAGES_FIELD.label"
      :hint="$options.EXCEPT_PACKAGES_FIELD.hint"
      label-for="risk-severity-package-exceptions"
      last
    >
      <name-list-textarea
        id="risk-severity-package-exceptions"
        single-line
        :items="packageExceptionLines"
        :placeholder="$options.EXCEPT_PACKAGES_FIELD.placeholder"
        data-testid="package-exceptions"
        @input="handlePackageExceptionsChange"
      />
    </field-row>
  </div>
</template>

<style scoped>
/* Fixed widths come from the design; no spacing-scale utility matches them. */
.df-thr-count {
  width: 67px !important;
}

.df-thr-sev {
  width: 140px;
}
</style>
