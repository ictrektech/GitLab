<script>
import { GlAlert, GlAvatarLabeled, GlBadge, GlButton, GlTableLite } from '@gitlab/ui';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { fetchPolicies } from '~/lib/graphql';
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import getRepositoryRoleAssignmentsQuery from '../../../graphql/queries/get_repository_role_assignments.query.graphql';
import {
  ROLE_ASSIGNMENTS_ERROR_DENIED,
  ROLE_ASSIGNMENTS_ERROR_INVALID_REQUEST,
  ROLE_ASSIGNMENTS_ERROR_UNKNOWN,
  ROLE_ASSIGNMENTS_ERROR_UNAVAILABLE,
  ROLE_ASSIGNMENTS_PAGE_SIZE,
  ROLE_NAMES,
} from './constants';

const KNOWN_ERROR_CODES = [
  ROLE_ASSIGNMENTS_ERROR_DENIED,
  ROLE_ASSIGNMENTS_ERROR_UNAVAILABLE,
  ROLE_ASSIGNMENTS_ERROR_INVALID_REQUEST,
];

const errorCode = (error) => {
  const code = error?.graphQLErrors?.[0]?.extensions?.code;

  return KNOWN_ERROR_CODES.includes(code) ? code : ROLE_ASSIGNMENTS_ERROR_UNKNOWN;
};

export default {
  name: 'ArtifactRegistryDirectMembersCard',
  components: {
    CrudComponent,
    GlAlert,
    GlAvatarLabeled,
    GlBadge,
    GlButton,
    GlTableLite,
  },
  props: {
    repositoryId: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      roleAssignments: undefined,
      error: null,
      hasReloaded: false,
      isLoadingMore: false,
    };
  },
  apollo: {
    roleAssignments: {
      query: getRepositoryRoleAssignmentsQuery,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      nextFetchPolicy: fetchPolicies.CACHE_FIRST,
      notifyOnNetworkStatusChange: true,
      variables() {
        return { resourceId: this.repositoryId, first: ROLE_ASSIGNMENTS_PAGE_SIZE };
      },
      update: ({ artifactRegistryRoleAssignments }) => artifactRegistryRoleAssignments,
      result({ error }) {
        if (!error) this.error = null;
      },
      error(error) {
        this.showFirstPageError(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.roleAssignments.loading && !this.isLoadingMore;
    },
    showsRows() {
      return !this.isLoading && (!this.error || this.error.onLoadMore);
    },
    rows() {
      if (!this.showsRows) return [];

      return (this.roleAssignments?.nodes ?? []).filter(({ assignee }) => assignee);
    },
    pageInfo() {
      return this.roleAssignments?.pageInfo ?? {};
    },
    showsLoadMore() {
      return this.showsRows && !this.isDenied && Boolean(this.pageInfo.hasNextPage);
    },
    count() {
      if (!this.showsRows) return null;
      if (!this.pageInfo.hasNextPage) return this.rows.length;

      return sprintf(s__('ArtifactRegistry|%{count}+'), { count: this.rows.length });
    },
    isEmpty() {
      return this.showsRows && Boolean(this.roleAssignments) && this.rows.length === 0;
    },
    isDenied() {
      return this.error?.code === ROLE_ASSIGNMENTS_ERROR_DENIED;
    },
    showsRetry() {
      if (!this.error || this.isDenied) return false;

      return !this.error.onLoadMore || this.error.code === ROLE_ASSIGNMENTS_ERROR_INVALID_REQUEST;
    },
    errorMessage() {
      return this.isDenied ? this.$options.i18n.denied : this.$options.i18n.failed;
    },
    currentUserGid() {
      return gon.current_user_id ? convertToGraphQLId(TYPENAME_USER, gon.current_user_id) : null;
    },
  },
  methods: {
    showFirstPageError(error) {
      this.error = { code: errorCode(error), onLoadMore: false };
    },
    reload() {
      this.error = null;
      this.$apollo.queries.roleAssignments.refetch().catch(this.showFirstPageError);
    },
    retry() {
      this.hasReloaded = false;
      this.reload();
    },
    async loadMore() {
      this.isLoadingMore = true;

      try {
        await this.$apollo.queries.roleAssignments.fetchMore({
          variables: { after: this.pageInfo.endCursor },
        });
        this.error = null;
        this.hasReloaded = false;
      } catch (error) {
        this.showLoadMoreError(errorCode(error));
      } finally {
        this.isLoadingMore = false;
      }
    },
    showLoadMoreError(code) {
      if (code === ROLE_ASSIGNMENTS_ERROR_INVALID_REQUEST && !this.hasReloaded) {
        this.hasReloaded = true;
        this.reload();
        return;
      }

      this.error = { code, onLoadMore: true };
    },
    isCurrentUser(assignee) {
      return assignee.id === this.currentUserGid;
    },
    roleName(role) {
      return ROLE_NAMES[role] ?? this.$options.i18n.unavailableRole;
    },
  },
  fields: [
    { key: 'member', label: s__('ArtifactRegistry|Member') },
    { key: 'role', label: s__('ArtifactRegistry|Role') },
    { key: 'actions', label: s__('ArtifactRegistry|Actions'), thClass: 'gl-sr-only' },
  ],
  avatarSize: 32,
  i18n: {
    title: s__('ArtifactRegistry|Direct members'),
    empty: s__('ArtifactRegistry|There are no direct members for this repository.'),
    denied: s__("ArtifactRegistry|You don't have permission to view access for this repository."),
    failed: s__('ArtifactRegistry|Direct members could not be loaded.'),
    retry: s__('ArtifactRegistry|Retry'),
    loadMore: s__('ArtifactRegistry|Load more'),
    currentUser: s__("ArtifactRegistry|It's you"),
    unavailableRole: s__('ArtifactRegistry|Unavailable role'),
  },
};
</script>

<template>
  <crud-component
    :title="$options.i18n.title"
    title-tag="h3"
    :count="count"
    :show-zero-count="showsRows"
    :is-loading="isLoading"
    body-class="!gl-m-0"
    data-testid="direct-members-card"
  >
    <template v-if="isEmpty" #empty>
      {{ $options.i18n.empty }}
    </template>

    <gl-alert
      v-if="error"
      variant="danger"
      :dismissible="false"
      :primary-button-text="showsRetry ? $options.i18n.retry : ''"
      class="gl-m-3"
      data-testid="direct-members-error"
      @primary-action="retry"
    >
      {{ errorMessage }}
    </gl-alert>

    <gl-table-lite v-if="rows.length" :fields="$options.fields" :items="rows" class="gl-mb-0">
      <template #cell(member)="{ item: { assignee } }">
        <gl-avatar-labeled
          :label="assignee.name"
          :label-link="assignee.webPath"
          :sub-label="`@${assignee.username}`"
          :src="assignee.avatarUrl"
          :entity-name="assignee.name"
          :size="$options.avatarSize"
        >
          <template v-if="isCurrentUser(assignee)" #meta>
            <gl-badge variant="success" class="gl-ml-2" data-testid="current-user-badge">
              {{ $options.i18n.currentUser }}
            </gl-badge>
          </template>
        </gl-avatar-labeled>
      </template>

      <template #cell(role)="{ item: { role } }">
        {{ roleName(role) }}
      </template>
    </gl-table-lite>

    <template v-if="showsLoadMore" #pagination>
      <div class="crud-pagination-container">
        <gl-button :loading="isLoadingMore" data-testid="load-more" @click="loadMore">
          {{ $options.i18n.loadMore }}
        </gl-button>
      </div>
    </template>
  </crud-component>
</template>
