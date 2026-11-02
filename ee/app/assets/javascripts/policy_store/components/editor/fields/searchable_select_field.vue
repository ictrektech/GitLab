<script>
import { GlCollapsibleListbox } from '@gitlab/ui';
import { searchInItemsProperties } from '~/lib/utils/search_utils';
import { s__ } from '~/locale';
import { fieldProps } from './field_props';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'SearchableSelectField',
  components: { FieldWrapper, GlCollapsibleListbox },
  props: {
    ...fieldProps,
    // Number because a long option list is typically keyed by record id.
    value: {
      type: [String, Number],
      required: false,
      default: '',
    },
  },
  emits: ['input'],
  data() {
    // Deliberately not cleared when the dropdown closes: GlCollapsibleListbox keeps its
    // own search input populated too and exposes no way to reset it, so clearing only
    // this side would leave a stale term sitting above an unfiltered list.
    return { searchTerm: '' };
  },
  computed: {
    items() {
      return (this.field.options || []).map(({ id, label }) => ({ value: id, text: label }));
    },
    // GlCollapsibleListbox does not filter for us: `searchable` only renders the input
    // and emits the term.
    filteredItems() {
      return searchInItemsProperties({
        items: this.items,
        properties: ['text'],
        searchQuery: this.searchTerm.trim(),
      });
    },
    hasValue() {
      return this.value !== '' && this.value != null;
    },
    // An empty array rather than the empty value: the listbox wraps a non-array
    // `selected` in one, so `''` would read as a selection and drop the subtle
    // placeholder styling from the toggle. A set value stays unwrapped for the same
    // reason inverted -- a one-item array trips the listbox's multi-select guard.
    // Caveat: the listbox hides its reset button for a falsy non-array `selected`, so
    // a field whose option ids start at 0 cannot be cleared (@gitlab/ui, not ours).
    selected() {
      return this.hasValue ? this.value : [];
    },
    placeholder() {
      return this.field.placeholder || s__('PolicyStore|Select...');
    },
    // An id the catalog no longer offers shows as itself, not as the placeholder:
    // configItemsFor does the same on the detail page, and showing "Select..." over a
    // value that is still set would invite the author to save it back unknowingly.
    toggleText() {
      if (!this.hasValue) return this.placeholder;

      return this.items.find(({ value }) => value === this.value)?.text ?? String(this.value);
    },
    // The listbox shows one empty state for both "nothing matched" and "nothing to
    // match", so the copy has to distinguish them here.
    emptyText() {
      return this.items.length
        ? s__('PolicyStore|No matching options')
        : s__('PolicyStore|No options available');
    },
  },
};
</script>

<template>
  <field-wrapper :field="field" :invalid-feedback="error">
    <!-- No `label-actions` slot content here, so GlBaseDropdown's own fallback names the
         toggle from the form group label, which holds the label text alone. A field that
         grows label actions must point `toggle-aria-labelled-by` at `labelTextId` instead,
         as field_wrapper.vue describes. -->
    <!-- Unlike its siblings the toggle gets no `aria-describedby`: GlCollapsibleListbox
         exposes no prop for it and fallthrough attributes land on the dropdown wrapper,
         not the button. `state` is all the invalid state it can carry today. -->
    <template #default="{ inputId, state }">
      <gl-collapsible-listbox
        :toggle-id="inputId"
        :state="state"
        :items="filteredItems"
        :selected="selected"
        :toggle-text="toggleText"
        :header-text="field.label"
        :search-placeholder="s__('PolicyStore|Search options')"
        :no-results-text="emptyText"
        :reset-button-label="__('Clear')"
        searchable
        block
        @search="searchTerm = $event"
        @reset="$emit('input', '')"
        @select="$emit('input', $event)"
      />
    </template>
  </field-wrapper>
</template>
