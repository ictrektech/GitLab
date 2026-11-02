<script>
import { GlFormCheckbox } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { COLUMN_ASSIGNEES, COLUMN_LABELS, COLUMN_TITLE } from '../constants';
import WorkItemAssigneesCell from './work_item_assignees_cell.vue';
import WorkItemLabelsCell from './work_item_labels_cell.vue';
import WorkItemTableCell from './work_item_table_cell.vue';
import WorkItemTitleCell from './work_item_title_cell.vue';

// Columns with a cell component of their own. Every other column is rendered by
// WorkItemTableCell, which needs to be told the column.
const CELL_COMPONENTS = {
  [COLUMN_TITLE]: WorkItemTitleCell,
  [COLUMN_ASSIGNEES]: WorkItemAssigneesCell,
  [COLUMN_LABELS]: WorkItemLabelsCell,
};

export default {
  name: 'WorkItemTableRow',
  components: {
    GlFormCheckbox,
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    columns: {
      type: Array,
      required: true,
    },
    activeItem: {
      type: Object,
      required: false,
      default: null,
    },
    detailPanelEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    showCheckbox: {
      type: Boolean,
      required: false,
      default: false,
    },
    checked: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['set-active-item', 'checked-input'],
  computed: {
    isActive() {
      return Boolean(
        this.activeItem &&
        getIdFromGraphQLId(this.item.id) === getIdFromGraphQLId(this.activeItem.id),
      );
    },
    isRowClickable() {
      return this.detailPanelEnabled && !this.showCheckbox;
    },
    // Decides element, role and cell once per column, so the template doesn't re-derive them
    // per cell. Inline-editable cells manage their own padding so the entire cell is clickable.
    normalizedColumns() {
      return this.columns.map((column) => {
        const cell = CELL_COMPONENTS[column.key];
        return {
          ...column,
          tag: column.rowHeader ? 'th' : 'td',
          scope: column.rowHeader ? 'row' : null,
          cell: cell ?? WorkItemTableCell,
          cellProps: this.cellPropsFor(column, Boolean(cell)),
        };
      });
    },
  },
  methods: {
    // Every cell takes the item. The row header also opens the work item, so it gets the
    // row's state, and the shared read-only cell needs to know which column it renders.
    cellPropsFor(column, hasOwnCell) {
      if (column.rowHeader) {
        return { isActive: this.isActive, detailPanelEnabled: this.isRowClickable };
      }
      return hasOwnCell ? {} : { columnKey: column.key };
    },
  },
};
</script>

<template>
  <tr
    class="gl-border-b last:gl-border-b-0 hover:gl-bg-subtle"
    :class="{
      '!gl-bg-strong hover:!gl-bg-strong': isActive,
      'gl-cursor-pointer': isRowClickable,
    }"
    :aria-current="isActive ? 'true' : undefined"
    data-testid="work-item-table-row"
  >
    <td
      v-if="showCheckbox"
      class="gl-border-r gl-px-4 gl-py-3 gl-align-middle"
      data-testid="work-item-table-checkbox-cell"
    >
      <gl-form-checkbox
        class="gl-mx-auto gl-min-h-0 gl-w-5 gl-leading-16"
        :checked="checked"
        @input="$emit('checked-input', $event)"
      >
        <span class="gl-sr-only">{{ item.title }}</span>
      </gl-form-checkbox>
    </td>
    <component
      :is="column.tag"
      v-for="column in normalizedColumns"
      :key="column.key"
      :scope="column.scope"
      class="gl-border-r gl-truncate gl-text-left gl-align-middle gl-font-normal last:gl-border-r-0"
      :class="{ 'gl-px-4 gl-py-3': !column.inlineEditable }"
    >
      <component
        :is="column.cell"
        :item="item"
        v-bind="column.cellProps"
        @set-active-item="$emit('set-active-item', $event)"
      />
    </component>
  </tr>
</template>
