import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies } from '~/lib/graphql';
import { typePolicies as policyStoreTypePolicies } from 'ee/policy_store/apollo';

// createMockApollo's cache options replace the global type policies, unlike
// createCache in production, which spreads the page's over them. Build every
// policy store spec cache here so each one carries both.
export const createPolicyStoreMockApollo = (handlers) =>
  createMockApollo(handlers, {}, { typePolicies: { ...typePolicies, ...policyStoreTypePolicies } });
