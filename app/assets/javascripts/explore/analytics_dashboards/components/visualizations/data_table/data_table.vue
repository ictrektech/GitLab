<script>
import { GlIcon, GlTable, GlTableLite, GlKeysetPagination, GlTooltipDirective } from '@gitlab/ui';
import { defaultSortCompare } from '@gitlab/ui/src/vendor/bootstrap-vue/src/components/table/helpers/default-sort-compare';
import { get, uniqueId } from 'lodash-es';
import RowDisclosureToggle from '~/vue_shared/components/expandable_rows/row_disclosure_toggle.vue';
import { flattenTree, rowDomId, sortTree } from '~/vue_shared/components/expandable_rows/utils';
import DataTableCell from './data_table_cell.vue';

const DEFAULT_PAGE_SIZE = 20;
const SUPPORTED_FIELD_KEY_PATTERN = /^[a-zA-Z0-9][\w-]*(\.[a-zA-Z0-9][\w-]*)*$/;

// Reserved keys on an expandable row. A supported field key cannot start with `_`.
const ROW_KEY = '_rowKey';
const ROW_META_KEY = '_row';

const hasSupportedFieldKey = ({ key }) =>
  typeof key === 'string' && SUPPORTED_FIELD_KEY_PATTERN.test(key);

// Cells are top-aligned, which puts the text beside a row's toggle lower than the text in the
// other cells, so an expandable table centers its cells.
const withCenteredCells = (fields) =>
  fields?.map((field) => ({
    ...field,
    tdClass: [field.tdClass, '!gl-align-middle'].filter(Boolean),
  }));

// Keys each node by its `id` under its parent's key when it has one, so expanded rows stay
// expanded through a sort and a node listed under two parents gets two keys. Nodes without an
// `id` are keyed by their position in the tree.
const withRowKeys = (nodes, parentKey = null, parentPath = []) =>
  nodes.map((node, index) => {
    const path = [...parentPath, index];
    const key = JSON.stringify(node.id != null ? { parent: parentKey, id: node.id } : { path });

    return {
      ...node,
      [ROW_KEY]: key,
      children: withRowKeys(node.children ?? [], key, path),
    };
  });

const keysOf = (nodes) => nodes.flatMap((node) => [node[ROW_KEY], ...keysOf(node.children)]);

// True when the key and every ancestor's key come from an `id`, not a position.
const isIdKey = (key) => {
  const { parent, id } = JSON.parse(key);

  return id != null && (parent == null || isIdKey(parent));
};

// The comparator BTable sorts a flat table with, so an expandable one sorts the same way.
const compareBy = (sortBy, sortDesc) => (a, b) =>
  defaultSortCompare(a, b, { sortBy }) * (sortDesc ? -1 : 1);

// Names a row for its toggle. Cells rendered by a component take an object, such as a user.
const labelOf = (value) => {
  if (value == null) return '';
  if (typeof value !== 'object') return String(value);

  return String(value.text ?? value.name ?? value.fullName ?? value.title ?? '');
};

export default {
  name: 'DataTable',
  components: {
    DataTableCell,
    GlIcon,
    GlTable,
    GlTableLite,
    GlKeysetPagination,
    RowDisclosureToggle,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    data: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    options: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    query: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['update-query'],
  data() {
    return {
      expandedKeys: [],
      localSort: null,
    };
  },
  computed: {
    tableComponent() {
      const hasSorting = this.sanitizedOptions.fields?.some(({ sortable }) => Boolean(sortable));
      return hasSorting ? GlTable : GlTableLite;
    },
    nodes() {
      return this.data.nodes || [];
    },
    pageInfo() {
      return this.data.pageInfo || {};
    },
    derivedFields() {
      // NOTE: we derive the field names from the keys in the first row of data
      // unless a custom field config is passed in the visualization options
      if (this.nodes.length < 1) {
        return null;
      }

      // An expandable row's `children` are rows of their own, not a column.
      const keys = Object.keys(this.nodes[0]).filter(
        (key) => !(this.options.expandableRows && key === 'children'),
      );

      return keys.map((key) => ({
        key,
        tdClass: 'gl-truncate gl-max-w-0',
      }));
    },
    sanitizedOptions() {
      const { responsive, fixed, stacked, fields, refetchOnSort, expandableRows } = this.options;
      const sanitizedFields = fields ? fields.filter(hasSupportedFieldKey) : this.derivedFields;

      return {
        responsive: responsive ?? true,
        fixed: fixed ?? false,
        stacked: stacked ?? false,
        refetchOnSort: refetchOnSort ?? false,
        expandableRows: expandableRows ?? false,
        fields: expandableRows ? withCenteredCells(sanitizedFields) : sanitizedFields,
      };
    },
    showPaginationControls() {
      return Boolean(this.pageInfo.hasPreviousPage || this.pageInfo.hasNextPage);
    },
    sort() {
      return this.localSort ?? { sortBy: this.query.sortBy, sortDesc: this.query.sortDesc };
    },
    // BTable sorts the flat list it is given, which would pull children away from their
    // parents, so an expandable table sorts its tree itself.
    items() {
      if (!this.sanitizedOptions.expandableRows) return this.nodes;

      const { sortBy, sortDesc } = this.sort;
      const tree = this.keyedTree;
      const sortedTree = sortBy ? sortTree(tree, compareBy(sortBy, sortDesc)) : tree;

      const rows = flattenTree(sortedTree, {
        keyOf: (node) => node[ROW_KEY],
        expandedKeys: new Set(this.expandedKeys),
      });
      // Names each child row's parent for its toggle, which tells screen readers.
      const labels = new Map(
        rows.map(({ key, node }) => [key, labelOf(get(node, this.toggleFieldKey))]),
      );

      return rows.map((row) => ({
        ...row.node,
        [ROW_META_KEY]: { ...row, parentLabel: labels.get(row.parentKey) ?? '' },
      }));
    },
    keyedTree() {
      return this.sanitizedOptions.expandableRows ? withRowKeys(this.nodes) : [];
    },
    toggleFieldKey() {
      return this.sanitizedOptions.expandableRows ? this.sanitizedOptions.fields?.[0]?.key : null;
    },
  },
  watch: {
    // A refetch after a sort returns the same rows, so only rows that are gone collapse.
    keyedTree() {
      const keys = new Set(keysOf(this.keyedTree));
      const expandedKeys = this.expandedKeys.filter((key) => keys.has(key));
      if (expandedKeys.length !== this.expandedKeys.length) this.expandedKeys = expandedKeys;
    },
  },
  created() {
    // Not reactive: only a prefix for the DOM ids the toggles point at.
    this.rowIdPrefix = uniqueId('data-table-row-');
  },
  methods: {
    nextPage() {
      this.expandedKeys = [];
      const { first, last, endCursor } = this.pageInfo;
      this.$emit('update-query', {
        pagination: {
          first: first ?? last ?? DEFAULT_PAGE_SIZE,
          endCursor,
        },
      });
    },
    prevPage() {
      this.expandedKeys = [];
      const { first, last, startCursor } = this.pageInfo;
      this.$emit('update-query', {
        pagination: {
          last: last ?? first ?? DEFAULT_PAGE_SIZE,
          startCursor,
        },
      });
    },
    onSortingChanged({ sortBy, sortDesc }) {
      if (this.sanitizedOptions.expandableRows) this.localSort = { sortBy, sortDesc };

      if (this.sanitizedOptions.refetchOnSort) {
        // The server reorders the rows, so a position key would point at another row.
        this.expandedKeys = this.expandedKeys.filter(isIdKey);
        this.$emit('update-query', { sortBy, sortDesc, pagination: undefined });
      }
    },
    rowAttributes(item) {
      const row = item?.[ROW_META_KEY];

      return row?.depth ? { id: rowDomId(this.rowIdPrefix, row.key) } : {};
    },
    toggleLabel(value) {
      return labelOf(value);
    },
    childRowIds(row) {
      return row.childKeys.map((key) => rowDomId(this.rowIdPrefix, key));
    },
    toggleRow(row) {
      this.expandedKeys = row.expanded
        ? this.expandedKeys.filter((key) => key !== row.key)
        : [...this.expandedKeys, row.key];
    },
  },
  ROW_KEY,
  ROW_META_KEY,
};
</script>

<template>
  <div>
    <component
      :is="tableComponent"
      :fields="sanitizedOptions.fields"
      :responsive="sanitizedOptions.responsive"
      :fixed="sanitizedOptions.fixed"
      :stacked="sanitizedOptions.stacked"
      :no-local-sorting="sanitizedOptions.refetchOnSort || sanitizedOptions.expandableRows"
      :items="items"
      :primary-key="sanitizedOptions.expandableRows ? $options.ROW_KEY : undefined"
      :tbody-tr-attr="sanitizedOptions.expandableRows ? rowAttributes : undefined"
      :sort-by="query.sortBy"
      :sort-desc="query.sortDesc"
      hover
      borderless
      @sort-changed="onSortingChanged"
    >
      <template #head()="{ label, field: { tooltip } }">
        {{ label }}
        <gl-icon
          v-if="tooltip"
          v-gl-tooltip.hover
          class="gl-text-blue-600"
          name="information-o"
          :title="tooltip"
        />
      </template>
      <template #cell()="{ value, field, item }">
        <row-disclosure-toggle
          v-if="field.key === toggleFieldKey"
          :label="toggleLabel(value)"
          :expandable="item[$options.ROW_META_KEY].expandable"
          :expanded="item[$options.ROW_META_KEY].expanded"
          :depth="item[$options.ROW_META_KEY].depth"
          :parent-label="item[$options.ROW_META_KEY].parentLabel"
          :child-row-ids="childRowIds(item[$options.ROW_META_KEY])"
          @toggle="toggleRow(item[$options.ROW_META_KEY])"
        >
          <data-table-cell :value="value" :field="field" />
        </row-disclosure-toggle>
        <data-table-cell v-else :value="value" :field="field" />
      </template>
    </component>
    <gl-keyset-pagination
      v-if="showPaginationControls"
      class="gl-m-3 gl-flex gl-items-center gl-justify-center"
      :has-previous-page="pageInfo.hasPreviousPage"
      :has-next-page="pageInfo.hasNextPage"
      :start-cursor="pageInfo.startCursor"
      :end-cursor="pageInfo.endCursor"
      @prev="prevPage"
      @next="nextPage"
    />
  </div>
</template>
