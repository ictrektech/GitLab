import * as Sentry from '~/sentry/sentry_browser_wrapper';
import getPolicyStorePolicies from './graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from './graphql/get_group_policy_store_policies.query.graphql';
import {
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
  NAMESPACE_TYPE_PROJECT,
} from './constants';
import { policyStoreId, toPolicy, containerQueryVariables, policyStoreFrom } from './policies';

/**
 * The smart query the detail and editor pages resolve their policy with. Both
 * read one policy by id from the container's policies query, which also
 * carries the triggers catalog, and treat a policy they cannot read as the
 * page error, so the query and its error handling are shared.
 *
 * The host component injects `namespaceType`, `namespacePath`, `organizationId`
 * and `policyId`, and declares a `policyError` data flag, which the error
 * hook sets. It must be declared in `data()`: Vue 2 does not make an
 * undeclared property reactive. Not found is not an error; the host reads
 * it from a null policy, so a failed request is the only host write.
 */
export default {
  query() {
    return this.namespaceType === NAMESPACE_TYPE_GROUP
      ? getGroupPolicyStorePolicies
      : getPolicyStorePolicies;
  },
  variables() {
    // A project is read-only, so no detail or editor page mounts on one and no
    // document here takes a project. Without this its path would be sent as an
    // organization's id.
    if (this.namespaceType === NAMESPACE_TYPE_PROJECT) {
      // eslint-disable-next-line @gitlab/require-i18n-strings
      throw new Error('Policy store has no project detail page');
    }

    // Matches containerQueryVariables: only an organization is read by id.
    const namespaceIdentifier =
      this.namespaceType === NAMESPACE_TYPE_ORGANIZATION ? this.organizationId : this.namespacePath;

    return {
      ...containerQueryVariables(this.namespaceType, namespaceIdentifier),
      ids: [policyStoreId(this.policyId)],
    };
  },
  // The blank "new" editor page has no policy to resolve, and an invalid id
  // cannot name one either; policyStoreId is null for both.
  skip() {
    return policyStoreId(this.policyId) === null;
  },
  // A cached read could serve a policy another session has since changed, so
  // the first read always comes from the network. Every read after it follows
  // the cache, so a mutation's normalized result reaches the page instead of
  // costing another round trip.
  fetchPolicy: 'network-only',
  nextFetchPolicy: 'cache-first',
  update(data) {
    return toPolicy(policyStoreFrom(data, this.namespaceType));
  },
  error(error) {
    Sentry.captureException(error);
    this.policyError = true;
  },
};
