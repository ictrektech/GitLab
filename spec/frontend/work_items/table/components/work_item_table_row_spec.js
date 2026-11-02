import { GlFormCheckbox } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemAssigneesCell from '~/work_items/table/components/work_item_assignees_cell.vue';
import WorkItemLabelsCell from '~/work_items/table/components/work_item_labels_cell.vue';
import WorkItemTableCell from '~/work_items/table/components/work_item_table_cell.vue';
import WorkItemTableRow from '~/work_items/table/components/work_item_table_row.vue';
import WorkItemTitleCell from '~/work_items/table/components/work_item_title_cell.vue';
import {
  COLUMN_ASSIGNEES,
  COLUMN_LABELS,
  COLUMN_REFERENCE,
  COLUMN_TITLE,
  TABLE_COLUMNS,
} from '~/work_items/table/constants';
import { buildWorkItemNode } from '../../board/mock_data';

describe('WorkItemTableRow', () => {
  let wrapper;

  const item = buildWorkItemNode(1, { title: 'Some work item' });
  const columns = TABLE_COLUMNS.filter(({ key }) => [COLUMN_TITLE, COLUMN_REFERENCE].includes(key));

  const findTitleCell = () => wrapper.findComponent(WorkItemTitleCell);
  const findCells = () => wrapper.findAllComponents(WorkItemTableCell);

  const findRow = () => wrapper.findByTestId('work-item-table-row');
  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findCheckboxCell = () => wrapper.findByTestId('work-item-table-checkbox-cell');

  const createComponent = ({ mountFn = shallowMountExtended, props = {} } = {}) => {
    wrapper = mountFn(WorkItemTableRow, {
      propsData: { item, columns, ...props },
      provide: { rootPageFullPath: 'group' },
    });
  };

  describe('cells', () => {
    beforeEach(() => {
      createComponent({ mountFn: mountExtended });
    });

    it('renders the title as the row header', () => {
      expect(wrapper.find('th').attributes('scope')).toBe('row');
    });

    it('renders a data cell for each of the other columns', () => {
      expect(wrapper.findAll('td')).toHaveLength(1);
      expect(findCells()).toHaveLength(1);
      expect(findCells().at(0).props('columnKey')).toBe(COLUMN_REFERENCE);
    });
  });

  describe('when a column has a cell component of its own', () => {
    beforeEach(() => {
      createComponent({
        props: {
          columns: TABLE_COLUMNS.filter(({ key }) =>
            [COLUMN_TITLE, COLUMN_ASSIGNEES, COLUMN_LABELS].includes(key),
          ),
        },
      });
    });

    it.each`
      column              | component
      ${COLUMN_ASSIGNEES} | ${WorkItemAssigneesCell}
      ${COLUMN_LABELS}    | ${WorkItemLabelsCell}
    `('renders the $column cell with the work item', ({ component }) => {
      expect(wrapper.findComponent(component).props('item')).toBe(item);
    });

    it('does not render the shared cell for it', () => {
      expect(findCells()).toHaveLength(0);
    });
  });

  describe('title', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the title cell with the work item', () => {
      expect(findTitleCell().props('item')).toBe(item);
    });
  });

  describe('when the detail panel is enabled', () => {
    beforeEach(() => {
      createComponent({ props: { detailPanelEnabled: true } });
    });

    it('passes detailPanelEnabled to title cell', () => {
      expect(findTitleCell().props('detailPanelEnabled')).toBe(true);
    });

    it('passes isActive to title cell', () => {
      createComponent({ props: { detailPanelEnabled: true, activeItem: item } });

      expect(findTitleCell().props('isActive')).toBe(true);
    });

    it('emits set-active-item when title cell emits it', () => {
      findTitleCell().vm.$emit('set-active-item', item);

      expect(wrapper.emitted('set-active-item')).toEqual([[item]]);
    });

    describe('and the work item is the one already open', () => {
      beforeEach(() => {
        createComponent({ props: { detailPanelEnabled: true, activeItem: item } });
      });

      it('marks the row as the current one', () => {
        expect(findRow().attributes('aria-current')).toBe('true');
        expect(findRow().classes()).toContain('!gl-bg-strong');
      });
    });
  });

  describe('when the detail panel is disabled', () => {
    beforeEach(() => {
      createComponent();
    });

    it('passes detailPanelEnabled as false to title cell', () => {
      expect(findTitleCell().props('detailPanelEnabled')).toBe(false);
    });
  });

  describe('bulk edit checkbox', () => {
    it('is absent by default', () => {
      createComponent({ mountFn: mountExtended });

      expect(findCheckboxCell().exists()).toBe(false);
      expect(wrapper.findAll('td')).toHaveLength(1);
    });

    describe('when the row can be selected', () => {
      beforeEach(() => {
        createComponent({ mountFn: mountExtended, props: { showCheckbox: true } });
      });

      it('renders an unchecked checkbox named after the work item', () => {
        expect(findCheckbox().props('checked')).toBe(false);
        expect(findCheckboxCell().text()).toBe(item.title);
      });

      it('reports the new state when checked', async () => {
        // A synthetic click ticks the box without firing `change`, which is the event the
        // checkbox actually listens to, so this toggles it the way a real one would.
        const checkbox = wrapper.find('input[type="checkbox"]');
        checkbox.element.checked = true;
        await checkbox.trigger('change');

        expect(wrapper.emitted('checked-input')).toEqual([[true]]);
      });
    });

    describe('while the side panel is enabled', () => {
      beforeEach(() => {
        createComponent({
          mountFn: mountExtended,
          props: { showCheckbox: true, detailPanelEnabled: true },
        });
      });

      it('does not open the side panel during bulk edit', () => {
        expect(findTitleCell().props('detailPanelEnabled')).toBe(false);
      });
    });

    it('renders a checked checkbox when the row is selected', () => {
      createComponent({ mountFn: mountExtended, props: { showCheckbox: true, checked: true } });

      expect(findCheckbox().props('checked')).toBe(true);
    });
  });
});
