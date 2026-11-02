import { GlTable, GlSkeletonLoader } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { trimText } from 'helpers/text_helper';
import BaseFeatureSettingsTable from 'ee/ai/shared/feature_settings/base_feature_settings_table.vue';
import { featureSettings } from './mock_data';

const MOCK_FIELDS = [
  {
    key: 'title',
    label: 'Features',
    loaderWidths: ['200', '80', '150'],
    sortable: true,
  },
  {
    key: 'model',
    label: 'Models',
    sortable: true,
  },
];

describe('BaseFeatureSettingsTable', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = mountExtended(BaseFeatureSettingsTable, {
      propsData: {
        items: featureSettings,
        isLoading: false,
        fields: MOCK_FIELDS,
        ...props,
      },
      scopedSlots: {
        'head(title)': '<div>Sub feature</div>',
        'head(model)': '<div>Model name</div>',
        'cell(title)': '<div>Sub feature content {{ props.item.title }}</div>',
        'cell(model)': '<div>Model name content {{ props.item.model }}</div>',
      },
    });
  };

  const findTable = () => wrapper.findComponent(GlTable);
  const findTableRowCells = (idx) => findTable().find('tbody').findAll('tr').at(idx).findAll('td');
  const findTableHeaderCells = (idx) =>
    findTable().find('thead').findAll('tr').at(idx).findAll('th');

  it('renders table component', () => {
    createComponent();

    expect(findTable().exists()).toBe(true);
  });

  describe('when loading', () => {
    beforeEach(() => {
      createComponent({ isLoading: true });
    });

    it('renders loader when `loaderWidths` is provided for that field', () => {
      const withLoader = findTableRowCells(0).at(0);
      expect(withLoader.findComponent(GlSkeletonLoader).exists()).toBe(true);
    });

    it('does not render loader if no `loaderWidths` provided for that field', () => {
      const withoutLoader = findTableRowCells(0).at(1);
      expect(withoutLoader.findComponent(GlSkeletonLoader).exists()).toBe(false);
    });

    it('does not render loaders in header', () => {
      const headers = findTableHeaderCells(0);
      headers.wrappers.forEach((header) =>
        expect(header.findComponent(GlSkeletonLoader).exists()).toBe(false),
      );
    });

    it('does not render content', () => {
      const rowCells = findTableRowCells(0);
      expect(rowCells.at(0).text()).not.toContain('Sub feature content');
      expect(rowCells.at(1).text()).not.toContain('Model name content');
    });

    it('does not render sort arrows in the column header', () => {
      expect(wrapper.findAllByTestId('sort-icon')).toHaveLength(0);
    });

    it('does not sort when the user clicks a column header', async () => {
      await findTableHeaderCells(0).at(0).trigger('click');

      expect(findTable().emitted('sort-changed')).toBeUndefined();
    });
  });

  describe('when not loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('does not render loaders', () => {
      const rowCells = findTableRowCells(0);
      rowCells.wrappers.forEach((cell) =>
        expect(cell.findComponent(GlSkeletonLoader).exists()).toBe(false),
      );
    });

    it('renders content', () => {
      const rowCells = findTableRowCells(0);
      expect(rowCells.at(0).text()).toContain('Sub feature content');
      expect(rowCells.at(1).text()).toContain('Model name content');
    });

    it('renders sort arrows in the header of each sortable column', () => {
      expect(wrapper.findAllByTestId('sort-icon')).toHaveLength(MOCK_FIELDS.length);
    });
  });

  describe('sorting', () => {
    // Unsorted, ascending and descending orders all differ.
    const sortableItems = [
      { feature: 'b_feature', title: 'B feature', model: 'Mistral' },
      { feature: 'a_feature', title: 'A feature', model: 'Zephyr' },
      { feature: 'c_feature', title: 'C feature', model: 'Aardvark' },
    ];

    const findRows = () => findTable().find('tbody').findAll('tr');
    const findTableItems = () =>
      findTable()
        .props('items')
        .map(({ title, model }) => ({ title, model }));

    const clickFeatureHeader = () => findTableHeaderCells(0).at(0).trigger('click');
    const clickModelHeader = () => findTableHeaderCells(0).at(1).trigger('click');

    beforeEach(() => {
      createComponent({ items: sortableItems });
    });

    it('renders rows in the original order before sorting', () => {
      expect(findTableItems()).toEqual([
        { title: 'B feature', model: 'Mistral' },
        { title: 'A feature', model: 'Zephyr' },
        { title: 'C feature', model: 'Aardvark' },
      ]);
    });

    it('sorts rows by model when the user clicks the Model column header', async () => {
      await clickModelHeader();

      expect(findTableItems()).toEqual([
        { title: 'C feature', model: 'Aardvark' },
        { title: 'B feature', model: 'Mistral' },
        { title: 'A feature', model: 'Zephyr' },
      ]);
    });

    it('sorts in descending order when the user clicks the same header again', async () => {
      await clickModelHeader();
      await clickModelHeader();

      expect(findTableItems()).toEqual([
        { title: 'A feature', model: 'Zephyr' },
        { title: 'B feature', model: 'Mistral' },
        { title: 'C feature', model: 'Aardvark' },
      ]);
    });

    it('sorts rows by feature when the user clicks the Feature column header', async () => {
      await clickFeatureHeader();

      expect(findTableItems()).toEqual([
        { title: 'A feature', model: 'Zephyr' },
        { title: 'B feature', model: 'Mistral' },
        { title: 'C feature', model: 'Aardvark' },
      ]);
    });

    describe('when rows share the same value', () => {
      beforeEach(() => {
        createComponent({
          items: [
            { feature: 'a_feature', title: 'A feature', model: 'Mistral' },
            { feature: 'b_feature', title: 'B feature', model: 'Mistral' },
            { feature: 'c_feature', title: 'C feature', model: 'Aardvark' },
          ],
        });
      });

      it('keeps their relative order when sorting in descending order', async () => {
        await clickModelHeader();
        await clickModelHeader();

        expect(findTableItems()).toEqual([
          { title: 'A feature', model: 'Mistral' },
          { title: 'B feature', model: 'Mistral' },
          { title: 'C feature', model: 'Aardvark' },
        ]);
      });
    });

    it('keeps the sorted row order when a cell value is edited in place', async () => {
      await clickModelHeader();

      const editedItems = sortableItems.map((item) =>
        item.feature === 'b_feature' ? { ...item, model: 'Zzz' } : { ...item },
      );
      await wrapper.setProps({ items: editedItems });

      expect(findTableItems()).toEqual([
        { title: 'C feature', model: 'Aardvark' },
        { title: 'B feature', model: 'Zzz' },
        { title: 'A feature', model: 'Zephyr' },
      ]);
    });

    // Compare markup, not node identity: under Vue 3 compat, GlTable does not
    // reuse row elements when rows reorder.
    it('keeps each row element with its feature when sorting', async () => {
      const zephyrRow = findRows().at(1).element;

      await clickModelHeader();

      expect(findRows().at(2).element.innerHTML).toBe(zephyrRow.innerHTML);
    });
  });

  describe('when both Code Review depths are listed', () => {
    const depthItems = [
      { feature: 'review_merge_request_dap_deep', title: 'Deep Code Review', model: 'Claude' },
      { feature: 'duo_agent_platform', title: 'Agents & flows', model: 'Claude' },
      { feature: 'review_merge_request_dap', title: 'Agentic Code Review', model: 'Claude' },
    ];

    const findBodyRows = () => findTable().find('tbody').findAll('tr');
    const findFeatureCellText = (idx) =>
      trimText(findBodyRows().at(idx).findAll('td').at(0).text());

    beforeEach(() => {
      createComponent({ items: depthItems });
    });

    it('renders a header row with the feature title and no model cell content', () => {
      const headerCells = findBodyRows().at(0).findAll('td');

      expect(headerCells.at(0).text()).toBe('Sub feature content Agentic Code Review');
      expect(headerCells.at(1).text()).toBe('');
    });

    it('renders a row per depth with its label and description, Standard first', () => {
      expect(findFeatureCellText(1)).toBe('Standard · Efficient review, limited context');
      expect(findFeatureCellText(2)).toBe('Deep · Extensive analysis, more context');
    });

    it('renders the model cell for each depth row', () => {
      expect(findBodyRows().at(1).findAll('td').at(1).text()).toBe('Model name content Claude');
      expect(findBodyRows().at(2).findAll('td').at(1).text()).toBe('Model name content Claude');
    });

    it('keeps the depth rows together after sorting', async () => {
      await findTableHeaderCells(0).at(0).trigger('click');

      expect([0, 1, 2, 3].map(findFeatureCellText)).toEqual([
        'Sub feature content Agentic Code Review',
        'Standard · Efficient review, limited context',
        'Deep · Extensive analysis, more context',
        'Sub feature content Agents & flows',
      ]);
    });
  });
});
