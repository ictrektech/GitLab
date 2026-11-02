<script>
import { GlButton, GlFormSelect, GlSprintf } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import { toNounSeriesText } from '~/lib/utils/grammar';
import { isRestricted, promisableOptions } from '../../../catalog/settings';
import { fieldProps } from './field_props';
import FieldWrapper from './field_wrapper.vue';

const emptyRow = () => ({ setting: '', expected: null });

// An option value is always a string, so a boolean true would otherwise be authored as
// "true", which the rule transpiler refuses on the value's type. JSON both ways keeps the
// type: `onValueChange` parses what this writes.
const toOptionValue = (value) =>
  value === null || value === undefined ? '' : JSON.stringify(value);

// Rows of { setting, expected } pairs, each persisted as its own rule. The choices, the
// permitted values and the restriction note all come off the catalog, so adopting the served
// catalog (https://gitlab.com/gitlab-org/gitlab/-/work_items/630152) edits catalog/settings.js
// and not this component.
export default {
  name: 'SettingExpectationsField',
  components: { FieldWrapper, GlButton, GlFormSelect, GlSprintf },
  props: {
    ...fieldProps,
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['input'],
  // Per instance: two of these fields on one screen would otherwise share a note id.
  data() {
    return { noteId: uniqueId('policy-store-expectation-note-') };
  },
  computed: {
    rows() {
      return this.value.length ? this.value : [emptyRow()];
    },
    // The lone row is a placeholder the model does not hold yet, so removing it would
    // re-render the identical row.
    removable() {
      return this.value.length > 0;
    },
    settingOptions() {
      return this.field.options || [];
    },
    // Named rather than counted: the author needs to know which row is the narrowed one.
    restrictedNames() {
      const names = this.rows
        .map(({ setting }) => this.settingFor(setting))
        .filter(isRestricted)
        .map(({ name }) => name);

      // Deduplicated because two rows may name the same setting until the duplicate blocker
      // fires on save. Joined as prose, since this one is read as a sentence.
      return toNounSeriesText([...new Set(names)]);
    },
  },
  methods: {
    settingFor(setting) {
      return this.field.settings?.[setting];
    },
    // A persisted setting the catalog no longer offers still names itself, rather than
    // reading as a row the author never filled in.
    unknownSetting(row) {
      return Boolean(row.setting) && !this.settingFor(row.setting);
    },
    describedBy(row) {
      return isRestricted(this.settingFor(row.setting)) ? this.noteId : null;
    },
    valueOptions(row) {
      return promisableOptions(this.settingFor(row.setting)) || [];
    },
    toOptionValue,
    // A value of the wrong shape belongs to a setting that is no longer selected, or to a
    // catalog that has since retyped this one; it selects nothing.
    selectedOptionValue(row) {
      const selected = toOptionValue(row.expected);

      return this.valueOptions(row).some((option) => toOptionValue(option.id) === selected)
        ? selected
        : '';
    },
    settingName(row, index) {
      return this.settingFor(row.setting)?.name || row.setting || index + 1;
    },
    // sprintf must not escape: these are announced as aria-labels, so a setting named
    // "Q&A gate" would otherwise be read out with the entity.
    settingLabel(row, index) {
      return sprintf(
        s__('PolicyStore|Project setting %{name}'),
        { name: this.settingName(row, index) },
        false,
      );
    },
    valueLabel(row, index) {
      return sprintf(
        s__('PolicyStore|Required value for %{name}'),
        { name: this.settingName(row, index) },
        false,
      );
    },
    removeLabel(row, index) {
      return sprintf(
        s__('PolicyStore|Remove setting %{name}'),
        { name: this.settingName(row, index) },
        false,
      );
    },
    emitRows(rows) {
      this.$emit('input', rows);
    },
    updateRow(index, patch) {
      this.emitRows(this.rows.map((row, i) => (i === index ? { ...row, ...patch } : row)));
    },
    onSettingChange(index, setting) {
      // Nothing is preselected even where the catalog permits one value only: a row the
      // author never answered would otherwise persist as a rule they never asked for.
      this.updateRow(index, { setting, expected: null });
    },
    onValueChange(index, optionValue) {
      this.updateRow(index, { expected: optionValue === '' ? null : JSON.parse(optionValue) });
    },
    addRow() {
      this.emitRows([...this.rows, emptyRow()]);
    },
    removeRow(index) {
      this.emitRows(this.rows.filter((_, i) => i !== index));
    },
  },
};
</script>

<template>
  <!-- The rows are a group of controls rather than one labelable element, so the wrapper's
       label names the group instead of pointing at a single input. -->
  <field-wrapper
    #default="{ labelTextId }"
    :field="field"
    :invalid-feedback="error"
    :labelled-control="false"
  >
    <div role="group" :aria-labelledby="labelTextId" class="gl-flex gl-flex-col gl-gap-3">
      <!-- Keyed by index, safe here as in freeze_windows_config.vue: every control binds
           :value from the row, so a re-used node is re-bound rather than left holding the
           removed row's answer. -->
      <div
        v-for="(row, index) in rows"
        :key="index"
        class="gl-flex gl-items-center gl-gap-3"
        data-testid="expectation-row"
      >
        <gl-form-select
          class="gl-flex-1"
          :value="row.setting"
          :aria-label="settingLabel(row, index)"
          data-testid="expectation-setting"
          @change="onSettingChange(index, $event)"
        >
          <option value="">{{ s__('PolicyStore|Select a setting') }}</option>
          <option v-if="unknownSetting(row)" :value="row.setting" disabled>
            {{ row.setting }}
          </option>
          <option v-for="option in settingOptions" :key="option.id" :value="option.id">
            {{ option.label }}
          </option>
        </gl-form-select>

        <gl-form-select
          v-if="row.setting"
          class="gl-flex-1"
          :value="selectedOptionValue(row)"
          :aria-label="valueLabel(row, index)"
          :aria-describedby="describedBy(row)"
          data-testid="expectation-value"
          @change="onValueChange(index, $event)"
        >
          <option value="">{{ s__('PolicyStore|Select a required value') }}</option>
          <option
            v-for="option in valueOptions(row)"
            :key="toOptionValue(option.id)"
            :value="toOptionValue(option.id)"
          >
            {{ option.label }}
          </option>
        </gl-form-select>

        <gl-button
          v-if="removable"
          icon="remove"
          category="tertiary"
          :aria-label="removeLabel(row, index)"
          data-testid="expectation-remove"
          @click="removeRow(index)"
        />
      </div>

      <p
        v-if="restrictedNames"
        :id="noteId"
        class="gl-mb-0 gl-text-subtle"
        data-testid="restriction-note"
      >
        <gl-sprintf
          :message="
            s__(
              'PolicyStore|%{settings}: a group or instance setting can still override the values not offered here, so only these values can be required.',
            )
          "
        >
          <template #settings>{{ restrictedNames }}</template>
        </gl-sprintf>
      </p>

      <gl-button
        category="tertiary"
        size="small"
        icon="plus"
        class="gl-self-start"
        data-testid="expectation-add"
        @click="addRow"
      >
        {{ s__('PolicyStore|Add setting') }}
      </gl-button>
    </div>
  </field-wrapper>
</template>
