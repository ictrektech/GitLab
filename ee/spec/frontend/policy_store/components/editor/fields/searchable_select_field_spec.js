import { GlCollapsibleListbox } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SearchableSelectField from 'ee/policy_store/components/editor/fields/searchable_select_field.vue';

describe('SearchableSelectField', () => {
  let wrapper;

  const field = {
    key: 'setting',
    label: 'Setting',
    options: [
      { id: 'visibility', label: 'Project visibility' },
      { id: 'mr_approvals', label: 'Merge request approvals' },
      { id: 'protected_branches', label: 'Protected branches' },
    ],
  };

  const createComponent = (props) =>
    mountExtended(SearchableSelectField, { propsData: { field, ...props } });
  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findToggle = () => wrapper.find(`#${findListbox().props('toggleId')}`);
  const itemTexts = () =>
    findListbox()
      .props('items')
      .map(({ text }) => text);

  describe('default rendering', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    it('maps catalog options onto listbox items', () => {
      expect(findListbox().props('items')).toEqual([
        { value: 'visibility', text: 'Project visibility' },
        { value: 'mr_approvals', text: 'Merge request approvals' },
        { value: 'protected_branches', text: 'Protected branches' },
      ]);
    });

    it('renders through FieldWrapper, so the label names the toggle', () => {
      expect(wrapper.find('label').attributes('for')).toBe(findListbox().props('toggleId'));
    });

    it('is searchable, which is the whole point of this control over SelectField', () => {
      expect(findListbox().props('searchable')).toBe(true);
    });

    it('shows the required marker the wrapper renders', () => {
      wrapper = createComponent({ field: { ...field, required: true } });

      expect(wrapper.findByTestId('required-marker').exists()).toBe(true);
    });

    // The binding is left off deliberately, so assert the name the toggle ends up with
    // rather than the prop: this has to survive a change to GlBaseDropdown's fallback
    // as well as anyone filling FieldWrapper's label-actions slot on this field.
    it('names the toggle from the field label', () => {
      const names = findToggle()
        .attributes('aria-labelledby')
        .split(' ')
        .map((id) => wrapper.find(`#${id}`).text());

      expect(names.join(' ')).toContain('Setting');
    });
  });

  describe('filtering', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    // GlCollapsibleListbox only emits the term; narrowing the list is ours to do.
    it('narrows the items to a case-insensitive match on the search term', async () => {
      await findListbox().vm.$emit('search', 'APPROV');

      expect(itemTexts()).toEqual(['Merge request approvals']);
    });

    it('restores the full list when the term is cleared', async () => {
      await findListbox().vm.$emit('search', 'approv');
      await findListbox().vm.$emit('search', '   ');

      expect(itemTexts()).toHaveLength(3);
    });

    it('leaves the list empty when nothing matches, so the no-results text shows', async () => {
      await findListbox().vm.$emit('search', 'nothing here');

      expect(itemTexts()).toEqual([]);
      expect(findListbox().props('noResultsText')).toBe('No matching options');
    });
  });

  describe('selection', () => {
    it('emits the selected option id', () => {
      wrapper = createComponent();

      findListbox().vm.$emit('select', 'visibility');

      expect(wrapper.emitted('input')).toEqual([['visibility']]);
    });

    it('labels the toggle with the selected option', () => {
      wrapper = createComponent({ value: 'mr_approvals' });

      expect(findListbox().props('selected')).toBe('mr_approvals');
      expect(findListbox().props('toggleText')).toBe('Merge request approvals');
      expect(findToggle().classes()).not.toContain('!gl-text-subtle');
    });

    // An empty string would be wrapped into a single-item selection by the listbox,
    // which then styles the toggle as if a value were chosen. '' is both the prop
    // default and what @reset emits, so it is the case this guards.
    it.each([
      ['a cleared value', ''],
      ['a persisted null', null],
    ])('reports no selection and a subtle placeholder for %s', (_, value) => {
      wrapper = createComponent({ value });

      expect(findListbox().props('selected')).toEqual([]);
      expect(findListbox().props('toggleText')).toBe('Select...');
      expect(findToggle().classes()).toContain('!gl-text-subtle');
    });

    it('prefers the placeholder the field declares', () => {
      wrapper = createComponent({ field: { ...field, placeholder: 'Any setting' } });

      expect(findListbox().props('toggleText')).toBe('Any setting');
    });

    // Matches configItemsFor on the detail page, which also shows an unknown id as
    // itself: the placeholder would read as "unset" over a value that is still set.
    it('shows a value the catalog no longer offers as its raw id', () => {
      wrapper = createComponent({ value: 'retired_setting' });

      expect(findListbox().props('toggleText')).toBe('retired_setting');
    });

    it('accepts a numeric option id, since long lists are keyed by record id', () => {
      wrapper = createComponent({
        field: { key: 'project', label: 'Project', options: [{ id: 7, label: 'Flight' }] },
        value: 7,
      });

      expect(findListbox().props('toggleText')).toBe('Flight');
    });
  });

  describe('clearing', () => {
    // SelectField offers a blank option; without a reset the listbox is a one-way door
    // on an optional field. The listbox only draws the button when the label, the header
    // text and a selection are all present, so assert the button, not the label prop.
    const findReset = () => wrapper.findByTestId('listbox-reset-button');

    beforeEach(() => {
      wrapper = createComponent({ value: 'visibility' });
    });

    it('offers a reset control once something is selected', () => {
      expect(findReset().exists()).toBe(true);
    });

    it('emits an empty value when the reset is clicked', async () => {
      await findReset().trigger('click');

      expect(wrapper.emitted('input')).toEqual([['']]);
    });
  });

  describe('a field declaring no options', () => {
    beforeEach(() => {
      wrapper = createComponent({ field: { key: 'setting', label: 'Setting' } });
    });

    it('renders an empty list', () => {
      expect(findListbox().props('items')).toEqual([]);
    });

    // "No matching options" would be wrong copy when nothing was searched for.
    it('says there is nothing to pick rather than nothing matched', () => {
      expect(findListbox().props('noResultsText')).toBe('No options available');
    });
  });
});
