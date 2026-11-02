<script>
import { defineComponent } from 'vue';
import {
  GlAlert,
  GlAvatar,
  GlBadge,
  GlButton,
  GlFormCheckbox,
  GlKeysetPagination,
  GlLink,
  GlLoadingIcon,
  GlSkeletonLoader,
  GlSprintf,
  GlTable,
  GlTooltipDirective,
} from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { GROUP_FILTER_ALL } from './constants';
import GroupAreasPopover from './group_areas_popover.vue';
import GroupsTableEmptyState from './groups_table_empty_state.vue';
import GroupsTableToolbar from './groups_table_toolbar.vue';
import { hasIndexingError, indexStatusLabel, indexingAreasFor, isIndexingNow } from './utils';

export default defineComponent({
  name: 'OrbitGroupsTable',
  components: {
    GlAlert,
    GlAvatar,
    GlBadge,
    GlButton,
    GlFormCheckbox,
    GlKeysetPagination,
    GlLink,
    GlLoadingIcon,
    GlSkeletonLoader,
    GlSprintf,
    GlTable,
    GroupAreasPopover,
    GroupsTableEmptyState,
    GroupsTableToolbar,
    TimeAgoTooltip,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      required: true,
    },
    groups: {
      type: Array,
      required: true,
    },
    selectable: {
      type: Boolean,
      required: false,
      default: true,
    },
    actionsColumn: {
      type: Boolean,
      required: false,
      default: false,
    },
    selectedPaths: {
      type: Array,
      required: true,
    },
    actionItems: {
      type: Array,
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
    filterOptions: {
      type: Array,
      required: true,
    },
    pageInfo: {
      type: Object,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    loadError: {
      type: String,
      required: false,
      default: null,
    },
    bulkProgress: {
      type: Object,
      required: false,
      default: null,
    },
    newGroupPath: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['search', 'filter', 'select', 'action', 'prev', 'next', 'retry'],
  computed: {
    rows() {
      return this.groups.map((group, index) => ({
        ...group,
        canSelect: group.allowedActions.length > 0,
        isSelected: this.selectedPaths.includes(group.fullPath),
        isPending: Boolean(this.bulkProgress?.pendingPaths.includes(group.fullPath)),
        showPath: group.fullPath !== group.name,
        selectLabel: sprintf(s__('Orbit|Select %{group}'), { group: group.fullPath }, false),
        statusLabel: indexStatusLabel(group),
        hasIndexingError: hasIndexingError(group),
        isIndexing: isIndexingNow(group),
        areas: indexingAreasFor(group),
        areasId: `orbit-group-areas-${index}`,
      }));
    },
    selectablePaths() {
      return this.rows.filter((row) => row.canSelect).map((row) => row.fullPath);
    },
    isRunning() {
      return this.bulkProgress !== null;
    },
    allSelected() {
      return (
        this.selectablePaths.length > 0 &&
        this.selectablePaths.every((path) => this.selectedPaths.includes(path))
      );
    },
    someSelected() {
      return this.selectedPaths.length > 0 && !this.allSelected;
    },
    hasNoGroups() {
      return (
        !this.isLoading &&
        !this.loadError &&
        !this.groups.length &&
        !this.search &&
        this.filter === GROUP_FILTER_ALL &&
        !this.pageInfo.hasPreviousPage
      );
    },
    showPagination() {
      return this.pageInfo.hasNextPage || this.pageInfo.hasPreviousPage;
    },
    fields() {
      return [
        ...(this.selectable ? [{ key: 'select', label: '', thClass: 'gl-w-5' }] : []),
        { key: 'name', label: s__('Orbit|Group') },
        { key: 'state', label: s__('Orbit|GitLab Orbit state') },
        { key: 'status', label: s__('Orbit|Index status') },
        ...(this.actionsColumn ? [{ key: 'actions', label: s__('Orbit|Actions') }] : []),
      ].map((field) => ({ ...field, tdClass: '!gl-align-middle' }));
    },
  },
  methods: {
    toggleGroup(fullPath, checked) {
      const otherPaths = this.selectedPaths.filter((path) => path !== fullPath);
      this.$emit('select', checked ? [...otherPaths, fullPath] : otherPaths);
    },
    toggleAll(checked) {
      this.$emit('select', checked ? this.selectablePaths : []);
    },
  },
});
</script>

<template>
  <section class="gl-flex gl-flex-col gl-gap-4" aria-labelledby="orbit-groups-heading">
    <div>
      <h2 id="orbit-groups-heading" class="gl-heading-4 gl-mb-1">{{ title }}</h2>
      <p class="gl-mb-0 gl-text-subtle">{{ description }}</p>
    </div>

    <groups-table-toolbar
      v-if="!hasNoGroups"
      :search="search"
      :filter="filter"
      :filter-options="filterOptions"
      :selectable="selectable"
      :selected-count="selectedPaths.length"
      :action-items="actionItems"
      :bulk-progress="bulkProgress"
      @search="$emit('search', $event)"
      @filter="$emit('filter', $event)"
      @action="$emit('action', $event)"
    />

    <gl-alert
      v-if="loadError"
      variant="danger"
      :title="s__('Orbit|Could not load groups')"
      :dismissible="false"
      :primary-button-text="s__('Orbit|Try again')"
      data-testid="groups-load-error"
      @primary-action="$emit('retry')"
    >
      {{ loadError }}
    </gl-alert>

    <template v-else>
      <gl-table
        :items="rows"
        :fields="fields"
        :busy="isLoading"
        primary-key="fullPath"
        responsive
        show-empty
        class="gl-mb-0"
        data-testid="groups-table"
      >
        <template #table-busy>
          <gl-skeleton-loader :lines="4" :width="600" equal-width-lines />
        </template>

        <template #head(select)>
          <gl-form-checkbox
            class="gl-min-h-5"
            :checked="allSelected"
            :indeterminate="someSelected"
            :disabled="isRunning || !selectablePaths.length"
            :aria-label="s__('Orbit|Select all groups on this page')"
            data-testid="select-all-groups"
            @change="toggleAll"
          />
        </template>

        <template #head(actions)="{ label }">
          <span class="gl-sr-only">{{ label }}</span>
        </template>

        <template #cell(select)="{ item }">
          <gl-form-checkbox
            v-if="item.canSelect"
            class="gl-min-h-5"
            :checked="item.isSelected"
            :disabled="isRunning"
            :aria-label="item.selectLabel"
            data-testid="select-group"
            @change="toggleGroup(item.fullPath, $event)"
          />
        </template>

        <template #cell(name)="{ item }">
          <span class="gl-flex gl-items-center gl-gap-3 gl-whitespace-nowrap">
            <gl-avatar
              :src="item.avatarUrl"
              :entity-name="item.name"
              :size="24"
              shape="rect"
              :alt="''"
            />
            <span class="gl-flex gl-flex-col">
              <gl-link :href="item.webPath" class="gl-font-bold gl-text-default">
                {{ item.name }}
              </gl-link>
              <span v-if="item.showPath" class="gl-text-sm gl-text-subtle">{{
                item.fullPath
              }}</span>
            </span>
          </span>
        </template>

        <template #cell(state)="{ item }">
          <span v-if="item.isPending" class="gl-flex gl-items-center gl-gap-2 gl-text-subtle">
            <gl-loading-icon size="sm" inline />
            {{ s__('Orbit|Updating…') }}
          </span>
          <span v-else class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
            <gl-badge v-if="item.isOn" variant="success" icon="status-success">
              {{ s__('Orbit|On') }}
            </gl-badge>
            <gl-badge v-else variant="neutral">{{ s__('Orbit|Off') }}</gl-badge>
            <gl-badge
              v-if="item.trialBadge"
              :variant="item.trialBadge.variant"
              :icon="item.trialBadge.icon"
              data-testid="group-trial-badge"
            >
              {{ item.trialBadge.text }}
            </gl-badge>
            <gl-badge v-if="item.isExcluded" variant="warning">{{
              s__('Orbit|Excluded')
            }}</gl-badge>
            <gl-badge v-if="item.failure" variant="danger" icon="error">
              {{ s__('Orbit|Update failed') }}
            </gl-badge>
            <gl-button
              v-if="item.note"
              v-gl-tooltip
              :title="item.note"
              :aria-label="item.note"
              category="tertiary"
              size="small"
              icon="information-o"
              data-testid="group-note"
            />
          </span>
        </template>

        <template #cell(status)="{ item }">
          <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-2">
            <span
              class="gl-inline-flex gl-items-center gl-gap-2 gl-whitespace-nowrap"
              :class="{ 'gl-text-danger': item.hasIndexingError }"
            >
              <gl-loading-icon v-if="item.isIndexing" size="sm" inline />
              {{ item.statusLabel }}
            </span>
            <span v-if="item.isOn && item.enabledAt" class="gl-whitespace-nowrap gl-text-subtle">
              ·
              <gl-sprintf :message="s__('Orbit|Turned on %{time}')">
                <template #time><time-ago-tooltip :time="item.enabledAt" /></template>
              </gl-sprintf>
            </span>
            <group-areas-popover
              v-if="item.areas.length"
              :toggle-id="item.areasId"
              :group-name="item.name"
              :areas="item.areas"
            />
          </span>
        </template>

        <template v-if="actionsColumn" #cell(actions)="{ item }">
          <slot name="actions" :group="item"></slot>
        </template>

        <template #empty>
          <groups-table-empty-state
            :no-groups="hasNoGroups"
            :search="search"
            :server-search="serverSearch"
            :filter="filter"
            :new-group-path="newGroupPath"
            @clear-search="$emit('search', '')"
          />
        </template>
      </gl-table>

      <div class="gl-flex gl-flex-wrap gl-items-start gl-justify-between gl-gap-4">
        <p class="gl-mb-0 gl-text-sm gl-text-subtle">
          {{
            s__(
              'Orbit|A group is indexed when Core, Planning, Code review, CI/CD, Source code, and Security are all indexed.',
            )
          }}
        </p>
        <gl-keyset-pagination
          v-if="showPagination"
          v-bind="pageInfo"
          :disabled="isRunning || isLoading"
          :prev-text="__('Previous')"
          :next-text="__('Next')"
          @prev="$emit('prev', $event)"
          @next="$emit('next', $event)"
        />
      </div>
    </template>
  </section>
</template>
