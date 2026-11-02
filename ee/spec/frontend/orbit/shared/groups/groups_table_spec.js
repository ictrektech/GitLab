import {
  GlAlert,
  GlCollapsibleListbox,
  GlDisclosureDropdown,
  GlKeysetPagination,
  GlLoadingIcon,
  GlPopover,
  GlSearchBoxByType,
} from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import GroupsTable from 'ee/orbit/shared/groups/groups_table.vue';
import { GROUP_FILTER_OPTIONS } from 'ee/orbit/shared/groups/constants';
import { ENABLED_AT, buildRow } from './mock_data';

describe('GroupsTable', () => {
  let wrapper;

  const defaultProps = {
    title: 'Top-level groups',
    description: 'Select groups to turn Orbit on or off.',
    filterOptions: GROUP_FILTER_OPTIONS,
    groups: [
      buildRow({ name: 'acme', isOn: true, indexingState: 'INDEXING', enabledAt: ENABLED_AT }),
      buildRow({ name: 'beta', isExcluded: true }),
    ],
    selectedPaths: [],
    actionItems: [],
    search: '',
    serverSearch: true,
    filter: 'all',
    pageInfo: { hasNextPage: true, hasPreviousPage: false, startCursor: 'a', endCursor: 'b' },
    isLoading: false,
    loadError: null,
    bulkProgress: null,
    newGroupPath: '/groups/new',
  };

  const createComponent = (props = {}, scopedSlots = {}) => {
    wrapper = mountExtended(GroupsTable, {
      propsData: { ...defaultProps, ...props },
      scopedSlots,
    });
  };

  const findRows = () => wrapper.findAll('tbody tr');
  const findRowText = (index) => findRows().at(index).text().replace(/\s+/g, ' ');
  const findRowCheckbox = (name) => wrapper.find(`tbody input[aria-label="Select ${name}"]`);
  const findSelectAll = () => wrapper.find('thead input[type="checkbox"]');
  const findActions = () => wrapper.findComponent(GlDisclosureDropdown);
  const findSearch = () => wrapper.findComponent(GlSearchBoxByType);
  const findFilter = () => wrapper.findComponent(GlCollapsibleListbox);
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findEmpty = () => wrapper.findByTestId('groups-empty');
  const findLoadError = () => wrapper.findComponent(GlAlert);
  const findNote = () => wrapper.findByTestId('group-note');
  const findAreasToggle = () => wrapper.findByTestId('group-areas-toggle');
  const findAreas = () => wrapper.findComponent(GlPopover);

  describe('with groups', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the title and description', () => {
      expect(wrapper.find('h2').text()).toBe('Top-level groups');
      expect(wrapper.text()).toContain('Select groups to turn Orbit on or off.');
    });

    it('shows the Orbit state and index status of each group', () => {
      expect(findRowText(0)).toContain('acme On Indexing · Turned on');
      expect(findRowText(1)).toContain('beta Off Excluded Not indexed');
    });

    it('shows a spinner next to the group that Orbit is indexing', () => {
      expect(findRows().at(0).findComponent(GlLoadingIcon).exists()).toBe(true);
      expect(findRows().at(1).findComponent(GlLoadingIcon).exists()).toBe(false);
    });

    it('shows the filter with the current state', () => {
      expect(findFilter().props('toggleText')).toBe('GitLab Orbit state: All');
    });

    it('disables the Actions menu', () => {
      expect(findActions().props('disabled')).toBe(true);
    });

    it('emits select with the path of a checked group', async () => {
      await findRowCheckbox('beta').setChecked(true);

      expect(wrapper.emitted('select')).toEqual([[['beta']]]);
    });

    it('emits select with every path from the header checkbox', async () => {
      await findSelectAll().setChecked(true);

      expect(wrapper.emitted('select')).toEqual([[['acme', 'beta']]]);
    });

    it('emits next with the end cursor', () => {
      findPagination().vm.$emit('next', 'b');

      expect(wrapper.emitted('next')).toEqual([['b']]);
    });

    it('emits search with the new text', () => {
      findSearch().vm.$emit('input', 'ac');

      expect(wrapper.emitted('search')).toEqual([['ac']]);
    });
  });

  describe('with a selection and action items', () => {
    beforeEach(() => {
      createComponent({
        selectedPaths: ['beta'],
        actionItems: [{ value: 'turnOn', text: 'Turn on GitLab Orbit' }],
      });
    });

    it('shows the selected count', () => {
      expect(wrapper.text()).toContain('1 group selected');
    });

    it('emits action with the chosen action', () => {
      findActions().vm.$emit('action', { value: 'turnOn', text: 'Turn on GitLab Orbit' });

      expect(wrapper.emitted('action')).toEqual([['turnOn']]);
    });
  });

  describe('while a bulk action runs', () => {
    beforeEach(() => {
      createComponent({
        selectedPaths: ['acme', 'beta'],
        actionItems: [{ value: 'exclude', text: 'Exclude from automatic indexing' }],
        bulkProgress: { action: 'exclude', done: 1, total: 2, pendingPaths: ['beta'] },
      });
    });

    it('shows the progress', () => {
      expect(wrapper.text()).toContain('Excluding groups: 1 of 2 done');
    });

    it('shows the pending row as updating', () => {
      expect(findRowText(1)).toContain('Updating…');
    });

    it('disables the Actions menu, search, and row checkboxes', () => {
      expect(findActions().props('disabled')).toBe(true);
      expect(findSearch().props('disabled')).toBe(true);
      expect(findRowCheckbox('acme').attributes('disabled')).toBeDefined();
    });
  });

  describe('with groups that share a name', () => {
    beforeEach(() => {
      createComponent({
        groups: [
          buildRow({ name: 'acme' }),
          { ...buildRow({ name: 'acme' }), id: 'gid://gitlab/Group/2', fullPath: 'acme-2' },
        ],
      });
    });

    it('shows the path of the group whose path differs from its name', () => {
      expect(findRowText(0)).not.toContain('acme-2');
      expect(findRowText(1)).toContain('acme acme-2');
      expect(findRowCheckbox('acme-2').exists()).toBe(true);
    });
  });

  describe('with a failed group', () => {
    beforeEach(() => {
      createComponent({
        groups: [
          buildRow({
            name: 'acme',
            failure: { kind: 'rejected', message: 'Not allowed' },
            note: 'Not allowed',
          }),
        ],
      });
    });

    it('shows the failed badge and the note in the info button', () => {
      expect(findRowText(0)).toContain('Off Update failed');
      expect(findNote().attributes('aria-label')).toBe('Not allowed');
    });
  });

  describe('with a group that has a trial badge', () => {
    beforeEach(() => {
      createComponent({
        groups: [
          buildRow({
            name: 'acme',
            isOn: true,
            indexingState: 'READY',
            trialBadge: { text: 'Trial active', variant: 'info', icon: null },
          }),
        ],
      });
    });

    it('shows the badge after the Orbit state', () => {
      expect(findRowText(0)).toContain('On Trial');
    });
  });

  describe('with the areas of a group that Orbit is indexing', () => {
    beforeEach(() => {
      createComponent({
        groups: [
          buildRow({
            name: 'acme',
            isOn: true,
            indexingState: 'INDEXING',
            indexingAreas: [
              { name: 'security', state: 'NOT_STARTED' },
              { name: 'core', state: 'READY' },
              { name: 'ci', state: 'INDEXING' },
            ],
          }),
        ],
      });
    });

    it('shows a button that names the group', () => {
      expect(findAreasToggle().attributes('aria-label')).toBe('Index status by area for acme');
    });

    it('lists the state of each area in the Overview order', () => {
      expect(findAreas().props('target')).toBe(findAreasToggle().attributes('id'));
      expect(findAreas().text()).toMatchInterpolatedText(
        'Core Indexed CI/CD Indexing Security Queued to start',
      );
    });
  });

  describe('with the areas of a group that is indexed', () => {
    beforeEach(() => {
      createComponent({
        groups: [
          buildRow({
            name: 'acme',
            isOn: true,
            indexingState: 'READY',
            indexingAreas: [{ name: 'core', state: 'READY' }],
          }),
        ],
      });
    });

    it('does not show the areas', () => {
      expect(findAreasToggle().exists()).toBe(false);
    });
  });

  describe('when the groups cannot be selected', () => {
    beforeEach(() => {
      createComponent({ selectable: false });
    });

    it('hides the checkboxes and the Actions menu', () => {
      expect(findSelectAll().exists()).toBe(false);
      expect(findRowCheckbox('acme').exists()).toBe(false);
      expect(findActions().exists()).toBe(false);
    });
  });

  describe('with a group that cannot be selected', () => {
    beforeEach(() => {
      createComponent({
        groups: [buildRow({ name: 'acme' }), buildRow({ name: 'beta', allowedActions: [] })],
      });
    });

    it('shows no checkbox for that group', () => {
      expect(findRowCheckbox('acme').exists()).toBe(true);
      expect(findRowCheckbox('beta').exists()).toBe(false);
    });

    it('selects only the other groups from the header checkbox', async () => {
      await findSelectAll().setChecked(true);

      expect(wrapper.emitted('select')).toEqual([[['acme']]]);
    });
  });

  describe('with the actions column', () => {
    beforeEach(() => {
      createComponent(
        { actionsColumn: true },
        { actions: '<a href="#" data-testid="row-action">{{ props.group.name }} usage</a>' },
      );
    });

    it('renders the actions slot for each group', () => {
      expect(wrapper.findAllByTestId('row-action')).toHaveLength(2);
      expect(wrapper.findByText('acme usage').exists()).toBe(true);
      expect(wrapper.findByText('beta usage').exists()).toBe(true);
    });

    it('keeps the header cell and labels it for screen readers only', () => {
      const header = wrapper
        .findAll('thead th')
        .filter((th) => th.text() === 'Actions')
        .at(0);

      expect(header.classes()).not.toContain('gl-sr-only');
      expect(header.find('.gl-sr-only').text()).toBe('Actions');
    });
  });

  describe('with no groups', () => {
    describe('and no search', () => {
      beforeEach(() => {
        createComponent({ groups: [], pageInfo: {} });
      });

      it('shows the new group empty state and hides the toolbar', () => {
        expect(findEmpty().text()).toContain('No top-level groups yet');
        expect(findEmpty().find('a').attributes('href')).toBe('/groups/new');
        expect(findSearch().exists()).toBe(false);
      });
    });

    describe('and no new group path', () => {
      beforeEach(() => {
        createComponent({ groups: [], pageInfo: {}, newGroupPath: null });
      });

      it('explains which groups show here, with no button', () => {
        expect(findEmpty().text()).toContain(
          'The groups where you have at least the Reporter role show here.',
        );
        expect(findEmpty().find('a').exists()).toBe(false);
      });
    });

    describe('and a search', () => {
      beforeEach(() => {
        createComponent({ groups: [], pageInfo: {}, search: 'zz&co' });
      });

      it('shows the no match empty state and keeps the toolbar', () => {
        expect(findEmpty().text()).toContain('No groups match “zz&co”');
        expect(findEmpty().text()).toContain('Edit your search and try again.');
        expect(findSearch().exists()).toBe(true);
      });

      it('emits an empty search from Clear search', async () => {
        await findEmpty().find('button').trigger('click');

        expect(wrapper.emitted('search')).toEqual([['']]);
      });
    });

    describe('and a search shorter than 3 characters', () => {
      beforeEach(() => {
        createComponent({ groups: [], pageInfo: {}, search: 'e2' });
      });

      it('says that a search finds part of a name from 3 characters', () => {
        expect(findEmpty().text()).toContain(
          'To find part of a group name, enter at least 3 characters.',
        );
      });
    });

    describe('and the excluded filter', () => {
      beforeEach(() => {
        createComponent({ groups: [], pageInfo: {}, filter: 'excluded' });
      });

      it('shows the no excluded groups empty state', () => {
        expect(findEmpty().text()).toContain('No groups are excluded');
      });
    });
  });

  describe('with a load error', () => {
    beforeEach(() => {
      createComponent({
        groups: [],
        loadError: 'GitLab could not complete the request. Try again.',
      });
    });

    it('shows the error and hides the table', () => {
      expect(findLoadError().text()).toContain('GitLab could not complete the request. Try again.');
      expect(wrapper.findByTestId('groups-table').exists()).toBe(false);
    });

    it('emits retry from Try again', () => {
      findLoadError().vm.$emit('primary-action');

      expect(wrapper.emitted('retry')).toEqual([[]]);
    });
  });
});
