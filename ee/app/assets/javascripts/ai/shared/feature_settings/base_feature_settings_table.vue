<script>
import { GlTable, GlSkeletonLoader } from '@gitlab/ui';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import { groupDuoCodeReviewDepths } from './utils';

const LOADER_ITEMS_COUNT = 3;

export default {
  name: 'BaseFeatureSettingsTable',
  components: {
    GlTable,
    GlSkeletonLoader,
  },
  mixins: [glSlotsMixin],
  props: {
    fields: {
      type: Array,
      required: true,
    },
    items: {
      type: Array,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      // Position of each feature from the last sort, or null when unsorted. Rows keep this
      // position when a cell value changes, so an edited row does not jump elsewhere.
      sortRank: null,
    };
  },
  computed: {
    loaderItems() {
      // create placeholder items to render during loading
      return new Array(LOADER_ITEMS_COUNT).fill(true);
    },
    tableFields() {
      return this.fields.map((field) => ({
        ...field,
        // Rows are placeholders while loading, so there is nothing to sort yet.
        sortable: Boolean(field.sortable) && !this.isLoading,
        // Rows of a depth block drop the border and padding between them, so they read as one feature.
        tdClass: (_value, _key, item) => [
          'gl-content-center !gl-border-b-0',
          { '!gl-border-t-0': item?.isDepthChild },
          { '!gl-pb-0': (item?.isDepthHeader || item?.isDepthChild) && !item?.isDepthBlockEnd },
        ],
      }));
    },
    titleSlot() {
      return `cell(${this.fields[0].key})`;
    },
    displayItems() {
      if (this.isLoading) return this.loaderItems;
      if (!this.sortRank) return groupDuoCodeReviewDepths(this.items);

      return groupDuoCodeReviewDepths(
        [...this.items].sort((a, b) => this.sortRank[a.feature] - this.sortRank[b.feature]),
      );
    },
  },
  methods: {
    onSortChanged({ sortBy, sortDesc }) {
      const collator = new Intl.Collator(undefined, { numeric: true });
      const sortValue = (item) => String(item[sortBy] ?? '');

      // Negate rather than reverse, so rows with equal values keep their relative order.
      const direction = sortDesc ? -1 : 1;
      const sorted = [...this.items].sort(
        (a, b) => collator.compare(sortValue(a), sortValue(b)) * direction,
      );

      this.sortRank = Object.fromEntries(sorted.map(({ feature }, index) => [feature, index]));
    },
    showSlot(slot, scope) {
      if (slot.startsWith('head')) return true;
      if (this.isLoading) return false;
      if (scope.item.isDepthHeader) return slot === this.titleSlot;

      return !this.showDepthLabel(scope, slot);
    },
    showDepthLabel(scope, slot) {
      return !this.isLoading && slot === this.titleSlot && Boolean(scope.item?.isDepthChild);
    },
    showLoader(scope, slot) {
      // only display loaders non-header cells
      if (!slot.startsWith('cell')) return false;

      if (!scope.field.loaderWidths) return false;

      return this.isLoading;
    },
    getLoaderWidth(scope) {
      const { loaderWidths } = scope.field;

      return loaderWidths[scope.index % loaderWidths.length];
    },
  },
};
</script>
<template>
  <gl-table
    class="gl-border gl-mb-0 gl-rounded-lg gl-border-section gl-bg-section"
    tbody-tr-class="gl-bg-subtle"
    :fields="tableFields"
    :items="displayItems"
    primary-key="feature"
    responsive
    borderless
    no-local-sorting
    @sort-changed="onSortChanged"
  >
    <template v-for="slot in Object.keys(glSlots())" #[slot]="scope">
      <div v-if="showLoader(scope, slot)" :key="slot" :class="scope.field.loaderClass">
        <gl-skeleton-loader :height="38" :width="600">
          <rect y="8" x="0" :width="getLoaderWidth(scope)" height="24" rx="10" />
        </gl-skeleton-loader>
      </div>
      <span v-if="showDepthLabel(scope, slot)" :key="`${slot}-depth`" class="gl-ml-5">
        {{ scope.item.depthLabel }}
        <span class="gl-text-subtle"
          ><span aria-hidden="true">·</span> {{ scope.item.depthDescription }}</span
        >
      </span>
      <slot v-if="showSlot(slot, scope)" :name="slot" v-bind="scope"></slot>
    </template>
  </gl-table>
</template>
