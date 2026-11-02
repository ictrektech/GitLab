<script>
import {
  GlAvatarLabeled,
  GlAvatarLink,
  GlEmptyState,
  GlLoadingIcon,
  GlTableLite,
} from '@gitlab/ui';
import { s__ } from '~/locale';
import CreatedAt from '~/members/components/table/created_at.vue';

export default {
  name: 'OrganizationAccessMembersTable',
  components: {
    CreatedAt,
    GlAvatarLabeled,
    GlAvatarLink,
    GlEmptyState,
    GlLoadingIcon,
    GlTableLite,
  },
  props: {
    resource: {
      type: Object,
      required: true,
    },
    members: {
      type: Array,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    hasActiveFilters: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    emptyState() {
      if (this.hasActiveFilters) return this.$options.emptyStates.noResults;

      return {
        illustration: 'empty-user-md',
        title: s__('OrganizationAccess|Grant access to members'),
        description: this.resource.noMembersDescription,
      };
    },
    roleLabels() {
      return Object.fromEntries(this.resource.roles.map(({ value, text }) => [value, text]));
    },
  },
  fields: [
    { key: 'member', label: s__('OrganizationAccess|Member') },
    { key: 'role', label: s__('OrganizationAccess|Role') },
    { key: 'granted', label: s__('OrganizationAccess|Access granted') },
  ],
  emptyStates: {
    noResults: {
      illustration: 'empty-search-md',
      title: s__('OrganizationAccess|No results found'),
      description: s__('OrganizationAccess|Edit your search and try again.'),
    },
  },
  avatarSize: 32,
};
</script>

<template>
  <gl-loading-icon v-if="loading" size="lg" class="gl-mt-5" />
  <gl-empty-state
    v-else-if="!members.length"
    :illustration-name="emptyState.illustration"
    :title="emptyState.title"
    :description="emptyState.description"
    data-testid="members-empty"
  />
  <gl-table-lite v-else :items="members" :fields="$options.fields" stacked="md">
    <template #cell(member)="{ item }">
      <gl-avatar-link :href="item.assignee.webPath" data-testid="member-avatar-link">
        <gl-avatar-labeled
          :size="$options.avatarSize"
          :src="item.assignee.avatarUrl"
          :entity-name="item.assignee.name"
          :label="item.assignee.name"
          :sub-label="`@${item.assignee.username}`"
        />
      </gl-avatar-link>
    </template>

    <template #cell(role)="{ item }">
      <span data-testid="member-role">{{ roleLabels[item.role] }}</span>
    </template>

    <template #cell(granted)="{ item }">
      <created-at :date="item.createdAt" />
    </template>
  </gl-table-lite>
</template>
