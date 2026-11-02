<script>
import { GlAlert } from '@gitlab/ui';
import produce from 'immer';
import { uniqBy } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { joinPaths } from '~/lib/utils/url_utility';
import { __, s__ } from '~/locale';
import {
  NAMESPACE_TYPE_GROUP,
  NAMESPACE_TYPE_ORGANIZATION,
  NAMESPACE_TYPE_PROJECT,
  POLICIES_PER_PAGE,
} from '../../constants';
import { toListPolicies, containerQueryVariables, policyStoreFrom } from '../../policies';
import {
  startOfReportingWindow,
  toEvaluationsCount,
  EVALUATIONS_COUNT_LIMIT,
} from '../../evaluations';
import getPolicyStorePolicies from '../../graphql/get_policy_store_policies.query.graphql';
import getGroupPolicyStorePolicies from '../../graphql/get_group_policy_store_policies.query.graphql';
import getProjectPolicyStorePolicies from '../../graphql/get_project_policy_store_policies.query.graphql';
import getPolicyEvaluationsCount from '../../graphql/get_policy_evaluations_count.query.graphql';
import getGroupPolicyEvaluationsCount from '../../graphql/get_group_policy_evaluations_count.query.graphql';
import ListWrapper from './list_wrapper.vue';

export default {
  name: 'PolicyStoreListRoot',
  components: {
    GlAlert,
    ListWrapper,
  },
  // The per-policy detail path is derived from listPath and the policy id until the API exposes it.
  inject: {
    organizationId: {},
    namespacePath: { default: '' },
    namespaceType: {},
    canCreatePolicy: { default: false },
    newPolicyPath: { default: '' },
    listPath: { default: '' },
  },
  data() {
    return {
      policies: [],
      pageInfo: { hasNextPage: false, endCursor: null },
      loadingMore: false,
      loadMoreError: false,
      policiesError: false,
      policiesErrorPermission: false,
      recentEvaluationsCount: null,
      recentEvaluationsError: false,
    };
  },
  // Both queries write the container's policyStore through the custom merge in
  // apollo.js. Apollo hands a custom merge no `existing` value on a refetch
  // unless the refetch is told to merge, so without this a Retry of one query
  // would drop the other's fields from the cache.
  apollo: {
    policies: {
      query() {
        if (this.isGroupContext) return getGroupPolicyStorePolicies;
        if (this.isProjectContext) return getProjectPolicyStorePolicies;

        return getPolicyStorePolicies;
      },
      refetchWritePolicy: 'merge',
      variables() {
        return { ...this.scopeVariables, first: POLICIES_PER_PAGE };
      },
      update(data) {
        return toListPolicies(policyStoreFrom(data, this.namespaceType));
      },
      result({ data, error }) {
        // A failed refetch re-emits the last cached data with the error
        // attached, and fetchMore re-emits the cache before its own promise
        // settles; skip both so the error state set by the hooks below survives.
        if (!data || error || this.loadingMore) return;

        // Denied reads return null instead of an error — the resolver nulls the
        // field when the viewer lacks read_govern_policy or the experiment is
        // off — so a null connection is the only permission signal the API gives.
        const connection = policyStoreFrom(data, this.namespaceType)?.policies;
        const denied = !connection;
        this.policiesError = denied;
        this.policiesErrorPermission = denied;
        this.pageInfo = connection?.pageInfo ?? { hasNextPage: false, endCursor: null };
      },
      error(error) {
        Sentry.captureException(error);
        this.policiesError = true;
      },
    },
    // The stat gets no error state of its own, but it must not answer with a
    // confident 0 when the read failed: null renders as a placeholder while
    // the policies query keeps ownership of the page error.
    recentEvaluationsCount: {
      query() {
        return this.isGroupContext ? getGroupPolicyEvaluationsCount : getPolicyEvaluationsCount;
      },
      // A project's policyStore reports no evaluations of its own, so the read
      // would always answer 0; the stat is hidden there instead of asked for.
      skip() {
        return this.isProjectContext;
      },
      refetchWritePolicy: 'merge',
      variables() {
        return this.evaluationsVariables();
      },
      update(data) {
        return toEvaluationsCount(policyStoreFrom(data, this.namespaceType)?.policyEvaluations);
      },
      error(error) {
        Sentry.captureException(error);
        this.recentEvaluationsError = true;
      },
    },
  },
  computed: {
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    isProjectContext() {
      return this.namespaceType === NAMESPACE_TYPE_PROJECT;
    },
    namespaceIdentifier() {
      return this.namespaceType === NAMESPACE_TYPE_ORGANIZATION
        ? this.organizationId
        : this.namespacePath;
    },
    // Throws on a blank identifier, as the mutation path does: a page that
    // forgot to provide it is a wiring bug to report, not an empty path to query.
    scopeVariables() {
      return containerQueryVariables(this.namespaceType, this.namespaceIdentifier);
    },
    // fetchMore flips the smart query's loading flag too; keep the loaded rows
    // visible and let the Load more button carry the spinner instead.
    policiesLoading() {
      return this.$apollo.queries.policies.loading && !this.loadingMore;
    },
    recentEvaluationsLoading() {
      return this.$apollo.queries.recentEvaluationsCount.loading;
    },
    // A failed refetch leaves Apollo re-emitting the last cached count, so the
    // error flag rather than the value decides whether the tile can show it.
    recentEvaluations() {
      return this.recentEvaluationsError ? null : this.recentEvaluationsCount;
    },
    listPolicies() {
      // A failed refetch leaves Apollo re-emitting the last cached rows; guard
      // here so an error never shows stale data, matching the REST version.
      if (this.policiesError) return [];

      // A read-only container provides no listPath, so its rows link nowhere.
      return this.policies.map((policy) => ({
        ...policy,
        detailPath: this.listPath ? joinPaths(this.listPath, String(policy.id)) : '',
      }));
    },
    policiesErrorMessage() {
      return this.policiesErrorPermission
        ? s__('PolicyStore|You do not have permission to view the policies.')
        : s__('PolicyStore|The policies could not be fetched from the Policy Store API.');
    },
    // Retrying cannot fix missing permissions, so the button only shows for
    // failures that might be transient.
    policiesErrorRetryText() {
      return this.policiesErrorPermission ? null : __('Retry');
    },
  },
  methods: {
    evaluationsVariables() {
      return {
        ...this.scopeVariables,
        evaluatedAfter: startOfReportingWindow(),
        limit: EVALUATIONS_COUNT_LIMIT,
      };
    },
    // The stat can fail on its own, so Retry covers it whichever page fetch
    // failed alongside it. A failed retry rejects the refetch promise; the
    // error() hook already handles it, so consume the rejection to avoid an
    // unhandled one.
    retry() {
      if (this.loadMoreError) {
        this.loadMorePolicies();
      } else {
        this.policiesError = false;
        this.policiesErrorPermission = false;
        this.$apollo.queries.policies.refetch().catch(() => {});
      }

      this.refetchRecentEvaluations();
    },
    // Pass the variables explicitly: a bare refetch() reuses the boundary
    // computed at mount, so a tab left open past UTC midnight would keep
    // asking for yesterday's window.
    refetchRecentEvaluations() {
      // A query skipped from creation never gets an observer, and vue-apollo's
      // refetch() returns undefined rather than a promise for one.
      if (this.isProjectContext) return;

      this.recentEvaluationsError = false;
      this.$apollo.queries.recentEvaluationsCount
        .refetch(this.evaluationsVariables())
        .catch(() => {});
    },
    loadMorePolicies() {
      this.loadingMore = true;
      this.loadMoreError = false;

      this.$apollo.queries.policies
        .fetchMore({
          variables: { after: this.pageInfo.endCursor },
          updateQuery: (previousResult, { fetchMoreResult }) =>
            produce(fetchMoreResult, (draftData) => {
              const previousNodes =
                policyStoreFrom(previousResult, this.namespaceType)?.policies?.nodes ?? [];
              const connection = policyStoreFrom(draftData, this.namespaceType).policies;

              // The cursor is a page number over a mutable store, so a row can shift
              // across the boundary. First wins: a repeated row keeps its loaded values
              // and its place, rather than jumping to where the new page put it.
              connection.nodes = uniqBy([...previousNodes, ...connection.nodes], 'id');
            }),
        })
        .then(({ data }) => {
          this.pageInfo = policyStoreFrom(data, this.namespaceType).policies.pageInfo;
        })
        .catch((error) => {
          Sentry.captureException(error);
          // fetchMore runs no-cache, so a failed page never touches the rows
          // already loaded; keep them and let Retry ask for that page again.
          this.loadMoreError = true;
        })
        .finally(() => {
          this.loadingMore = false;
        });
    },
  },
};
</script>

<template>
  <div>
    <gl-alert
      v-if="policiesError || loadMoreError"
      variant="danger"
      :dismissible="false"
      :primary-button-text="policiesErrorRetryText"
      class="gl-mt-4"
      data-testid="policies-error"
      @primary-action="retry()"
    >
      {{ policiesErrorMessage }}
    </gl-alert>
    <list-wrapper
      :policies="listPolicies"
      :loading="policiesLoading"
      :loading-more="loadingMore"
      :has-next-page="pageInfo.hasNextPage && !loadMoreError"
      :error="policiesError"
      :recent-evaluations="recentEvaluations"
      :recent-evaluations-loading="recentEvaluationsLoading"
      :can-create-policy="canCreatePolicy"
      :show-recent-evaluations="!isProjectContext"
      :new-policy-path="newPolicyPath"
      @load-more="loadMorePolicies"
    />
  </div>
</template>
