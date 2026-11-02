<script>
import { GlButton, GlDisclosureDropdown } from '@gitlab/ui';
import { s__ } from '~/locale';
import { isLoggedIn } from '~/lib/utils/common_utils';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  AI_CATALOG_INDEX_ROUTE,
  AI_CATALOG_AGENTS_ROUTE,
  AI_CATALOG_AGENTS_NEW_ROUTE,
  AI_CATALOG_FLOWS_ROUTE,
  AI_CATALOG_FLOWS_NEW_ROUTE,
  AI_CATALOG_MCP_SERVERS_ROUTE,
  AI_CATALOG_MCP_SERVERS_NEW_ROUTE,
} from '../router/constants';

export default {
  name: 'AiCatalogNavActions',
  components: {
    GlButton,
    GlDisclosureDropdown,
  },
  mixins: [glAbilitiesMixin(), glFeatureFlagsMixin()],
  inject: {
    isGlobalNamespace: {
      default: false,
    },
  },
  props: {
    canAdmin: {
      type: Boolean,
      required: false,
      default: false,
    },
    canCreate: {
      type: Boolean,
      required: false,
      default: false,
    },
    newButtonVariant: {
      type: String,
      required: false,
      default: 'confirm',
    },
  },
  computed: {
    canCreateItem() {
      return (
        this.glAbilities.readAiCatalog ||
        (isLoggedIn() && this.canAdmin && !this.isGlobalNamespace && this.canCreate)
      );
    },
    showNewItemDropdown() {
      return this.glFeatures.aiCatalogUnifiedViews && this.canCreateItem;
    },
    showNewButton() {
      return this.canCreateItem && this.newButtonProps.route;
    },
    newItemDropdownItems() {
      return [
        {
          text: s__('AICatalog|Create agent'),
          to: { name: AI_CATALOG_AGENTS_NEW_ROUTE },
        },
        {
          text: s__('AICatalog|Create flow'),
          to: { name: AI_CATALOG_FLOWS_NEW_ROUTE },
        },
      ];
    },
    newButtonProps() {
      switch (this.$route.name) {
        case AI_CATALOG_INDEX_ROUTE:
        case AI_CATALOG_AGENTS_ROUTE:
          return {
            route: AI_CATALOG_AGENTS_NEW_ROUTE,
            label: s__('AICatalog|New agent'),
          };
        case AI_CATALOG_FLOWS_ROUTE:
          return {
            route: AI_CATALOG_FLOWS_NEW_ROUTE,
            label: s__('AICatalog|New flow'),
          };
        case AI_CATALOG_MCP_SERVERS_ROUTE:
          return this.glAbilities.createAiCatalogMcpServer
            ? {
                route: AI_CATALOG_MCP_SERVERS_NEW_ROUTE,
                label: s__('AICatalog|New MCP server'),
              }
            : { route: null, label: '' };
        default:
          return {
            route: null,
            label: '',
          };
      }
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-items-center gl-gap-3">
    <gl-disclosure-dropdown
      v-if="showNewItemDropdown"
      :items="newItemDropdownItems"
      :toggle-text="s__('AICatalog|Add')"
      icon="plus"
      placement="bottom-end"
      data-testid="new-item-dropdown"
    />
    <gl-button
      v-else-if="showNewButton"
      :to="{ name: newButtonProps.route }"
      :variant="newButtonVariant"
    >
      {{ newButtonProps.label }}
    </gl-button>
    <slot></slot>
  </div>
</template>
