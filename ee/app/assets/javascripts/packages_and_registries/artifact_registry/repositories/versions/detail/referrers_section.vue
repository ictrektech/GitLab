<script>
import { GlAlert, GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import { isEqual, isNil, omit, omitBy } from 'lodash-es';
import { fetchPolicies } from '~/lib/graphql';
import { s__ } from '~/locale';
import { getPageParams } from '~/packages_and_registries/shared/utils';
import { GRAPHQL_PAGE_SIZE } from '../../../constants';
import getManifestReferrersQuery from '../../../graphql/queries/get_manifest_referrers.query.graphql';
import ReferrersTable from './referrers_table.vue';

const CURSOR_QUERY_KEYS = ['after', 'before'];

export default {
  name: 'ArtifactRegistryReferrersSection',
  components: {
    GlAlert,
    GlKeysetPagination,
    GlSkeletonLoader,
    ReferrersTable,
  },
  inject: ['organizationGid'],
  props: {
    name: {
      type: String,
      required: true,
    },
    artifactId: {
      type: String,
      required: true,
    },
    digest: {
      type: String,
      required: true,
    },
  },
  emits: ['status-changed'],
  data() {
    return {
      referrers: undefined,
      hasError: false,
    };
  },
  apollo: {
    referrers: {
      query: getManifestReferrersQuery,
      // The connection's cache policy keys on no argument, so a cursored read would otherwise
      // be answered from the page already held and the pager would move nothing.
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.name,
          artifactId: this.artifactId,
          digest: this.digest,
          first: GRAPHQL_PAGE_SIZE,
          // A backward page asks for `last` and carries `first: undefined`, so the page
          // params have to land after the default rather than beside it.
          ...this.pageParams,
        };
      },
      update: ({ organization }) =>
        organization?.artifactRegistryRepository?.manifest?.referrers ?? null,
      // Not redundant with `error` below: this query sets no `errorPolicy`, so vue-apollo calls
      // `result` on failure too. Clearing unconditionally here would drop the alert.
      result({ error }) {
        this.hasError = Boolean(error);
      },
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.referrers.loading;
    },
    rows() {
      return this.referrers?.nodes ?? [];
    },
    // An absent connection is a manifest that stopped resolving, not one nothing attests to, so
    // it reads as a failure rather than as an empty list.
    hasFailed() {
      return this.hasError || (!this.isLoading && this.referrers === null);
    },
    isFirstRead() {
      return this.isLoading && !this.rows.length;
    },
    pageParams() {
      return getPageParams(this.$route.query, GRAPHQL_PAGE_SIZE);
    },
    // vue-apollo keeps the last good result on error, so without this the pager would stay
    // live on the failed page's cursors, and Next would rebuild the query that just failed.
    pageInfo() {
      if (this.hasFailed) return {};

      return this.referrers?.pageInfo ?? {};
    },
  },
  // Watched from `mounted`: vue-apollo registers the query in `created`, after declared
  // watchers first run, so a declared watcher would throw once and never run again.
  mounted() {
    this.$watch(
      () => ({ isLoading: this.isLoading, hasError: this.hasFailed, count: this.rows.length }),
      (status) => this.$emit('status-changed', status),
      { immediate: true },
    );
  },
  methods: {
    pageTo(cursor) {
      const remainder = omit(this.$route.query, CURSOR_QUERY_KEYS);
      const query = omitBy({ ...remainder, ...cursor }, isNil);

      if (isEqual(query, this.$route.query)) return;

      this.$router.push({ path: this.$route.path, query });
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
  },
};
</script>

<template>
  <div>
    <gl-skeleton-loader v-if="isFirstRead" :lines="3" data-testid="referrers-skeleton" />

    <gl-alert
      v-else-if="hasFailed"
      variant="danger"
      :dismissible="false"
      data-testid="referrers-error"
    >
      {{ $options.i18n.unavailable }}
    </gl-alert>

    <referrers-table
      v-else
      :referrers="rows"
      :name="name"
      :artifact-id="artifactId"
      :subject-digest="digest"
      :is-loading="isLoading"
    />

    <div class="gl-mt-3 gl-flex gl-justify-center">
      <gl-keyset-pagination
        v-bind="pageInfo"
        :disabled="isLoading"
        @prev="pageTo({ before: $event })"
        @next="pageTo({ after: $event })"
      />
    </div>
  </div>
</template>
