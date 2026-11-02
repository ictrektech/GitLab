<script>
import { GlTableLite } from '@gitlab/ui';
import { s__ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { ROLE_NAMES } from './constants';

const ROLE_PERMISSIONS = {
  ARTIFACT_VIEWER: s__(
    'ArtifactRegistry|Browse repositories and pull artifacts. Cannot publish or delete.',
  ),
  ARTIFACT_CONTRIBUTOR: s__(
    'ArtifactRegistry|Browse, pull, and publish artifacts (for example, from CI/CD jobs). Cannot delete artifacts or change repository settings.',
  ),
  ARTIFACT_MANAGER: s__(
    'ArtifactRegistry|Publish and delete artifacts. Update settings for repositories and virtual repository upstreams. Cannot create or delete repositories, or manage access to the registry.',
  ),
  ARTIFACT_ADMIN: s__(
    'ArtifactRegistry|View, create, and delete repositories. Manage member access to the registry.',
  ),
};

export default {
  name: 'ArtifactRegistryInheritedMembersCard',
  components: {
    CrudComponent,
    GlTableLite,
  },
  items: ['ARTIFACT_ADMIN', 'ARTIFACT_MANAGER', 'ARTIFACT_CONTRIBUTOR', 'ARTIFACT_VIEWER'].map(
    (role) => ({
      role: ROLE_NAMES[role],
      permission: ROLE_PERMISSIONS[role],
    }),
  ),
  fields: [
    { key: 'role', label: s__('ArtifactRegistry|Role') },
    { key: 'permission', label: s__('ArtifactRegistry|Permission') },
  ],
};
</script>

<template>
  <crud-component
    :title="s__('ArtifactRegistry|Inherited members')"
    title-tag="h3"
    body-class="!gl-m-0"
  >
    <gl-table-lite :fields="$options.fields" :items="$options.items" class="gl-mb-0" />
  </crud-component>
</template>
