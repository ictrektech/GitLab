import { nextTick } from 'vue';
import { GlIcon, GlTable, GlTableLite, GlKeysetPagination } from '@gitlab/ui';
import { mount, shallowMount } from '@vue/test-utils';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import DataTable from '~/explore/analytics_dashboards/components/visualizations/data_table/data_table.vue';
import DiffLineChanges from '~/explore/analytics_dashboards/components/visualizations/data_table/diff_line_changes.vue';
import CalculatePercent from '~/explore/analytics_dashboards/components/visualizations/data_table/calculate_percent.vue';
import RowDisclosureToggle from '~/vue_shared/components/expandable_rows/row_disclosure_toggle.vue';

describe('DataTable Visualization', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findSortableTable = () => wrapper.findComponent(GlTable);
  const findTableHeaders = () => findTable().findAll('th');
  const findTableRowCells = (idx) => findTable().find('tbody').findAll('tr').at(idx).findAll('td');
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);

  const nodes = [{ field_one: 'alpha', field_two: 'beta', field_three: 'gamma' }];

  const createWrapper = (mountFn = shallowMount, props = {}) => {
    wrapper = extendedWrapper(
      mountFn(DataTable, {
        propsData: {
          data: { nodes },
          options: {},
          ...props,
        },
        stubs: {
          DiffLineChanges,
          CalculatePercent,
        },
      }),
    );
  };

  describe('default behaviour', () => {
    it('should render the table with the expected attributes', () => {
      createWrapper();

      expect(findTable().attributes()).toMatchObject({
        responsive: 'true',
        hover: '',
      });
    });

    it('should render and style the table headers', () => {
      createWrapper(mount);

      const headers = findTableHeaders();

      expect(headers).toHaveLength(3);

      ['Field One', 'Field Two'].forEach((headerText, idx) => {
        expect(headers.at(idx).text()).toBe(headerText);
      });
    });

    it('should render and style the table cells', () => {
      createWrapper(mount);

      const rowCells = findTableRowCells(0);

      expect(rowCells).toHaveLength(3);

      Object.values(nodes[0]).forEach((value, idx) => {
        expect(rowCells.at(idx).text()).toBe(value);
        expect(rowCells.at(idx).classes()).toEqual(
          expect.arrayContaining(['gl-truncate', 'gl-max-w-0']),
        );
      });
    });

    it('should not add delimiters for small numbers', () => {
      createWrapper(mount, {
        data: {
          nodes: [
            {
              field_one: 123,
            },
          ],
        },
      });

      const rowCells = findTableRowCells(0);

      expect(rowCells.at(0).text()).toBe('123');
    });

    it.each([
      [1234, '1,234'],
      [12345, '12,345'],
      [123456789, '123,456,789'],
    ])('should format "%d" with delimiters as "%s"', (value, expected) => {
      createWrapper(mount, {
        data: {
          nodes: [
            {
              field_one: value,
            },
          ],
        },
      });

      const rowCells = findTableRowCells(0);

      expect(rowCells.at(0).text()).toBe(expected);
    });
  });

  describe('with links data', () => {
    it('should render values as links when provided with links data', () => {
      const linksData = [
        { foo: { text: 'foo', href: 'https://example.com/foo' } },
        { bar: { text: 'bar', href: 'https://example.com/bar' } },
      ];
      createWrapper(mount, { data: { nodes: linksData } });

      const rowCells = findTableRowCells(0);

      Object.values(linksData[0]).forEach((linkConfig, idx) => {
        const link = rowCells.at(idx).find('a');

        expect(link.exists()).toBe(true);
        expect(link.text()).toBe(linkConfig.text);
        expect(link.attributes('href')).toBe(linkConfig.href);
      });
    });

    it('should render external link icon for external links', () => {
      const linksData = [{ foo: { text: 'foo', href: 'https://example.com/foo' } }];
      createWrapper(mount, { data: { nodes: linksData } });

      const rowCells = findTableRowCells(0);

      Object.values(linksData[0]).forEach((linkConfig, idx) => {
        const icon = rowCells.at(idx).find('a').findComponent(GlIcon);

        expect(icon.exists()).toBe(true);
        expect(icon.props('name')).toBe('external-link');
      });
    });

    it('should not add delimiters to link text for small numbers', () => {
      createWrapper(mount, {
        data: {
          nodes: [{ foo: { text: 123, href: 'https://example.com/foo' } }],
        },
      });

      const rowCells = findTableRowCells(0);

      expect(rowCells.at(0).text()).toBe('123');
    });

    it.each([
      [1234, '1,234'],
      [12345, '12,345'],
      [123456789, '123,456,789'],
    ])('should format link text of "%d" with delimiters as "%s"', (value, expected) => {
      createWrapper(mount, {
        data: {
          nodes: [{ foo: { text: value, href: 'https://example.com/foo' } }],
        },
      });

      const rowCells = findTableRowCells(0);

      expect(rowCells.at(0).text()).toBe(expected);
    });

    it('should not allow unsafe URLs to be linkable', () => {
      /* eslint-disable no-script-url */
      const linksData = [
        { foo: { text: 'foo', href: 'https://example.com/foo' } },
        { foo: { text: 'bar', href: 'javascript:alert("XSS")' } },
      ];
      /* eslint-enable no-script-url */

      createWrapper(mount, { data: { nodes: linksData } });

      const badLink = findTableRowCells(1).at(0).find('a');

      expect(findTableRowCells(0).at(0).find('a').exists()).toBe(true);
      expect(badLink.text()).toBe('bar');
      expect(badLink.attributes('href')).toBe('about:blank');
    });
  });

  describe('pagination', () => {
    it('does not render page controls if there is no other pages', () => {
      createWrapper();

      expect(findPagination().exists()).toBe(false);
    });

    describe('with previous page', () => {
      const pageInfo = { hasPreviousPage: true, startCursor: 'start', first: 10 };

      beforeEach(() => {
        createWrapper(mount, { data: { nodes, pageInfo } });
      });

      it('renders pagination controls', () => {
        expect(findPagination().props()).toMatchObject({
          hasPreviousPage: pageInfo.hasPreviousPage,
          startCursor: pageInfo.startCursor,
        });
      });

      it('emits updateQuery when selected', () => {
        findPagination().vm.$emit('prev');

        expect(wrapper.emitted('update-query')[0][0]).toMatchObject({
          pagination: {
            startCursor: pageInfo.startCursor,
            last: 10,
          },
        });
      });
    });

    describe('with next page', () => {
      const pageInfo = { hasNextPage: true, endCursor: 'end', first: 10 };

      beforeEach(() => {
        createWrapper(mount, { data: { nodes, pageInfo } });
      });

      it('renders pagination controls', () => {
        expect(findPagination().props()).toMatchObject({
          hasNextPage: pageInfo.hasNextPage,
          endCursor: pageInfo.endCursor,
        });
      });

      it('emits updateQuery when selected', () => {
        findPagination().vm.$emit('next');

        expect(wrapper.emitted('update-query')[0][0]).toMatchObject({
          pagination: {
            endCursor: pageInfo.endCursor,
            first: 10,
          },
        });
      });
    });
  });

  describe('sorting', () => {
    const sortableOpts = { fields: [{ key: 'field_one', sortable: true }] };

    it('uses GlTableLite when no fields are sortable', () => {
      createWrapper(shallowMount);

      expect(findTable().exists()).toBe(true);
      expect(findSortableTable().exists()).toBe(false);
    });

    it('uses GlTableLite when the only sortable field has an unsupported key', () => {
      createWrapper(shallowMount, {
        options: { fields: [{ key: '_meta.value', sortable: true }] },
      });

      expect(findTable().exists()).toBe(true);
      expect(findSortableTable().exists()).toBe(false);
    });

    it('does not pass sort params when not provided in the query', () => {
      createWrapper(shallowMount, { options: sortableOpts });

      expect(findSortableTable().props('sortBy')).toBeUndefined();
      expect(findSortableTable().props('sortDesc')).toBe(false);
    });

    it('passes sortBy to the table when set in the query', () => {
      createWrapper(shallowMount, {
        options: sortableOpts,
        query: {
          sortBy: 'field_one',
        },
      });

      expect(findSortableTable().props('sortBy')).toBe('field_one');
    });

    it('passes sortDesc to the table when set in the query', () => {
      createWrapper(shallowMount, {
        options: sortableOpts,
        query: {
          sortDesc: true,
        },
      });

      expect(findSortableTable().props('sortDesc')).toBe(true);
    });

    it('emits updateQuery when refetchOnSort is enabled and sorting changes', () => {
      createWrapper(shallowMount, {
        options: {
          ...sortableOpts,
          refetchOnSort: true,
        },
      });

      findSortableTable().vm.$emit('sort-changed', {
        sortBy: 'field_two',
        sortDesc: true,
      });

      expect(wrapper.emitted('update-query')[0][0]).toStrictEqual({
        sortBy: 'field_two',
        sortDesc: true,
        pagination: undefined,
      });
    });

    it('does not emit updateQuery when refetchOnSort is disabled and sorting changes', () => {
      createWrapper(shallowMount, {
        options: {
          ...sortableOpts,
          refetchOnSort: false,
        },
      });

      findSortableTable().vm.$emit('sort-changed', {
        sortBy: 'field_two',
        sortDesc: true,
      });

      expect(wrapper.emitted('update-query')).toBeUndefined();
    });
  });

  describe('options', () => {
    describe('fields', () => {
      it('can specify the fields to render', () => {
        createWrapper(mount, {
          options: {
            fields: [{ key: 'field_three' }, { key: 'field_two' }],
          },
        });

        const rowCells = findTableRowCells(0);
        expect(rowCells).toHaveLength(2);

        const headers = findTableHeaders();
        expect(headers).toHaveLength(2);

        [
          { field: 'Field Three', value: 'gamma' },
          { field: 'Field Two', value: 'beta' },
        ].forEach(({ field, value }, index) => {
          expect(headers.at(index).text()).toBe(field);
          expect(rowCells.at(index).text()).toBe(value);
        });
      });

      it('only renders fields with a supported key format', () => {
        createWrapper(mount, {
          options: {
            fields: [
              { key: 'field_one' },
              { key: 'sign-up_date' },
              { key: 'nested.field.value' },
              { key: '_meta.value' },
            ],
          },
        });

        expect(findTableHeaders().wrappers.map((header) => header.text())).toEqual([
          'Field One',
          'Sign-up Date',
          'Nested.field.value',
        ]);
      });

      it('can disable the default responsive table layout', () => {
        createWrapper(shallowMount, {
          options: {
            responsive: false,
          },
        });

        expect(findTable().attributes().responsive).toBeUndefined();
      });

      it('can set a fixed table layout', () => {
        createWrapper(shallowMount, {
          options: {
            fixed: true,
          },
        });

        expect(findTable().attributes().fixed).toBe('true');
      });

      it('can set a stacked table layout', () => {
        createWrapper(shallowMount, {
          options: {
            stacked: 'md',
          },
        });

        expect(findTable().attributes().stacked).toBe('md');
      });

      it('disables local sorting when refetchOnSort is enabled', () => {
        createWrapper(shallowMount, {
          options: {
            refetchOnSort: true,
          },
        });

        expect(findTable().attributes('no-local-sorting')).toBe('true');
      });

      it('can customize column labels', () => {
        createWrapper(mount, {
          options: {
            fields: [
              { key: 'field_three', label: 'Power level' },
              { key: 'field_two', label: 'Saiyan level' },
            ],
          },
        });

        const headers = findTableHeaders();
        expect(headers).toHaveLength(2);

        ['Power level', 'Saiyan level'].forEach((field, index) => {
          expect(headers.at(index).text()).toBe(field);
        });
      });

      it('renders a custom component with the correct props', () => {
        const customData = { additions: 10, deletions: 10 };

        createWrapper(mount, {
          data: { nodes: [{ customData }] },
          options: {
            fields: [{ key: 'customData', component: 'DiffLineChanges' }],
          },
        });

        expect(wrapper.findComponent(DiffLineChanges).props()).toMatchObject(customData);
      });

      describe('tooltip', () => {
        it('does not render a tooltip icon when tooltip is not provided', () => {
          createWrapper(mount, {
            options: {
              fields: [{ key: 'field_one', label: 'Field One' }],
            },
          });

          const headers = findTableHeaders();
          const tooltipIcon = headers.at(0).findComponent(GlIcon);

          expect(tooltipIcon.exists()).toBe(false);
        });

        it('renders a tooltip icon when tooltip is provided in field config', () => {
          const tooltip = 'This is a helpful tooltip';

          createWrapper(mount, {
            options: {
              fields: [{ key: 'field_one', label: 'Field One', tooltip }],
            },
          });

          const headers = findTableHeaders();
          const tooltipIcon = headers.at(0).findComponent(GlIcon);

          expect(tooltipIcon.exists()).toBe(true);
          expect(tooltipIcon.props('name')).toBe('information-o');
          expect(tooltipIcon.attributes('title')).toBe(tooltip);
        });
      });
    });
  });

  describe('expandableRows', () => {
    const treeNodes = [
      {
        id: 'group-1',
        name: 'Platform',
        users: 5,
        children: [
          { name: 'web', users: 1 },
          { name: 'api', users: 4 },
        ],
      },
      { id: 'group-2', name: 'Mobile', users: 2 },
    ];
    const fields = [
      { key: 'name', label: 'Name' },
      { key: 'users', label: 'Users' },
    ];

    const findToggles = () => wrapper.findAllComponents(RowDisclosureToggle);
    const findRows = () => wrapper.find('tbody').findAll('tr');
    const screenReaderText = (wrapperEl) => {
      const srText = wrapperEl.find('.gl-sr-only');
      return srText.exists() ? srText.text() : null;
    };
    // The text on screen, without what only screen readers get.
    const visibleText = (td) =>
      td
        .text()
        .replace(screenReaderText(td) ?? '', '')
        .trim();
    const findRowTexts = () =>
      findRows().wrappers.map((row) => row.findAll('td').wrappers.map(visibleText));

    const createExpandableWrapper = (options = {}) =>
      createWrapper(mount, {
        data: { nodes: treeNodes },
        options: { expandableRows: true, fields, ...options },
      });

    const expandFirstRow = async () => {
      findToggles().at(0).vm.$emit('toggle');
      await nextTick();
    };

    it('renders only the top-level rows at first', () => {
      createExpandableWrapper();

      expect(findRowTexts()).toEqual([
        ['Platform', '5'],
        ['Mobile', '2'],
      ]);
    });

    it('renders a toggle on rows with children and holds the space on the others', () => {
      createExpandableWrapper();

      expect(findToggles().wrappers.map((toggle) => toggle.props())).toEqual([
        expect.objectContaining({ label: 'Platform', expandable: true, expanded: false }),
        expect.objectContaining({ label: 'Mobile', expandable: false, expanded: false }),
      ]);
    });

    it('does not render the children as a column when fields are derived', () => {
      createWrapper(mount, {
        data: { nodes: treeNodes },
        options: { expandableRows: true },
      });

      expect(
        findTable()
          .findAll('th')
          .wrappers.map((th) => th.text()),
      ).toEqual(['Id', 'Name', 'Users']);
    });

    describe('when a row is expanded', () => {
      beforeEach(async () => {
        createExpandableWrapper();
        await expandFirstRow();
      });

      it('renders its children under it, aligned with its columns', () => {
        expect(findRowTexts()).toEqual([
          ['Platform', '5'],
          ['web', '1'],
          ['api', '4'],
          ['Mobile', '2'],
        ]);
      });

      it('indents the children', () => {
        expect(findToggles().at(1).props()).toMatchObject({ depth: 1, expandable: false });
      });

      it('tells screen readers which row a child is under', () => {
        expect(findRows().wrappers.map(screenReaderText)).toEqual([
          null,
          'Under Platform',
          'Under Platform',
          null,
        ]);
      });

      it('centers the cells, so the text beside a toggle lines up with the rest', () => {
        const cells = findRows().wrappers.flatMap((row) => row.findAll('td').wrappers);

        expect(cells.every((td) => td.classes('!gl-align-middle'))).toBe(true);
      });

      it('points the toggle at the rows it shows', () => {
        const ids = findRows()
          .wrappers.slice(1, 3)
          .map((row) => row.attributes('id'));

        expect(ids.every(Boolean)).toBe(true);
        expect(findToggles().at(0).props()).toMatchObject({
          expanded: true,
          childRowIds: ids,
        });
      });

      it('hides the children again on collapse', async () => {
        await expandFirstRow();

        expect(findRows()).toHaveLength(2);
      });

      it('keeps the row expanded when the same rows come back, as after a refetch', async () => {
        await wrapper.setProps({ data: { nodes: [...treeNodes].reverse() } });

        expect(findRows()).toHaveLength(4);
      });

      it('collapses a row that is no longer in the data', async () => {
        await wrapper.setProps({ data: { nodes: [treeNodes[1]] } });
        await wrapper.setProps({ data: { nodes: treeNodes } });

        expect(findRows()).toHaveLength(2);
      });
    });

    describe('when sorting', () => {
      const sortableFields = [
        { key: 'name', label: 'Name', sortable: true },
        { key: 'users', label: 'Users', sortable: true },
      ];

      beforeEach(async () => {
        createExpandableWrapper({ fields: sortableFields });
        await expandFirstRow();
      });

      it('sorts the tree itself, rather than letting the table sort the flat rows', () => {
        expect(findSortableTable().vm.$attrs['no-local-sorting']).toBe(true);
      });

      it('sorts each level without moving children out from under their parent', async () => {
        findSortableTable().vm.$emit('sort-changed', { sortBy: 'users', sortDesc: true });
        await nextTick();

        expect(findRowTexts().map(([name]) => name)).toEqual(['Platform', 'api', 'web', 'Mobile']);
      });

      it('keeps a row expanded through a sort', async () => {
        findSortableTable().vm.$emit('sort-changed', { sortBy: 'name', sortDesc: false });
        await nextTick();

        expect(findRowTexts().map(([name]) => name)).toEqual(['Mobile', 'Platform', 'api', 'web']);
      });
    });

    it('collapses every row on a page change', async () => {
      createWrapper(mount, {
        data: { nodes: treeNodes, pageInfo: { hasNextPage: true } },
        options: { expandableRows: true, fields },
      });
      await expandFirstRow();

      findPagination().vm.$emit('next');
      await nextTick();

      expect(findRows()).toHaveLength(2);
    });

    it('keys a child listed under two parents apart', async () => {
      const shared = { id: 'project-1', name: 'shared', users: 1 };
      createWrapper(mount, {
        data: {
          nodes: [
            { id: 'alice', name: 'Alice', users: 1, children: [shared] },
            { id: 'bob', name: 'Bob', users: 1, children: [shared] },
          ],
        },
        options: { expandableRows: true, fields },
      });
      await expandFirstRow();
      findToggles().at(2).vm.$emit('toggle');
      await nextTick();

      const ids = [1, 3].map((index) => findRows().at(index).attributes('id'));
      expect(ids[0]).not.toBe(ids[1]);
    });

    describe('when the first column holds objects', () => {
      const userNodes = [
        { id: 'u1', user: { name: 'Zhang Wei', username: 'zwei' }, users: 1 },
        {
          id: 'u2',
          user: { name: 'Sidney Jones', username: 'sjones' },
          users: 2,
          children: [{ id: 'p1', user: { name: 'web' }, users: 2 }],
        },
      ];

      beforeEach(() => {
        createWrapper(mount, {
          data: { nodes: userNodes },
          options: {
            expandableRows: true,
            fields: [
              { key: 'user', label: 'User', sortable: true },
              { key: 'users', label: 'Users' },
            ],
          },
        });
      });

      it('names the toggle after the object', () => {
        expect(findToggles().at(1).props('label')).toBe('Sidney Jones');
      });

      it('sorts by the object as the table would', async () => {
        findSortableTable().vm.$emit('sort-changed', { sortBy: 'user', sortDesc: false });
        await nextTick();

        expect(findToggles().wrappers.map((toggle) => toggle.props('label'))).toEqual([
          'Sidney Jones',
          'Zhang Wei',
        ]);
      });
    });

    it('still asks for a refetch on sort when refetchOnSort is enabled', () => {
      createExpandableWrapper({
        fields: [{ key: 'name', label: 'Name', sortable: true }],
        refetchOnSort: true,
      });

      findSortableTable().vm.$emit('sort-changed', { sortBy: 'name', sortDesc: true });

      expect(wrapper.emitted('update-query')).toEqual([
        [{ sortBy: 'name', sortDesc: true, pagination: undefined }],
      ]);
    });

    describe('when sorting with refetchOnSort', () => {
      const sortRefetchAndReverse = async (rows) => {
        findSortableTable().vm.$emit('sort-changed', { sortBy: 'name', sortDesc: true });
        await wrapper.setProps({ data: { nodes: [...rows].reverse() } });
      };

      const createRefetchWrapper = (rows) =>
        createWrapper(mount, {
          data: { nodes: rows },
          options: {
            expandableRows: true,
            refetchOnSort: true,
            fields: [{ key: 'name', label: 'Name', sortable: true }, fields[1]],
          },
        });

      it('keeps a row with an id expanded', async () => {
        createRefetchWrapper(treeNodes);
        await expandFirstRow();

        await sortRefetchAndReverse(treeNodes);

        expect(findRows()).toHaveLength(4);
      });

      it('collapses a row without an id instead of expanding the row that takes its place', async () => {
        const idlessNodes = [
          { name: 'Platform', users: 5, children: [{ name: 'web', users: 5 }] },
          { name: 'Mobile', users: 2, children: [{ name: 'ios', users: 2 }] },
        ];
        createRefetchWrapper(idlessNodes);
        await expandFirstRow();

        await sortRefetchAndReverse(idlessNodes);

        expect(findRowTexts()).toEqual([
          ['Platform', '5'],
          ['Mobile', '2'],
        ]);
      });
    });
  });
});
