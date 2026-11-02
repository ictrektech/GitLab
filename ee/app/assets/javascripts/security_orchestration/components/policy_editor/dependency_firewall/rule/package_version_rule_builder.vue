<script>
import { GlButton, GlFormCharacterCount, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { s__, __, n__, sprintf } from '~/locale';
import FieldRow from '../components/field_row.vue';
import { isValidReferenceLink } from '../utils';
import { PACKAGE_VERSION_REASON_MAX_LENGTH, PACKAGE_VERSION_LINK_MAX_LENGTH } from '../constants';

const OPTIONAL_ENTRY_KEYS = ['reason', 'reference_link'];

export default {
  name: 'PackageVersionRuleBuilder',
  components: { GlButton, GlFormCharacterCount, GlFormGroup, GlFormInput, FieldRow },
  i18n: {
    blurb: s__('SecurityOrchestration|Deny specific package versions by exact name and version.'),
    packagesLabel: s__('SecurityOrchestration|Block these packages'),
    nameLabel: s__('SecurityOrchestration|Package name'),
    versionLabel: s__('SecurityOrchestration|Package version'),
    reasonLabel: s__('SecurityOrchestration|Reason'),
    reasonDescription: s__(
      'SecurityOrchestration|Shown to developers when this package is blocked.',
    ),
    linkLabel: s__('SecurityOrchestration|Reference link'),
    linkDescription: s__(
      'SecurityOrchestration|Stored with the rule. Must start with http:// or https://.',
    ),
    entryAriaLabel: s__('SecurityOrchestration|Package (row %{row})'),
    invalidLink: s__(
      'SecurityOrchestration|Enter a link of up to %{max} characters that starts with http:// or https://.',
    ),
    addPackageText: s__('SecurityOrchestration|Add package'),
    incompleteRow: s__('SecurityOrchestration|Enter a name and version for every package.'),
    removeLabel: __('Remove'),
    removePackageLabel: s__('SecurityOrchestration|Remove %{package}'),
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
    isActive: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['changed'],
  reasonMaxLength: PACKAGE_VERSION_REASON_MAX_LENGTH,
  linkMaxLength: PACKAGE_VERSION_LINK_MAX_LENGTH,
  computed: {
    deniedList() {
      return this.initRule.denied || [];
    },
    hasIncompleteRow() {
      return this.deniedList.some(({ name, version }) => !name || !version);
    },
    showIncompleteRow() {
      return this.isActive && (this.hasIncompleteRow || this.deniedList.length === 0);
    },
    hasInvalidLink() {
      return this.deniedList.some((entry) => this.isLinkInvalid(entry));
    },
    showInvalidLink() {
      return this.isActive && this.hasInvalidLink;
    },
    invalidLinkMessage() {
      return sprintf(this.$options.i18n.invalidLink, { max: PACKAGE_VERSION_LINK_MAX_LENGTH });
    },
  },
  methods: {
    emitDenied(denied) {
      this.$emit('changed', { ...this.initRule, denied });
    },
    updateEntry(index, key, value) {
      this.emitDenied(
        this.deniedList.map((entry, i) => {
          if (i !== index) return entry;

          const updated = { ...entry, [key]: value };
          if (OPTIONAL_ENTRY_KEYS.includes(key) && !value) delete updated[key];
          return updated;
        }),
      );
    },
    addRow() {
      this.emitDenied([...this.deniedList, { name: '', version: '' }]);
    },
    removeRow(index) {
      this.emitDenied(this.deniedList.filter((_, i) => i !== index));
    },
    isFieldInvalid(entry, key) {
      return this.isActive && !entry[key];
    },
    isReasonTooLong(entry) {
      return (entry.reason || '').length > PACKAGE_VERSION_REASON_MAX_LENGTH;
    },
    isLinkInvalid(entry) {
      return (
        Boolean(entry.reference_link) &&
        (!isValidReferenceLink(entry.reference_link) ||
          entry.reference_link.length > PACKAGE_VERSION_LINK_MAX_LENGTH)
      );
    },
    fieldId(field, index) {
      return `package-version-${field}-input-${index}`;
    },
    entryAriaLabel(index) {
      return sprintf(this.$options.i18n.entryAriaLabel, { row: index + 1 });
    },
    removeAriaLabel({ name, version }) {
      const packageLabel = [name, version].filter(Boolean).join(' ');

      return packageLabel
        ? sprintf(this.$options.i18n.removePackageLabel, { package: packageLabel }, false)
        : this.$options.i18n.removeLabel;
    },
    remainingCountText(count) {
      return n__('%d character remaining.', '%d characters remaining.', count);
    },
    overLimitText(count) {
      return n__('%d character over limit.', '%d characters over limit.', count);
    },
  },
};
</script>

<template>
  <div class="gl-w-full">
    <p class="gl-mb-5 gl-text-subtle" data-testid="package-version-blurb">
      {{ $options.i18n.blurb }}
    </p>

    <field-row
      :label="$options.i18n.packagesLabel"
      label-id="package-version-packages-label"
      last
      data-testid="packages-field"
    >
      <div
        class="gl-flex gl-flex-col gl-gap-5"
        role="group"
        aria-labelledby="package-version-packages-label"
      >
        <div class="gl-flex gl-flex-col gl-gap-5">
          <div
            v-for="(entry, index) in deniedList"
            :key="index"
            role="group"
            :aria-label="entryAriaLabel(index)"
            class="gl-border-b gl-flex gl-flex-col gl-gap-4 gl-pb-5 last:gl-border-b-0 last:gl-pb-0"
            :data-testid="`package-version-entry-${index}`"
          >
            <div class="gl-flex gl-flex-wrap gl-items-end gl-gap-3">
              <gl-form-group
                :label="$options.i18n.nameLabel"
                :label-for="fieldId('name', index)"
                class="gl-mb-0 gl-w-full @md/panel:gl-w-auto @md/panel:gl-grow"
              >
                <gl-form-input
                  :id="fieldId('name', index)"
                  :value="entry.name"
                  trim
                  :aria-invalid="isFieldInvalid(entry, 'name') ? 'true' : null"
                  :aria-describedby="
                    isFieldInvalid(entry, 'name') ? 'package-version-incomplete-row' : null
                  "
                  :data-testid="`package-version-name-${index}`"
                  @input="updateEntry(index, 'name', $event)"
                />
              </gl-form-group>
              <gl-form-group
                :label="$options.i18n.versionLabel"
                :label-for="fieldId('version', index)"
                class="gl-mb-0 gl-w-full @md/panel:gl-w-auto @md/panel:gl-grow"
              >
                <gl-form-input
                  :id="fieldId('version', index)"
                  :value="entry.version"
                  trim
                  :aria-invalid="isFieldInvalid(entry, 'version') ? 'true' : null"
                  :aria-describedby="
                    isFieldInvalid(entry, 'version') ? 'package-version-incomplete-row' : null
                  "
                  :data-testid="`package-version-version-${index}`"
                  @input="updateEntry(index, 'version', $event)"
                />
              </gl-form-group>
              <gl-button
                icon="close"
                category="tertiary"
                :aria-label="removeAriaLabel(entry)"
                data-testid="remove-package-row"
                @click="removeRow(index)"
              />
            </div>

            <div class="gl-flex gl-flex-wrap gl-gap-3">
              <gl-form-group
                optional
                :label="$options.i18n.reasonLabel"
                :label-description="$options.i18n.reasonDescription"
                :label-for="fieldId('reason', index)"
                class="gl-mb-0 gl-w-full"
              >
                <gl-form-input
                  :id="fieldId('reason', index)"
                  :value="entry.reason"
                  trim
                  :maxlength="$options.reasonMaxLength"
                  :aria-invalid="isActive && isReasonTooLong(entry) ? 'true' : null"
                  :data-testid="`package-version-reason-${index}`"
                  @input="updateEntry(index, 'reason', $event)"
                />
                <template #description>
                  <gl-form-character-count
                    :value="entry.reason || ''"
                    :limit="$options.reasonMaxLength"
                    :count-text-id="`package-version-reason-count-${index}`"
                  >
                    <template #remaining-count-text="{ count }">{{
                      remainingCountText(count)
                    }}</template>
                    <template #over-limit-text="{ count }">{{ overLimitText(count) }}</template>
                  </gl-form-character-count>
                </template>
              </gl-form-group>
              <gl-form-group
                optional
                :label="$options.i18n.linkLabel"
                :label-description="$options.i18n.linkDescription"
                :label-for="fieldId('link', index)"
                class="gl-mb-0 gl-w-full"
              >
                <gl-form-input
                  :id="fieldId('link', index)"
                  :value="entry.reference_link"
                  trim
                  :maxlength="$options.linkMaxLength"
                  :aria-invalid="isActive && isLinkInvalid(entry) ? 'true' : null"
                  :aria-describedby="
                    isActive && isLinkInvalid(entry) ? 'package-version-invalid-link' : null
                  "
                  :data-testid="`package-version-link-${index}`"
                  @input="updateEntry(index, 'reference_link', $event)"
                />
              </gl-form-group>
            </div>
          </div>
        </div>

        <gl-button
          icon="plus"
          category="tertiary"
          class="gl-self-start"
          data-testid="add-package-row"
          @click="addRow"
        >
          {{ $options.i18n.addPackageText }}
        </gl-button>

        <p
          v-if="showIncompleteRow"
          id="package-version-incomplete-row"
          role="alert"
          class="gl-mb-0 gl-text-danger"
          data-testid="incomplete-package-row"
        >
          {{ $options.i18n.incompleteRow }}
        </p>

        <p
          v-if="showInvalidLink"
          id="package-version-invalid-link"
          role="alert"
          class="gl-mb-0 gl-text-danger"
          data-testid="invalid-package-link"
        >
          {{ invalidLinkMessage }}
        </p>
      </div>
    </field-row>
  </div>
</template>
