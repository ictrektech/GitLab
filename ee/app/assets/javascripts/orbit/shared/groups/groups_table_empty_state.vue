<script>
import { defineComponent } from 'vue';
import { GlButton } from '@gitlab/ui';
import { MINIMUM_SEARCH_LENGTH } from '~/graphql_shared/constants';
import { s__, sprintf } from '~/locale';
import { GROUP_FILTER_EXCLUDED } from './constants';

export default defineComponent({
  name: 'OrbitGroupsTableEmptyState',
  components: { GlButton },
  props: {
    noGroups: {
      type: Boolean,
      required: true,
    },
    search: {
      type: String,
      required: true,
    },
    serverSearch: {
      type: Boolean,
      required: true,
    },
    filter: {
      type: String,
      required: true,
    },
    newGroupPath: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['clear-search'],
  computed: {
    title() {
      if (this.search)
        return sprintf(s__('Orbit|No groups match “%{search}”'), { search: this.search }, false);
      if (this.filter === GROUP_FILTER_EXCLUDED) return s__('Orbit|No groups are excluded');
      return s__('Orbit|No groups have GitLab Orbit on');
    },
    // Gitlab::SQL::Pattern matches part of a name only from 3 characters.
    searchHint() {
      if (!this.serverSearch || this.search.length >= MINIMUM_SEARCH_LENGTH) {
        return s__('Orbit|Edit your search and try again.');
      }

      return sprintf(
        s__('Orbit|To find part of a group name, enter at least %{count} characters.'),
        {
          count: MINIMUM_SEARCH_LENGTH,
        },
      );
    },
  },
});
</script>

<template>
  <div class="gl-py-7 gl-text-center" data-testid="groups-empty">
    <template v-if="noGroups && newGroupPath">
      <p class="gl-mb-1 gl-font-bold">{{ s__('Orbit|No top-level groups yet') }}</p>
      <p class="gl-mb-4 gl-text-subtle">
        {{ s__('Orbit|GitLab Orbit indexes top-level groups. Create a group to start.') }}
      </p>
      <gl-button size="small" :href="newGroupPath">{{ s__('Orbit|New group') }}</gl-button>
    </template>
    <template v-else-if="noGroups">
      <p class="gl-mb-1 gl-font-bold">{{ s__('Orbit|No groups yet') }}</p>
      <p class="gl-mb-0 gl-text-subtle">
        {{ s__('Orbit|The groups where you have at least the Reporter role show here.') }}
      </p>
    </template>
    <template v-else>
      <p class="gl-mb-1 gl-font-bold">{{ title }}</p>
      <template v-if="search">
        <p class="gl-mb-4 gl-text-subtle" data-testid="groups-empty-search-hint">
          {{ searchHint }}
        </p>
        <gl-button size="small" @click="$emit('clear-search')">
          {{ s__('Orbit|Clear search') }}
        </gl-button>
      </template>
    </template>
  </div>
</template>
