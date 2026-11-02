import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GroupsTableEmptyState from 'ee/orbit/shared/groups/groups_table_empty_state.vue';

describe('GroupsTableEmptyState', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(GroupsTableEmptyState, {
      propsData: { noGroups: false, search: '', serverSearch: true, filter: 'all', ...props },
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const findSearchHint = () => wrapper.findByTestId('groups-empty-search-hint');

  describe('when the user has no top-level groups', () => {
    describe('and a new group path', () => {
      beforeEach(() => createComponent({ noGroups: true, newGroupPath: '/groups/new' }));

      it('offers to create a group', () => {
        expect(wrapper.text()).toContain(
          'GitLab Orbit indexes top-level groups. Create a group to start.',
        );
        expect(findButton().attributes('href')).toBe('/groups/new');
      });
    });

    describe('and no new group path', () => {
      beforeEach(() => createComponent({ noGroups: true }));

      it('says which groups show here, with no button', () => {
        expect(wrapper.text()).toContain('No groups yet');
        expect(wrapper.text()).toContain(
          'The groups where you have at least the Reporter role show here.',
        );
        expect(findButton().exists()).toBe(false);
      });
    });
  });

  describe('when a server search of 3 or more characters finds no group', () => {
    beforeEach(() => createComponent({ search: 'zzz' }));

    it('names the search and asks to check the spelling', () => {
      expect(wrapper.text()).toContain('No groups match “zzz”');
      expect(findSearchHint().text()).toBe('Edit your search and try again.');
    });

    it('emits clear-search from Clear search', () => {
      findButton().vm.$emit('click');

      expect(wrapper.emitted('clear-search')).toEqual([[]]);
    });
  });

  describe('when a server search of fewer than 3 characters finds no group', () => {
    beforeEach(() => createComponent({ search: 'e2' }));

    it('says that a search finds part of a name from 3 characters', () => {
      expect(findSearchHint().text()).toBe(
        'To find part of a group name, enter at least 3 characters.',
      );
    });
  });

  describe('when a browser search of fewer than 3 characters finds no group', () => {
    beforeEach(() => createComponent({ search: 'e2', serverSearch: false }));

    it('asks to check the spelling', () => {
      expect(findSearchHint().text()).toBe('Edit your search and try again.');
    });
  });

  describe.each`
    filter        | title
    ${'excluded'} | ${'No groups are excluded'}
    ${'on'}       | ${'No groups have GitLab Orbit on'}
  `('when the $filter filter has no group', ({ filter, title }) => {
    beforeEach(() => createComponent({ filter }));

    it('shows the title for the filter, with no search hint', () => {
      expect(wrapper.text()).toContain(title);
      expect(findSearchHint().exists()).toBe(false);
    });
  });
});
