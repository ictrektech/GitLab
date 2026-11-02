import {
  GlCollapsibleListbox,
  GlDisclosureDropdown,
  GlLoadingIcon,
  GlSearchBoxByType,
} from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GroupsTableToolbar from 'ee/orbit/shared/groups/groups_table_toolbar.vue';
import { GROUP_FILTER_OPTIONS } from 'ee/orbit/shared/groups/constants';

describe('GroupsTableToolbar', () => {
  let wrapper;

  const actionItems = [{ value: 'turnOn', text: 'Turn on GitLab Orbit' }];

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(GroupsTableToolbar, {
      propsData: {
        search: '',
        filter: 'all',
        filterOptions: GROUP_FILTER_OPTIONS,
        selectable: true,
        selectedCount: 0,
        actionItems: [],
        ...props,
      },
    });
  };

  const findSearch = () => wrapper.findComponent(GlSearchBoxByType);
  const findFilter = () => wrapper.findComponent(GlCollapsibleListbox);
  const findActions = () => wrapper.findComponent(GlDisclosureDropdown);

  describe('with no selection', () => {
    beforeEach(() => createComponent());

    it('shows the filter with the current state and disables the Actions menu', () => {
      expect(findFilter().props('toggleText')).toBe('GitLab Orbit state: All');
      expect(findActions().props('disabled')).toBe(true);
    });

    it('emits search and filter', () => {
      findSearch().vm.$emit('input', 'ac');
      findFilter().vm.$emit('select', 'on');

      expect(wrapper.emitted()).toMatchObject({ search: [['ac']], filter: [['on']] });
    });
  });

  describe('with selected groups and an action', () => {
    beforeEach(() => createComponent({ selectedCount: 2, actionItems }));

    it('shows the selected count', () => {
      expect(wrapper.text()).toContain('2 groups selected');
    });

    it('emits the chosen action', () => {
      findActions().vm.$emit('action', actionItems[0]);

      expect(wrapper.emitted('action')).toEqual([['turnOn']]);
    });
  });

  describe('while a bulk action runs', () => {
    beforeEach(() =>
      createComponent({
        selectedCount: 2,
        actionItems,
        bulkProgress: { action: 'turnOn', done: 1, total: 2, pendingPaths: ['beta'] },
      }),
    );

    it('shows the progress with a spinner instead of the selected count', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
      expect(wrapper.text()).toContain('1 of 2 done');
      expect(wrapper.text()).not.toContain('groups selected');
    });

    it('disables the search, the filter, and the Actions menu', () => {
      expect(findSearch().props('disabled')).toBe(true);
      expect(findFilter().props('disabled')).toBe(true);
      expect(findActions().props('disabled')).toBe(true);
    });
  });

  describe('when the groups cannot be selected', () => {
    beforeEach(() => createComponent({ selectable: false }));

    it('shows the search and the filter, with no Actions menu', () => {
      expect(findSearch().exists()).toBe(true);
      expect(findFilter().exists()).toBe(true);
      expect(findActions().exists()).toBe(false);
    });
  });
});
