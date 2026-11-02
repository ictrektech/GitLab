<script>
import { GlCollapsibleListbox, GlLabel, GlLoadingIcon, GlPopover, GlToastMixin } from '@gitlab/ui';
import { debounce, difference, unionBy } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { isScopedLabel } from '~/lib/utils/common_utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import groupLabelsQuery from '~/sidebar/components/labels/labels_select_widget/graphql/group_labels.query.graphql';
import projectLabelsQuery from '~/sidebar/components/labels/labels_select_widget/graphql/project_labels.query.graphql';
import { findLabelsWidget, formatLabelForListbox } from '../../utils';
import { updateWorkItemField } from '../utils';

export default {
  name: 'WorkItemLabelsCell',
  components: {
    GlCollapsibleListbox,
    GlLabel,
    GlLoadingIcon,
    GlPopover,
  },
  mixins: [GlToastMixin, glFeatureFlagsMixin()],
  inject: {
    hasScopedLabelsFeature: {
      default: false,
    },
    isGroup: {
      default: false,
    },
    rootPageFullPath: {},
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
  apollo: {
    availableLabels: {
      query() {
        return this.isGroup ? groupLabelsQuery : projectLabelsQuery;
      },
      variables() {
        return {
          fullPath: this.rootPageFullPath,
          searchTerm: this.searchTerm,
        };
      },
      skip() {
        return !this.searchStarted;
      },
      update(data) {
        return data.namespace?.labels?.nodes ?? [];
      },
      result({ data }) {
        const labels = data?.namespace?.labels?.nodes || [];
        this.labelsCache = unionBy(this.labelsCache, labels, 'id');
      },
      error() {
        this.$toast.show(s__('WorkItem|Something went wrong when fetching labels.'));
      },
    },
  },
  data() {
    return {
      isEditing: false,
      isSaving: false,
      searchTerm: '',
      searchStarted: false,
      selectedLabelIds: [],
      availableLabels: [],
      labelsCache: [],
      maxVisibleLabels: 3,
    };
  },
  computed: {
    labels() {
      return findLabelsWidget(this.item)?.labels?.nodes || [];
    },
    allowsScopedLabels() {
      return Boolean(
        this.hasScopedLabelsFeature || findLabelsWidget(this.item)?.allowsScopedLabels,
      );
    },
    isLoadingLabels() {
      return this.$apollo.queries.availableLabels.loading;
    },
    listboxItems() {
      const formatted = this.availableLabels.map(formatLabelForListbox);

      if (this.selectedLabelIds.length === 0 || this.searchTerm || formatted.length === 0) {
        return formatted;
      }

      const selected = this.labelsCache
        .filter((l) => this.selectedLabelIds.includes(l.id))
        .map(formatLabelForListbox);

      if (selected.length === 0) {
        return formatted;
      }

      return [
        { text: s__('WorkItem|Selected'), options: selected },
        { text: s__('WorkItem|All'), textSrOnly: true, options: formatted },
      ];
    },
    selectedLabels() {
      if (!this.isEditing) {
        return this.labels;
      }
      return this.labelsCache.filter((l) => this.selectedLabelIds.includes(l.id));
    },
    visibleLabels() {
      return this.selectedLabels.slice(0, this.maxVisibleLabels);
    },
    hiddenLabels() {
      return this.selectedLabels.slice(this.maxVisibleLabels);
    },
    hasMoreLabels() {
      return this.hiddenLabels.length > 0;
    },
    moreLabelsText() {
      return `+${this.hiddenLabels.length}`;
    },
  },
  created() {
    this.debouncedSearch = debounce(this.search, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  },
  beforeDestroy() {
    this.debouncedSearch?.cancel();
  },
  methods: {
    handleCellClick() {
      if (!this.isEditing) {
        this.startEditing();
      }
    },
    startEditing() {
      this.selectedLabelIds = this.labels.map((l) => l.id);
      this.labelsCache = unionBy(this.labelsCache, this.labels, 'id');
      this.isEditing = true;
      this.searchStarted = true;
    },
    cancelEditing() {
      this.isEditing = false;
      this.searchTerm = '';
      this.selectedLabelIds = [];
    },
    async saveLabels() {
      if (this.isSaving) return;

      const currentLabelIds = this.labels.map((l) => l.id);
      const labelsToAdd = difference(this.selectedLabelIds, currentLabelIds);
      const labelsToRemove = difference(currentLabelIds, this.selectedLabelIds);

      const hasChanges = labelsToAdd.length > 0 || labelsToRemove.length > 0;
      if (!hasChanges) {
        this.cancelEditing();
        return;
      }

      this.isSaving = true;

      try {
        await updateWorkItemField(this.$apollo, {
          id: this.item.id,
          input: {
            labelsWidget: {
              addLabelIds: labelsToAdd,
              removeLabelIds: labelsToRemove,
            },
          },
          useWorkItemFeatures: this.glFeatures?.workItemFeaturesField,
        });
      } catch (error) {
        this.$toast.show(s__('WorkItem|Something went wrong while updating the labels.'));
        Sentry.captureException(error);
      } finally {
        this.isSaving = false;
        this.cancelEditing();
      }
    },
    handleSelect(labelIds) {
      this.selectedLabelIds = labelIds;
    },
    handleShown() {
      this.searchTerm = '';
      this.searchStarted = true;
    },
    handleHidden() {
      this.saveLabels();
    },
    search(term) {
      this.searchTerm = term;
    },
    scopedLabel(label) {
      return this.allowsScopedLabels && isScopedLabel(label);
    },
    labelFilterUrl(label) {
      return `?label_name[]=${encodeURIComponent(label.title)}`;
    },
  },
};
</script>

<template>
  <span
    class="gl-flex gl-w-full gl-items-center gl-gap-2 gl-overflow-hidden gl-px-4"
    :class="{
      'gl-cursor-pointer': !isEditing,
      'gl-py-3': labels.length > 0 || isEditing,
      'gl-py-5': labels.length === 0 && !isEditing,
    }"
    @click="handleCellClick"
  >
    <template v-if="!isEditing">
      <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-2">
        <gl-label
          v-for="label in visibleLabels"
          :key="label.id"
          :background-color="label.color"
          :title="label.title"
          :description="label.description"
          :scoped="scopedLabel(label)"
          :target="labelFilterUrl(label)"
          class="gl-shrink-0"
          data-testid="label-item"
          @click.stop
        />
        <span
          v-if="hasMoreLabels"
          :id="`more-labels-${item.id}`"
          class="gl-cursor-pointer gl-rounded-pill gl-bg-strong gl-px-3 gl-text-sm"
          data-testid="more-labels-button"
          @click.stop
        >
          {{ moreLabelsText }}
        </span>
        <gl-popover
          v-if="hasMoreLabels"
          :target="`more-labels-${item.id}`"
          triggers="hover focus"
          placement="bottom"
        >
          <div class="gl-flex gl-flex-wrap gl-gap-2">
            <gl-label
              v-for="label in hiddenLabels"
              :key="label.id"
              :background-color="label.color"
              :title="label.title"
              :description="label.description"
              :scoped="scopedLabel(label)"
              :target="labelFilterUrl(label)"
              class="gl-shrink-0"
              @click.stop
            />
          </div>
        </gl-popover>
      </span>
    </template>

    <template v-else>
      <gl-collapsible-listbox
        ref="listbox"
        :items="listboxItems"
        :selected="selectedLabelIds"
        :searching="isLoadingLabels"
        :header-text="s__('WorkItem|Select labels')"
        :reset-button-label="s__('WorkItem|Clear')"
        :no-results-text="s__('WorkItem|No matching results')"
        class="gl-w-full"
        block
        multiple
        start-opened
        searchable
        is-check-centered
        data-testid="labels-listbox"
        @select="handleSelect"
        @search="debouncedSearch"
        @shown="handleShown"
        @hidden="handleHidden"
        @reset="handleSelect([])"
      >
        <template #toggle="{ accessibilityAttributes }">
          <div
            role="button"
            tabindex="0"
            class="gl-flex gl-w-full gl-min-w-0 gl-cursor-pointer gl-items-center gl-gap-2 gl-text-left gl-text-sm"
            v-bind="accessibilityAttributes"
          >
            <gl-label
              v-for="label in visibleLabels"
              :key="label.id"
              :background-color="label.color"
              :title="label.title"
              :description="label.description"
              :scoped="scopedLabel(label)"
              :target="labelFilterUrl(label)"
              class="gl-shrink-0"
              data-testid="toggle-label-item"
              @click.stop
            />
            <span
              v-if="hasMoreLabels"
              class="gl-rounded-pill gl-bg-strong gl-px-3 gl-text-sm"
              data-testid="toggle-more-labels"
            >
              {{ moreLabelsText }}
            </span>
          </div>
        </template>
        <template #list-item="{ item: label }">
          <div class="gl-flex gl-items-center gl-gap-3">
            <span
              :style="{ background: label.color }"
              class="gl-border gl-h-3 gl-w-5 gl-shrink-0 gl-rounded-base gl-border-white"
            ></span>
            {{ label.text }}
          </div>
        </template>
      </gl-collapsible-listbox>
      <gl-loading-icon v-if="isSaving" size="sm" inline class="gl-shrink-0" />
    </template>
  </span>
</template>
