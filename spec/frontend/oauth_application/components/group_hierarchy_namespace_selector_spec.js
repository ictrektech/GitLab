import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import GranularNamespaceSelector from '~/vue_shared/access_tokens/components/granular_namespace_selector.vue';
import GroupHierarchyNamespaceSelector from '~/oauth_application/components/group_hierarchy_namespace_selector.vue';
import groupHierarchySearchQuery from '~/oauth_application/graphql/group_hierarchy_search.query.graphql';
import { DEBOUNCE_DELAY } from '~/vue_shared/components/filtered_search_bar/constants';

Vue.use(VueApollo);

jest.mock('~/alert');

describe('GroupHierarchyNamespaceSelector', () => {
  let wrapper;

  const rootGroup = {
    id: 'gid://gitlab/Group/1',
    name: 'Acme',
    fullPath: 'acme',
    __typename: 'Group',
  };
  const subgroup = {
    id: 'gid://gitlab/Group/2',
    name: 'Widgets',
    fullPath: 'acme/widgets',
    __typename: 'Group',
  };
  const project = {
    id: 'gid://gitlab/Project/3',
    name: 'Site',
    fullPath: 'acme/widgets/site',
    __typename: 'Project',
  };

  const mockResponse = {
    data: {
      group: {
        ...rootGroup,
        descendantGroups: { nodes: [subgroup], __typename: 'GroupConnection' },
        projects: { nodes: [project], __typename: 'ProjectConnection' },
      },
    },
  };

  const mockQueryHandler = jest.fn().mockResolvedValue(mockResponse);

  const createComponent = ({ queryHandler = mockQueryHandler, props = {} } = {}) => {
    wrapper = shallowMountExtended(GroupHierarchyNamespaceSelector, {
      apolloProvider: createMockApollo([[groupHierarchySearchQuery, queryHandler]]),
      propsData: {
        groupFullPath: 'acme',
        groupName: 'Acme',
        ...props,
      },
    });
  };

  const findSelector = () => wrapper.findComponent(GranularNamespaceSelector);
  const search = (term) => findSelector().vm.$emit('search', term);

  const waitForQuery = async () => {
    jest.advanceTimersByTime(DEBOUNCE_DELAY);
    await waitForPromises();
  };

  beforeEach(() => {
    createComponent();
  });

  describe('rendering', () => {
    it('titles the namespace list after the group', () => {
      expect(findSelector().props('title')).toBe('Groups and projects in Acme');
    });

    it('does not offer a search hint', () => {
      expect(findSelector().props('searchHint')).toBe('');
    });

    it('passes no error by default', () => {
      expect(findSelector().props('error')).toBe('');
    });

    describe('with an error', () => {
      beforeEach(() => {
        createComponent({ props: { error: 'At least one group or project is required.' } });
      });

      it('passes it through to the namespace list', () => {
        expect(findSelector().props('error')).toBe('At least one group or project is required.');
      });
    });

    describe('with a value', () => {
      beforeEach(() => {
        createComponent({ props: { value: [subgroup] } });
      });

      it('passes it through to the namespace list', () => {
        expect(findSelector().props('value')).toEqual([subgroup]);
      });
    });
  });

  describe('GraphQL query', () => {
    it('searches the group hierarchy on mount', async () => {
      await waitForQuery();

      expect(mockQueryHandler).toHaveBeenCalledWith({ fullPath: 'acme', search: '' });
    });

    it('searches again when the term changes', async () => {
      await search('widg');
      await waitForQuery();

      expect(mockQueryHandler).toHaveBeenCalledWith({ fullPath: 'acme', search: 'widg' });
    });

    it('skips the query when the term is too short', async () => {
      await search('w');
      await waitForQuery();

      expect(mockQueryHandler).not.toHaveBeenCalledWith({ fullPath: 'acme', search: 'w' });
    });
  });

  describe('groups and projects', () => {
    it('offers the group itself before its descendant groups, and its projects', async () => {
      await waitForQuery();

      expect(findSelector().props('groups')).toEqual([rootGroup, subgroup]);
      expect(findSelector().props('projects')).toEqual([project]);
    });

    describe('when the search term does not match the group itself', () => {
      beforeEach(async () => {
        await search('widgets');
        await waitForQuery();
      });

      it('offers only the descendants', () => {
        expect(findSelector().props('groups')).toEqual([subgroup]);
      });
    });

    describe('when the search term matches the group itself', () => {
      beforeEach(async () => {
        await search('ACME');
        await waitForQuery();
      });

      it('keeps the group first', () => {
        expect(findSelector().props('groups')).toEqual([rootGroup, subgroup]);
      });
    });

    describe('when the group is not found', () => {
      beforeEach(async () => {
        createComponent({ queryHandler: jest.fn().mockResolvedValue({ data: { group: null } }) });
        await waitForQuery();
      });

      it('offers nothing', () => {
        expect(findSelector().props('groups')).toEqual([]);
        expect(findSelector().props('projects')).toEqual([]);
      });
    });
  });

  describe('events', () => {
    it('re-emits `input` from the namespace list', () => {
      findSelector().vm.$emit('input', [project]);

      expect(wrapper.emitted('input')).toEqual([[[project]]]);
    });
  });

  describe('error handling', () => {
    it('shows an alert when the query fails', async () => {
      const error = new Error('GraphQL error');

      createComponent({ queryHandler: jest.fn().mockRejectedValue(error) });
      await waitForQuery();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Error loading groups and projects. Please refresh page.',
        captureError: true,
        error,
      });
    });
  });
});
