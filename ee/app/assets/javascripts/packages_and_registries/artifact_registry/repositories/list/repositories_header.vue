<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlIcon } from '@gitlab/ui';
import { __, n__, s__, sprintf } from '~/locale';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import { NAMESPACE_PERMISSION_CREATE_REPOSITORY } from '../../constants';
import { permissionAllows } from '../../graphql/utils/permissions';
import CreateButton from '../components/create_button.vue';
import { formattedCount, humanSizeClamped, toCount } from '../../utils';

export default {
  name: 'ArtifactRegistryRepositoriesHeader',
  i18n: {
    title: s__('ArtifactRegistry|Repositories'),
    storageUsed: s__('ArtifactRegistry|Storage used'),
    moreActions: __('More actions'),
  },
  components: {
    CreateButton,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlIcon,
    PageHeading,
  },
  inject: {
    organizationAccessPath: { default: null },
  },
  props: {
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
    statistics: {
      type: Object,
      required: false,
      default: null,
    },
  },
  computed: {
    canManageAccess() {
      return (
        Boolean(this.organizationAccessPath) &&
        permissionAllows(this.permissions, NAMESPACE_PERMISSION_CREATE_REPOSITORY)
      );
    },
    manageAccessItem() {
      return {
        text: s__('ArtifactRegistry|Manage access'),
        href: this.organizationAccessPath,
      };
    },
    // Each figure is nullable on its own. An unknown one is left out rather than rendered as
    // zero, which would read as an empty namespace.
    statisticsItems() {
      const { repositoriesCount, deduplicatedSizeBytes } = this.statistics ?? {};
      const items = [];

      if (repositoriesCount != null) {
        items.push({
          testId: 'repositories-count',
          icon: 'infrastructure-registry',
          text: sprintf(
            n__(
              'ArtifactRegistry|%{count} repository',
              'ArtifactRegistry|%{count} repositories',
              toCount(repositoriesCount),
            ),
            { count: formattedCount(repositoriesCount) },
          ),
        });
      }

      if (deduplicatedSizeBytes != null) {
        items.push({
          testId: 'storage-used',
          icon: 'archive',
          label: this.$options.i18n.storageUsed,
          text: humanSizeClamped(deduplicatedSizeBytes),
        });
      }

      return items;
    },
  },
};
</script>

<template>
  <page-heading :heading="$options.i18n.title">
    <template v-if="statisticsItems.length" #description>
      <div class="gl-flex gl-flex-wrap gl-gap-5" data-testid="statistics-summary">
        <span
          v-for="item in statisticsItems"
          :key="item.testId"
          class="gl-flex gl-items-center gl-gap-2 gl-text-default"
          :data-testid="item.testId"
        >
          <gl-icon :name="item.icon" />
          <span v-if="item.label" class="gl-sr-only">{{ item.label }}</span>
          {{ item.text }}
        </span>
      </div>
    </template>
    <template #actions>
      <create-button :permissions="permissions" placement="bottom-end" />
      <gl-disclosure-dropdown
        v-if="canManageAccess"
        icon="ellipsis_v"
        :toggle-text="$options.i18n.moreActions"
        text-sr-only
        category="tertiary"
        no-caret
        placement="bottom-end"
        data-testid="header-actions"
      >
        <gl-disclosure-dropdown-item :item="manageAccessItem" data-testid="manage-access" />
      </gl-disclosure-dropdown>
    </template>
  </page-heading>
</template>
