<script>
import { GlIcon, GlLink, GlLoadingIcon, GlTableLite } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { formatNumber, n__, s__, sprintf } from '~/locale';
import { MAX_OWNERS, RESOURCES, RESOURCE_ARTIFACT_REGISTRY } from '../constants';
import getResourceAccessSummary from '../graphql/queries/get_resource_access_summary.query.graphql';

export default {
  name: 'OrganizationAccessResourcesTable',
  components: { GlIcon, GlLink, GlLoadingIcon, GlTableLite },
  props: {
    organizationPath: {
      type: String,
      required: true,
    },
  },
  data() {
    return { summaries: {}, hasError: false };
  },
  apollo: {
    summaries: {
      query: getResourceAccessSummary,
      variables() {
        const { ownerRole } = RESOURCES[RESOURCE_ARTIFACT_REGISTRY];

        // Empty until the page passes the registry namespace ID. The mock ignores it.
        // https://gitlab.com/gitlab-org/gitlab/-/issues/632260
        return { resourceId: '', ownerRole, maxOwners: MAX_OWNERS };
      },
      update({ artifactRegistryRoleAssignmentCounts, artifactRegistryRoleAssignments }) {
        return {
          [RESOURCE_ARTIFACT_REGISTRY]: {
            counts: artifactRegistryRoleAssignmentCounts,
            owners: (artifactRegistryRoleAssignments?.nodes || [])
              .map((node) => node?.assignee)
              .filter(Boolean),
          },
        };
      },
      error(error) {
        this.hasError = true;
        createAlert({ message: this.$options.i18n.errorMessage, error, captureError: true });
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.summaries.loading;
    },
    items() {
      return Object.values(RESOURCES).map((resource) => {
        const { counts, owners = [] } = this.summaries[resource.key] || {};
        const total = counts?.total || 0;
        const roleCounts = Object.fromEntries(
          (counts?.byRole || []).map(({ role, count }) => [role, count]),
        );

        return {
          resource,
          membersText: sprintf(
            n__('OrganizationAccess|%{count} member', 'OrganizationAccess|%{count} members', total),
            { count: formatNumber(total) },
          ),
          membersPath: resource.membersPath?.(this.organizationPath) || null,
          roleBreakdown: resource.roles
            .map(({ value, countText }) => {
              const count = roleCounts[value] || 0;

              return sprintf(countText(count), { count: formatNumber(count) });
            })
            .join(' · '),
          owners,
        };
      });
    },
  },
  i18n: {
    errorMessage: s__(
      'OrganizationAccess|An error occurred loading resource access. Please refresh the page to try again.',
    ),
  },
  fields: [
    { key: 'resource', label: s__('OrganizationAccess|Resource') },
    { key: 'members', label: s__('OrganizationAccess|Members') },
    { key: 'owners', label: s__('OrganizationAccess|Managers') },
  ],
};
</script>

<template>
  <gl-loading-icon v-if="isLoading" size="lg" class="gl-mt-5" />
  <gl-table-lite v-else-if="!hasError" :items="items" :fields="$options.fields" stacked="md">
    <template #cell(resource)="{ item }">
      <div class="gl-flex gl-items-center gl-gap-3" data-testid="resource-cell">
        <gl-icon :name="item.resource.icon" variant="subtle" />
        <span class="gl-font-bold">{{ item.resource.label }}</span>
      </div>
    </template>

    <template #cell(members)="{ item }">
      <gl-link v-if="item.membersPath" :href="item.membersPath" data-testid="members-link">
        {{ item.membersText }}
      </gl-link>
      <span v-else data-testid="members-text">{{ item.membersText }}</span>
      <div class="gl-text-sm gl-text-subtle" data-testid="role-breakdown">
        {{ item.roleBreakdown }}
      </div>
    </template>

    <template #cell(owners)="{ item }">
      <span data-testid="owners">
        <span v-for="(owner, index) in item.owners" :key="owner.id" data-testid="owner">
          <gl-link :href="owner.webPath">{{ owner.name }}</gl-link
          ><template v-if="index < item.owners.length - 1">{{ __(', ') }}</template>
        </span>
      </span>
    </template>
  </gl-table-lite>
</template>
