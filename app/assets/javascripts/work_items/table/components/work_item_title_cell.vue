<script>
import {
  GlButton,
  GlFormInput,
  GlIcon,
  GlLoadingIcon,
  GlToastMixin,
  GlTooltipDirective,
} from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { titleInLinkSafeHtmlConfig } from '~/lib/dompurify';
import SafeHtml from '~/vue_shared/directives/safe_html';
import TooltipOnTruncate from '~/vue_shared/directives/tooltip_on_truncate';
import { TITLE_LENGTH_MAX } from '~/issues/constants';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { visitUrl } from '~/lib/utils/url_utility';
import WorkItemTypeIcon from '~/work_items/components/work_item_type_icon.vue';
import { updateWorkItemField } from '../utils';

export default {
  name: 'WorkItemTitleCell',
  components: {
    GlButton,
    GlFormInput,
    GlIcon,
    GlLoadingIcon,
    WorkItemTypeIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
    SafeHtml,
    TooltipOnTruncate,
  },
  mixins: [GlToastMixin, glFeatureFlagsMixin()],
  inject: {
    getWorkItemTypeConfiguration: {
      default: null,
    },
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    isActive: {
      type: Boolean,
      required: false,
      default: false,
    },
    detailPanelEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['set-active-item'],
  data() {
    return {
      isEditing: false,
      isSaving: false,
      editedTitle: '',
    };
  },
  computed: {
    isValid() {
      return this.editedTitle.trim().length > 0 && this.editedTitle.length <= TITLE_LENGTH_MAX;
    },
    workItemType() {
      return this.item.workItemType?.name;
    },
    workItemConfig() {
      return this.getWorkItemTypeConfiguration
        ? this.getWorkItemTypeConfiguration(this.workItemType)
        : {};
    },
    useIssueView() {
      return this.workItemConfig?.useIssueView;
    },
  },
  methods: {
    handleTitleClick(event) {
      if (event.metaKey || event.ctrlKey || event.shiftKey) {
        return;
      }

      event.preventDefault();

      // When detail panel is disabled (bulk edit mode or unsupported view), do nothing on regular click
      // The link's href will work for modifier-key clicks (cmd+click, ctrl+click, middle-click)
      if (!this.detailPanelEnabled) {
        return;
      }

      // Unsupported types (incidents, tickets, test cases) should navigate instead of opening drawer
      if (this.useIssueView) {
        visitUrl(this.item.webPath);
        return;
      }

      this.$emit('set-active-item', this.isActive ? null : this.item);
    },
    startEditing() {
      this.editedTitle = this.item.title;
      this.isEditing = true;
      this.$nextTick(() => {
        this.$refs.titleInput?.$el?.focus();
      });
    },
    cancelEditing() {
      this.isEditing = false;
      this.editedTitle = '';
      this.$nextTick(() => {
        this.$refs.editButton?.$el?.focus();
      });
    },
    async saveTitle() {
      if (!this.isValid || this.isSaving) return;

      const trimmedTitle = this.editedTitle.trim();

      if (trimmedTitle === this.item.title) {
        this.cancelEditing();
        return;
      }

      this.isSaving = true;

      try {
        await updateWorkItemField(this.$apollo, {
          id: this.item.id,
          input: { title: trimmedTitle },
          useWorkItemFeatures: this.glFeatures?.workItemFeaturesField,
        });
        this.cancelEditing();
      } catch (error) {
        this.$toast.show(s__('WorkItem|Something went wrong while updating the title.'));
        Sentry.captureException(error);
      } finally {
        this.isSaving = false;
      }
    },
    handleBlur() {
      if (!this.isEditing) return;
      this.saveTitle();
    },
    handleKeydown(event) {
      if (event.key === 'Enter') {
        event.preventDefault();
        this.saveTitle();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        this.cancelEditing();
      }
    },
  },
  TITLE_LENGTH_MAX,
  titleInLinkSafeHtmlConfig,
};
</script>

<template>
  <span
    class="gl-flex gl-items-center gl-gap-2"
    :class="{
      'gl-group': !isEditing,
      'gl-cursor-pointer': !isEditing,
    }"
    @click="!isEditing && handleTitleClick($event)"
  >
    <work-item-type-icon
      v-if="item.workItemType"
      :work-item-type="item.workItemType.name"
      :type-icon-name="item.workItemType.iconName"
      icon-variant="subtle"
      class="gl-shrink-0"
    />
    <gl-icon
      v-if="item.confidential"
      v-gl-tooltip
      :title="__('Confidential')"
      :aria-label="__('Confidential')"
      name="eye-slash"
      variant="warning"
      class="gl-shrink-0"
      data-testid="confidential-icon"
    />

    <template v-if="!isEditing">
      <a
        :href="item.webPath"
        class="gl-min-w-0 gl-font-bold gl-text-default hover:gl-text-default"
        data-testid="work-item-link"
        @click.stop="handleTitleClick"
      >
        <span
          v-safe-html:[$options.titleInLinkSafeHtmlConfig]="item.titleHtml"
          v-tooltip-on-truncate="item.title"
          dir="auto"
          class="gl-block gl-truncate"
          data-testid="work-item-title"
        ></span>
      </a>
      <gl-button
        ref="editButton"
        icon="pencil"
        category="tertiary"
        size="small"
        :aria-label="s__('WorkItem|Edit title')"
        class="gl-ml-auto gl-shrink-0 gl-opacity-0 gl-transition-opacity focus:gl-opacity-10 group-hover:gl-opacity-10"
        data-testid="edit-title-button"
        @click.stop="startEditing"
      />
    </template>

    <template v-else>
      <span class="gl-contents" @click.stop>
        <gl-form-input
          ref="titleInput"
          v-model="editedTitle"
          :state="isValid"
          :disabled="isSaving"
          :maxlength="$options.TITLE_LENGTH_MAX"
          class="-gl-ml-1 gl-min-w-0 gl-flex-grow !gl-px-1 !gl-py-2 !gl-text-sm"
          @keydown="handleKeydown"
          @blur="handleBlur"
        />
      </span>
      <gl-loading-icon v-if="isSaving" size="sm" inline class="gl-shrink-0" />
      <span v-if="isSaving" class="gl-sr-only" aria-live="polite">
        {{ s__('WorkItem|Saving title') }}
      </span>
    </template>
  </span>
</template>
