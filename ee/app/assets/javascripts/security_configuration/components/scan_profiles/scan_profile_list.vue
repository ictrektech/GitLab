<script>
import { GlButton, GlIcon, GlSearchBoxByType } from '@gitlab/ui';
import { s__, n__, sprintf } from '~/locale';
import { SCAN_PROFILE_I18N } from '~/security_configuration/constants';
import InsufficientPermissionsPopover from './insufficient_permissions_popover.vue';
import { managedByLabel } from './utils';

export default {
  name: 'ScanProfileList',
  components: {
    GlButton,
    GlIcon,
    GlSearchBoxByType,
    InsufficientPermissionsPopover,
  },
  inject: {
    rootGroupName: { default: '' },
  },
  props: {
    profiles: {
      type: Array,
      required: true,
    },
    selectedId: {
      type: String,
      required: false,
      default: '',
    },
    canCreate: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select', 'create'],
  data() {
    return {
      searchTerm: '',
    };
  },
  computed: {
    filteredProfiles() {
      const q = this.searchTerm.trim().toLowerCase();
      if (!q) return this.profiles;
      return this.profiles.filter(({ name, description }) => {
        return (
          (name ?? '').toLowerCase().includes(q) || (description ?? '').toLowerCase().includes(q)
        );
      });
    },
    hasSearchQuery() {
      return this.searchTerm.trim().length > 0;
    },
    showNoResults() {
      return this.profiles.length > 0 && this.hasSearchQuery && this.filteredProfiles.length === 0;
    },
  },
  SCAN_PROFILE_I18N,
  i18n: {
    newProfile: s__('ScanProfiles|Create new profile'),
    emptyState: s__('SecurityConfiguration|There are no profiles for this scanner yet.'),
    searchPlaceholder: s__('ScanProfiles|Search profiles...'),
    noResults: s__('ScanProfiles|No profiles match your search.'),
  },
  methods: {
    managedByLabel,
    projectCountLabel(count) {
      return sprintf(
        n__(
          'SecurityConfiguration|%{count} project',
          'SecurityConfiguration|%{count} projects',
          count,
        ),
        { count },
      );
    },
  },
};
</script>

<template>
  <div>
    <div class="gl-mb-3 gl-mr-5">
      <gl-search-box-by-type
        v-model="searchTerm"
        :placeholder="$options.i18n.searchPlaceholder"
        data-testid="scan-profile-search"
      />
    </div>
    <p v-if="!profiles.length" class="gl-text-subtle" data-testid="scan-profile-drawer-empty">
      {{ $options.i18n.emptyState }}
    </p>
    <p
      v-if="showNoResults"
      class="gl-my-5 gl-mr-5 gl-text-subtle"
      aria-live="polite"
      data-testid="scan-profile-list-no-results"
    >
      {{ $options.i18n.noResults }}
    </p>
    <ul class="gl-m-0 gl-list-none gl-p-0" data-testid="scan-profile-list">
      <li v-for="profile in filteredProfiles" :key="profile.id" class="gl-mr-5">
        <button
          type="button"
          class="gl-w-full gl-cursor-pointer gl-rounded-base gl-border-0 gl-bg-transparent gl-px-4 gl-py-3 gl-text-left"
          :class="{ '!gl-bg-feedback-info': profile.id === selectedId }"
          :aria-current="profile.id === selectedId ? 'true' : null"
          data-testid="scan-profile-list-item"
          @click="$emit('select', profile.id)"
        >
          <span class="gl-block gl-font-bold gl-text-default">{{ profile.name }}</span>
          <span class="gl-mt-1 gl-line-clamp-2 gl-text-sm gl-text-subtle">
            {{ profile.description }}
          </span>
          <span class="gl-mt-2 gl-flex gl-items-center gl-gap-3 gl-text-sm gl-text-subtle">
            <span class="gl-flex gl-items-center gl-gap-2">
              <gl-icon name="user" :size="12" />
              {{ managedByLabel(profile, rootGroupName) }}
            </span>
            <span
              class="gl-flex gl-items-center gl-gap-2"
              data-testid="scan-profile-list-item-project-count"
            >
              <gl-icon name="project" :size="12" />
              <span aria-hidden="true">{{ profile.projectCount }}</span>
              <span class="gl-sr-only">{{ projectCountLabel(profile.projectCount) }}</span>
            </span>
          </span>
        </button>
      </li>
    </ul>
    <div ref="newWrapper" class="gl-mr-5 gl-mt-3" data-testid="scan-profile-new-wrapper">
      <gl-button
        icon="plus"
        variant="confirm"
        category="secondary"
        class="gl-w-full"
        :disabled="!canCreate"
        data-testid="scan-profile-new-button"
        @click="$emit('create')"
      >
        {{ $options.i18n.newProfile }}
      </gl-button>
      <insufficient-permissions-popover
        v-if="!canCreate"
        :target="() => $refs.newWrapper"
        :description="$options.SCAN_PROFILE_I18N.noCreatePermission"
      />
    </div>
  </div>
</template>
