import createApolloProvider from 'ee/policy_store/apollo';
import getPolicyStorePolicies from 'ee/policy_store/graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from 'ee/policy_store/graphql/get_group_policy_store_policies.query.graphql';
import getProjectPolicyStorePolicies from 'ee/policy_store/graphql/get_project_policy_store_policies.query.graphql';
import getPolicyStoreCatalogs from 'ee/policy_store/graphql/get_policy_store_catalogs.query.graphql';
import getGroupPolicyStoreCatalogs from 'ee/policy_store/graphql/get_group_policy_store_catalogs.query.graphql';
import {
  mockGraphqlPolicy,
  mockOrganizationPoliciesResponse,
  mockGroupPoliciesResponse,
  mockProjectPoliciesResponse,
} from './mock_data';

describe('policy store Apollo provider', () => {
  it('builds a provider around its own client on every call', () => {
    const provider = createApolloProvider();

    expect(provider.defaultClient).toBeDefined();
    expect(createApolloProvider().defaultClient).not.toBe(provider.defaultClient);
  });

  // Every page runs several queries that all write the container's policyStore,
  // which has no id of its own. The provider's cache has to merge those writes
  // instead of letting the last one replace the rest.
  describe.each`
    container         | policiesQuery                  | catalogsQuery                  | variables                                               | policiesData
    ${'organization'} | ${getPolicyStorePolicies}      | ${getPolicyStoreCatalogs}      | ${{ id: 'gid://gitlab/Organizations::Organization/1' }} | ${mockOrganizationPoliciesResponse().data}
    ${'group'}        | ${getGroupPolicyStorePolicies} | ${getGroupPolicyStoreCatalogs} | ${{ fullPath: 'my-org/my-group' }}                      | ${mockGroupPoliciesResponse().data}
  `('for a $container', ({ container, policiesQuery, catalogsQuery, variables, policiesData }) => {
    const policiesVariables = { ...variables, ids: [mockGraphqlPolicy().id] };

    const catalogsData = (policyStore) => ({
      [container]: { ...policiesData[container], policyStore },
    });

    // Both documents select triggers, so the later write owns that field either way.
    const catalogs = {
      __typename: 'PolicyStore',
      triggers: policiesData[container].policyStore.triggers,
      rules: [{ __typename: 'PolicyStoreRule', id: 'custom', name: 'Custom' }],
      actions: [{ __typename: 'PolicyStoreAction', id: 'block', name: 'Block' }],
    };

    let cache;

    beforeEach(() => {
      ({ cache } = createApolloProvider().defaultClient);
      cache.writeQuery({ query: policiesQuery, variables: policiesVariables, data: policiesData });
    });

    const readPolicies = () =>
      cache.readQuery({ query: policiesQuery, variables: policiesVariables });

    it('keeps the policies read when the catalogs read writes the same policyStore', () => {
      cache.writeQuery({ query: catalogsQuery, variables, data: catalogsData(catalogs) });

      expect(readPolicies()).toEqual(policiesData);
      expect(cache.readQuery({ query: catalogsQuery, variables })).toEqual(catalogsData(catalogs));
    });

    it('keeps the policies read when a later read of the same policyStore is denied', () => {
      cache.writeQuery({ query: catalogsQuery, variables, data: catalogsData(null) });

      expect(readPolicies()).toEqual(policiesData);
    });
  });
  // A project runs the policies query alone, but its refetch merges rather than
  // replaces, so a later denied read must not drop the rows already loaded.
  describe('for a project', () => {
    const variables = { fullPath: 'my-org/my-group/my-project' };

    it('keeps the policies read when a later read of the same policyStore is denied', () => {
      const { cache } = createApolloProvider().defaultClient;
      const { data } = mockProjectPoliciesResponse();

      cache.writeQuery({ query: getProjectPolicyStorePolicies, variables, data });
      cache.writeQuery({
        query: getProjectPolicyStorePolicies,
        variables,
        data: { project: { ...data.project, policyStore: null } },
      });

      expect(cache.readQuery({ query: getProjectPolicyStorePolicies, variables })).toEqual(data);
    });
  });
});
