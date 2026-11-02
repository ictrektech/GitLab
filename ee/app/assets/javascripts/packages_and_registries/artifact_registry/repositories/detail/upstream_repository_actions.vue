<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem, GlToastMixin } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { REPOSITORY_EDIT_ROUTE_NAME } from 'ee/packages_and_registries/artifact_registry/constants';
import clearRepositoryCacheMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/clear_repository_cache.mutation.graphql';
import dissociateUpstreamRepositoryMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/dissociate_upstream_repository.mutation.graphql';
import {
  evictClearedRepositoryDetails,
  evictDissociatedUpstreamRepositories,
} from 'ee/packages_and_registries/artifact_registry/graphql/utils/cache_update';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import {
  upstreamActions,
  upstreamHasActions,
} from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';

export default {
  name: 'ArtifactRegistryUpstreamRepositoryActions',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
  },
  mixins: [GlToastMixin],
  props: {
    upstreamRepository: {
      type: Object,
      required: true,
    },
    associationId: {
      type: String,
      required: true,
    },
    repository: {
      type: Object,
      required: true,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      clearing: false,
      removing: false,
    };
  },
  computed: {
    busy() {
      return this.clearing || this.removing;
    },
    toggleText() {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
        name: this.upstreamRepository.name,
      });
    },
    allowed() {
      return upstreamActions(this.upstreamRepository, this.permissions);
    },
    hasItems() {
      return upstreamHasActions(this.upstreamRepository, this.permissions);
    },
    editItem() {
      return {
        text: s__('ArtifactRegistry|Edit repository'),
        to: { name: REPOSITORY_EDIT_ROUTE_NAME, params: { id: this.upstreamRepository.name } },
      };
    },
    clearCacheItem() {
      return {
        text: s__('ArtifactRegistry|Clear cache'),
        action: () => this.clearCache(),
      };
    },
    removeItem() {
      return {
        text: s__('ArtifactRegistry|Remove repository'),
        variant: 'danger',
        action: () => this.remove(),
        extraAttrs: {
          'aria-label': sprintf(s__('ArtifactRegistry|Remove repository %{name}'), {
            name: this.upstreamRepository.name,
          }),
        },
      };
    },
  },
  methods: {
    async clearCache() {
      if (this.busy) return;

      this.clearing = true;
      const { name } = this.upstreamRepository;

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: clearRepositoryCacheMutation,
          input: { name },
          update: evictClearedRepositoryDetails(name),
        });

        if (!accepted) return;

        this.$toast.show(
          sprintf(s__('ArtifactRegistry|Cache clear successfully scheduled for %{name}.'), {
            name,
          }),
        );
      } finally {
        this.clearing = false;
      }
    },
    async remove() {
      if (this.busy) return;

      this.removing = true;
      const { name, format } = this.repository;

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: dissociateUpstreamRepositoryMutation,
          input: { name, format, associationId: this.associationId },
          update: evictDissociatedUpstreamRepositories(name),
        });

        if (!accepted) return;

        this.$toast.show(
          sprintf(s__('ArtifactRegistry|%{name} removed from this virtual repository.'), {
            name: this.upstreamRepository.name,
          }),
        );
      } finally {
        this.removing = false;
      }
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    v-if="hasItems"
    icon="ellipsis_v"
    :toggle-text="toggleText"
    :loading="busy"
    text-sr-only
    category="tertiary"
    no-caret
    placement="bottom-end"
    data-testid="upstream-actions"
  >
    <gl-disclosure-dropdown-item
      v-if="allowed.clearCache"
      :item="clearCacheItem"
      data-testid="clear-upstream-cache"
    />

    <gl-disclosure-dropdown-item
      v-if="allowed.edit"
      :item="editItem"
      data-testid="edit-upstream-repository"
    />

    <gl-disclosure-dropdown-item
      v-if="allowed.remove"
      :item="removeItem"
      data-testid="remove-upstream-repository"
    />
  </gl-disclosure-dropdown>
</template>
