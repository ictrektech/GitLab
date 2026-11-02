<script>
import PageHeading from '~/vue_shared/components/page_heading.vue';
import ResourcesTable from './resources_table.vue';

export default {
  name: 'OrganizationAccessApp',
  components: { PageHeading, ResourcesTable },
  props: {
    organizationPath: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <div>
    <page-heading :heading="s__('OrganizationAccess|Organization access')">
      <template #description>
        {{ s__('OrganizationAccess|Manage resource access for items at the organization level') }}
      </template>
    </page-heading>
    <resources-table :organization-path="organizationPath" />
  </div>
</template>
