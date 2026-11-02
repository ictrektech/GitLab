import { InMemoryCache } from '@apollo/client/core';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import adminExcludedGroupsQuery from 'ee/orbit/settings/admin/graphql/admin_excluded_groups.query.graphql';
import adminGroupsQuery from 'ee/orbit/settings/admin/graphql/admin_groups.query.graphql';
import { EXCLUDED_GROUPS_PAGE_SIZE } from 'ee/orbit/settings/admin/constants';
import { ADMIN_CACHE_CONFIG } from 'ee/orbit/settings/admin/graphql/cache_config';
import { buildGroup, buildOnGroup, excludedGroupsResponse, groupsResponse } from '../mock_data';

describe('ADMIN_CACHE_CONFIG OrbitNamespace', () => {
  describe('when the orbitUpdate payload writes the group', () => {
    it('updates `enabled` and keeps the other Orbit fields of the group', () => {
      const cache = new InMemoryCache(ADMIN_CACHE_CONFIG);
      const group = buildOnGroup('acme');
      cache.writeQuery({ query: adminGroupsQuery, data: groupsResponse([group]).data });

      cache.writeQuery({
        query: orbitUpdateMutation,
        variables: { input: { groupPath: 'acme', enabled: false } },
        data: {
          orbitUpdate: {
            __typename: 'OrbitUpdatePayload',
            group: {
              __typename: 'Group',
              id: group.id,
              name: group.name,
              fullPath: group.fullPath,
              orbit: { __typename: 'OrbitNamespace', enabled: false },
            },
            errors: [],
          },
        },
      });

      const { orbit } = cache.readQuery({ query: adminGroupsQuery }).orbit.groups.nodes[0];
      expect(orbit).toEqual({ ...group.orbit, enabled: false });
    });
  });
});

describe('ADMIN_CACHE_CONFIG Orbit', () => {
  describe('when the exclusion query loads after the group query', () => {
    it('keeps the loaded groups', () => {
      const cache = new InMemoryCache(ADMIN_CACHE_CONFIG);
      const group = buildOnGroup('acme');
      cache.writeQuery({ query: adminGroupsQuery, data: groupsResponse([group]).data });

      cache.writeQuery({
        query: adminExcludedGroupsQuery,
        variables: { first: EXCLUDED_GROUPS_PAGE_SIZE },
        data: excludedGroupsResponse([buildGroup({ name: 'beta' })]).data,
      });

      expect(cache.readQuery({ query: adminGroupsQuery }).orbit.groups.nodes).toEqual([group]);
    });
  });
});

describe('ADMIN_CACHE_CONFIG Orbit.excludedGroups', () => {
  const { merge } = ADMIN_CACHE_CONFIG.typePolicies.Orbit.fields.excludedGroups;
  const page = (ids) => ({ nodes: ids.map((id) => ({ __ref: `Group:${id}` })) });

  describe('when a page with a cursor loads', () => {
    it('appends the page to the loaded pages', () => {
      expect(merge(page([1]), page([2]), { args: { after: 'c1' } })).toEqual(page([1, 2]));
    });
  });

  describe('when a refetch loads the first page', () => {
    it('replaces the loaded pages', () => {
      expect(merge(page([1, 2]), page([3]), { args: {} })).toEqual(page([3]));
    });
  });

  describe('when a later page returns no data', () => {
    it('keeps the loaded pages', () => {
      expect(merge(page([1]), null, { args: { after: 'c1' } })).toEqual(page([1]));
    });
  });

  describe('when the cache is empty', () => {
    it('uses the incoming page', () => {
      expect(merge(undefined, page([1]), { args: { after: 'c1' } })).toEqual(page([1]));
    });
  });
});
