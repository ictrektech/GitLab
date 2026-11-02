<script>
import { defineComponent } from 'vue';
import {
  GlCollapsibleListbox,
  GlDisclosureDropdown,
  GlLoadingIcon,
  GlSearchBoxByType,
} from '@gitlab/ui';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { n__, s__, sprintf } from '~/locale';
import { ACTION_PROGRESS_LABELS } from './constants';

export default defineComponent({
  name: 'OrbitGroupsTableToolbar',
  components: {
    GlCollapsibleListbox,
    GlDisclosureDropdown,
    GlLoadingIcon,
    GlSearchBoxByType,
  },
  props: {
    search: {
      type: String,
      required: true,
    },
    filter: {
      type: String,
      required: true,
    },
    filterOptions: {
      type: Array,
      required: true,
    },
    selectable: {
      type: Boolean,
      required: true,
    },
    selectedCount: {
      type: Number,
      required: true,
    },
    actionItems: {
      type: Array,
      required: true,
    },
    bulkProgress: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['search', 'filter', 'action'],
  computed: {
    isRunning() {
      return this.bulkProgress !== null;
    },
    filterToggleText() {
      const option = this.filterOptions.find(({ value }) => value === this.filter);
      return sprintf(s__('Orbit|GitLab Orbit state: %{state}'), { state: option.text });
    },
    selectedCountText() {
      return n__('Orbit|%d group selected', 'Orbit|%d groups selected', this.selectedCount);
    },
    progressText() {
      const { action, done, total } = this.bulkProgress;
      return sprintf(s__('Orbit|%{action}: %{done} of %{total} done'), {
        action: ACTION_PROGRESS_LABELS[action],
        done,
        total,
      });
    },
  },
  searchDebounceMs: DEFAULT_DEBOUNCE_AND_THROTTLE_MS,
});
</script>

<template>
  <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
    <gl-search-box-by-type
      :value="search"
      :placeholder="s__('Orbit|Search groups')"
      :debounce="$options.searchDebounceMs"
      :disabled="isRunning"
      class="gl-w-full sm:gl-w-30"
      data-testid="groups-search"
      @input="$emit('search', $event)"
    />
    <gl-collapsible-listbox
      :items="filterOptions"
      :selected="filter"
      :toggle-text="filterToggleText"
      :disabled="isRunning"
      data-testid="groups-filter"
      @select="$emit('filter', $event)"
    />
    <template v-if="selectable">
      <div class="gl-flex gl-items-center gl-gap-3 sm:gl-ml-auto" aria-live="polite">
        <span v-if="isRunning" class="gl-flex gl-items-center gl-gap-2 gl-text-subtle">
          <gl-loading-icon size="sm" inline />
          {{ progressText }}
        </span>
        <span v-else-if="selectedCount" class="gl-text-subtle">
          {{ selectedCountText }}
        </span>
      </div>
      <gl-disclosure-dropdown
        :items="actionItems"
        :toggle-text="s__('Orbit|Actions')"
        :disabled="isRunning || !actionItems.length"
        placement="bottom-end"
        data-testid="groups-actions"
        @action="$emit('action', $event.value)"
      />
    </template>
  </div>
</template>
