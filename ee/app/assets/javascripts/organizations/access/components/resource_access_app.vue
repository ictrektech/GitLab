<script>
import { GlButton, GlFilteredSearch, GlFilteredSearchToken, GlModalDirective } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { n__, s__ } from '~/locale';
import { OPERATOR_IS, OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import showGlobalToast from '~/vue_shared/plugins/global_toast';
import { MAX_MEMBERS, RESOURCES, TOKEN_TYPE_ROLE } from '../constants';
import getResourceMembers from '../graphql/queries/get_resource_members.query.graphql';
import InviteMembersModal, { INVITE_MEMBERS_MODAL_ID } from './invite_members_modal.vue';
import MemberStats from './member_stats.vue';
import MembersTable from './members_table.vue';

const roleToken = (data) => ({ type: TOKEN_TYPE_ROLE, value: { data, operator: OPERATOR_IS } });

const invitedAssignment = ({ id, name, username, avatar_url: avatarUrl }, role, createdAt) => ({
  __typename: 'ArtifactRegistryRoleAssignment',
  resourceId: '',
  role,
  createdAt,
  assignee: {
    __typename: 'UserCore',
    id: convertToGraphQLId(TYPENAME_USER, id),
    name,
    username,
    webPath: '#',
    avatarUrl: avatarUrl || null,
  },
});

export default {
  name: 'OrganizationAccessResourceApp',
  components: {
    GlButton,
    GlFilteredSearch,
    InviteMembersModal,
    MemberStats,
    MembersTable,
    PageHeading,
  },
  directives: { GlModal: GlModalDirective },
  props: {
    resourceKey: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      members: [],
      counts: null,
      hasError: false,
      filterValue: [],
      filters: { search: null, role: null },
      // Local until https://gitlab.com/gitlab-org/gitlab/-/work_items/629712 calls the grant mutation and refetches.
      invited: [],
    };
  },
  apollo: {
    members: {
      query: getResourceMembers,
      variables() {
        // Empty until the page passes the registry namespace ID (#629711). The mock ignores it.
        return { resourceId: '', first: MAX_MEMBERS };
      },
      update({ artifactRegistryRoleAssignments }) {
        return (artifactRegistryRoleAssignments?.nodes || []).filter((node) => node?.assignee);
      },
      result({ data }) {
        this.counts = data?.artifactRegistryRoleAssignmentCounts || null;
      },
      error(error) {
        this.hasError = true;
        createAlert({ message: this.$options.i18n.errorMessage, error, captureError: true });
      },
    },
  },
  computed: {
    resource() {
      return RESOURCES[this.resourceKey];
    },
    invitedIds() {
      return new Set(this.invited.map(({ assignee }) => assignee.id));
    },
    replacedMembers() {
      return this.members.filter(({ assignee }) => this.invitedIds.has(assignee.id));
    },
    allMembers() {
      return [
        ...this.invited,
        ...this.members.filter(({ assignee }) => !this.invitedIds.has(assignee.id)),
      ];
    },
    isLoading() {
      return this.$apollo.queries.members.loading;
    },
    stats() {
      const {
        adminRole,
        ownerRole,
        adminStatTitle,
        adminFilterLabel,
        ownerStatTitle,
        ownerFilterLabel,
      } = this.resource;
      const withRole = (list, value) => list.filter(({ role }) => role === value).length;
      const countRole = (value) =>
        (this.counts?.byRole.find(({ role }) => role === value)?.count || 0) +
        withRole(this.invited, value) -
        withRole(this.replacedMembers, value);

      return [
        {
          title: adminStatTitle,
          value: countRole(adminRole),
          filter: roleToken(adminRole),
          filterLabel: adminFilterLabel,
        },
        {
          title: ownerStatTitle,
          value: countRole(ownerRole),
          filter: roleToken(ownerRole),
          filterLabel: ownerFilterLabel,
        },
        {
          title: s__('OrganizationAccess|Total members'),
          value: (this.counts?.total || 0) + this.invited.length - this.replacedMembers.length,
        },
      ];
    },
    availableTokens() {
      return [
        {
          type: TOKEN_TYPE_ROLE,
          title: s__('OrganizationAccess|Role'),
          icon: 'key',
          token: GlFilteredSearchToken,
          operators: OPERATORS_IS,
          unique: true,
          options: this.resource.roles.map(({ value, text }) => ({ value, title: text })),
        },
      ];
    },
    hasActiveFilters() {
      return Object.values(this.filters).some(Boolean);
    },
    filteredMembers() {
      const { search, role } = this.filters;
      const query = search?.toLowerCase().replace(/^@/, '');

      return this.allMembers.filter((member) => {
        if (role && member.role !== role) return false;
        if (!query) return true;

        const { name, username } = member.assignee;
        return name.toLowerCase().includes(query) || username.toLowerCase().includes(query);
      });
    },
  },
  methods: {
    onInput(value) {
      this.filterValue = value;
    },
    onSubmit(terms) {
      // The `submit` payload has free text as plain strings and tokens as
      // `{ type, value: { data } }`, even with `terms-as-tokens`.
      const search = terms
        .filter((term) => typeof term === 'string')
        .map((term) => term.trim())
        .join(' ');

      this.filters = {
        search: search || null,
        role: terms.find((term) => term.type === TOKEN_TYPE_ROLE)?.value.data ?? null,
      };
    },
    onClear() {
      this.filterValue = [];
      this.filters = { search: null, role: null };
    },
    onStatFilter(token) {
      this.filterValue = [token];
      this.onSubmit([token]);
    },
    onTokenDestroy({ type }) {
      if (type === TOKEN_TYPE_ROLE) this.filters = { ...this.filters, role: null };
    },
    onInvite({ users, role }) {
      const createdAt = new Date().toISOString();
      const invited = users.map((user) => invitedAssignment(user, role, createdAt));
      const ids = new Set(invited.map(({ assignee }) => assignee.id));

      this.invited = [...invited, ...this.invited.filter(({ assignee }) => !ids.has(assignee.id))];
      showGlobalToast(
        n__(
          'OrganizationAccess|Member was successfully added.',
          'OrganizationAccess|Members were successfully added.',
          users.length,
        ),
      );
    },
  },
  inviteMembersModalId: INVITE_MEMBERS_MODAL_ID,
  i18n: {
    errorMessage: s__(
      'OrganizationAccess|An error occurred loading members. Please refresh the page to try again.',
    ),
  },
};
</script>

<template>
  <div>
    <page-heading :heading="resource.label">
      <template v-if="!hasError" #actions>
        <gl-button v-gl-modal="$options.inviteMembersModalId" variant="confirm">
          {{ s__('OrganizationAccess|Invite members') }}
        </gl-button>
      </template>
    </page-heading>
    <template v-if="!hasError">
      <member-stats :stats="stats" :loading="isLoading" class="gl-mb-5" @filter="onStatFilter" />
      <gl-filtered-search
        :value="filterValue"
        :placeholder="s__('OrganizationAccess|Search by name or username')"
        :available-tokens="availableTokens"
        :clear-button-title="__('Clear')"
        :close-button-title="__('Close')"
        terms-as-tokens
        @input="onInput"
        @submit="onSubmit"
        @clear="onClear"
        @token-destroy="onTokenDestroy"
      />
      <members-table
        :resource="resource"
        :members="filteredMembers"
        :loading="isLoading"
        :has-active-filters="hasActiveFilters"
        class="gl-mt-5"
      />
      <invite-members-modal :resource="resource" @invite="onInvite" />
    </template>
  </div>
</template>
