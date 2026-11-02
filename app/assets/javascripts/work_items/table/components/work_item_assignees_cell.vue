<script>
import {
  GlAvatar,
  GlAvatarLink,
  GlAvatarsInline,
  GlCollapsibleListbox,
  GlLink,
  GlLoadingIcon,
  GlToastMixin,
  GlTooltipDirective,
  GlTruncate,
} from '@gitlab/ui';
import { debounce, unionBy, xor } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { __, n__, s__ } from '~/locale';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { userIsDisabled } from '~/ai/agents_utils';
import { FLOW_TRIGGER_EVENTS } from '~/vue_shared/constants';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import usersSearchQuery from '~/graphql_shared/queries/workspace_autocomplete_users.query.graphql';
import SidebarParticipant from '~/sidebar/components/assignees/sidebar_participant.vue';
import workItemEditMetadataQuery from '../graphql/work_item_edit_metadata.query.graphql';
import { findAssigneesWidget } from '../../utils';
import { updateWorkItemField } from '../utils';

const MAX_VISIBLE_ASSIGNEES = 3;
const AVATAR_SIZE = 16;

const formatUserForListbox = (user) => ({ ...user, value: user.id, text: user.name });

export default {
  name: 'WorkItemAssigneesCell',
  components: {
    GlAvatar,
    GlAvatarLink,
    GlAvatarsInline,
    GlCollapsibleListbox,
    GlLink,
    GlLoadingIcon,
    GlTruncate,
    SidebarParticipant,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin, glFeatureFlagsMixin()],
  inject: {
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
    users: {
      query: usersSearchQuery,
      variables() {
        return {
          fullPath: this.rootPageFullPath,
          search: this.searchTerm,
          isProject: !this.isGroup,
        };
      },
      skip() {
        return !this.searchStarted;
      },
      update(data) {
        return (this.isGroup ? data.groupNamespace?.users : data.namespace?.users) ?? [];
      },
      result({ data }) {
        const users = (this.isGroup ? data?.groupNamespace?.users : data?.namespace?.users) || [];
        this.usersCache = unionBy(users, this.usersCache, 'id');
      },
      error() {
        this.$toast.show(s__('WorkItem|Something went wrong when fetching users.'));
      },
    },
    editMetadata: {
      query: workItemEditMetadataQuery,
      variables() {
        return { id: this.item.id };
      },
      skip() {
        return !this.isEditing;
      },
      update(data) {
        return data.workItem;
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      isEditing: false,
      isSaving: false,
      searchTerm: '',
      searchStarted: false,
      selectedAssigneeIds: [],
      users: [],
      usersCache: [],
      editMetadata: null,
    };
  },
  computed: {
    assignees() {
      return findAssigneesWidget(this.item)?.assignees?.nodes || [];
    },
    // The list response does not include this, so it is fetched when editing starts. Falling back
    // to multi-select is safe: the server keeps only the first assignee when the work item allows one.
    allowsMultipleAssignees() {
      return findAssigneesWidget(this.editMetadata)?.allowsMultipleAssignees ?? true;
    },
    isLoading() {
      return this.$apollo.queries.users.loading || this.$apollo.queries.editMetadata.loading;
    },
    listboxSelected() {
      return this.allowsMultipleAssignees
        ? this.selectedAssigneeIds
        : (this.selectedAssigneeIds[0] ?? null);
    },
    listboxItems() {
      const formatted = this.users.map(formatUserForListbox);

      if (this.selectedAssigneeIds.length === 0 || this.searchTerm || formatted.length === 0) {
        return formatted;
      }

      const selected = this.selectedAssignees.map(formatUserForListbox);
      const unselected = formatted.filter(({ value }) => !this.selectedAssigneeIds.includes(value));

      return [
        { text: s__('WorkItem|Selected'), options: selected },
        { text: __('All users'), textSrOnly: true, options: unselected },
      ];
    },
    selectedAssignees() {
      if (!this.isEditing) {
        return this.assignees;
      }
      return this.selectedAssigneeIds
        .map((id) => this.usersCache.find((user) => user.id === id))
        .filter(Boolean);
    },
    // Only one assignee is named, since more than one would not fit the column.
    singleAssignee() {
      return this.selectedAssignees.length === 1 ? this.selectedAssignees[0] : null;
    },
    hiddenAssigneesText() {
      const count = this.selectedAssignees.length - MAX_VISIBLE_ASSIGNEES;
      return n__('%d additional assignee', '%d additional assignees', count);
    },
    headerText() {
      return this.allowsMultipleAssignees ? __('Select assignees') : __('Select assignee');
    },
  },
  created() {
    this.debouncedSearch = debounce(this.search, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  },
  beforeDestroy() {
    this.debouncedSearch?.cancel();
  },
  methods: {
    handleCellClick(event) {
      // Avatars and the name are links to the user, so clicking them should not start editing.
      if (event.target.closest('a')) return;
      if (!this.isEditing) {
        this.startEditing();
      }
    },
    startEditing() {
      this.selectedAssigneeIds = this.assignees.map((user) => user.id);
      this.usersCache = unionBy(this.usersCache, this.assignees, 'id');
      this.isEditing = true;
      this.searchStarted = true;
    },
    cancelEditing() {
      this.isEditing = false;
      this.searchTerm = '';
      this.selectedAssigneeIds = [];
    },
    async saveAssignees() {
      if (this.isSaving) return;

      const currentAssigneeIds = this.assignees.map((user) => user.id);
      if (xor(currentAssigneeIds, this.selectedAssigneeIds).length === 0) {
        this.cancelEditing();
        return;
      }

      this.isSaving = true;

      try {
        await updateWorkItemField(this.$apollo, {
          id: this.item.id,
          input: {
            assigneesWidget: {
              assigneeIds: this.selectedAssigneeIds,
            },
          },
          useWorkItemFeatures: this.glFeatures?.workItemFeaturesField,
        });
      } catch (error) {
        this.$toast.show(s__('WorkItem|Something went wrong while updating the assignees.'));
        Sentry.captureException(error);
      } finally {
        this.isSaving = false;
        this.cancelEditing();
      }
    },
    handleSelect(value) {
      const ids = this.allowsMultipleAssignees ? value : [value].filter(Boolean);
      // Users who cannot be assigned (such as some AI agents) can still be unassigned.
      this.selectedAssigneeIds = ids.filter(
        (id) => this.selectedAssigneeIds.includes(id) || !this.isUserDisabled(id),
      );
    },
    isUserDisabled(id) {
      const user = this.usersCache.find((u) => u.id === id);
      return Boolean(user && userIsDisabled(user, FLOW_TRIGGER_EVENTS.ASSIGN));
    },
    handleShown() {
      this.searchTerm = '';
      this.searchStarted = true;
    },
    handleHidden() {
      this.saveAssignees();
    },
    search(term) {
      this.searchTerm = term;
    },
  },
  AVATAR_SIZE,
  MAX_VISIBLE_ASSIGNEES,
};
</script>

<template>
  <span
    class="gl-flex gl-w-full gl-items-center gl-gap-2 gl-overflow-hidden gl-px-4"
    :class="{
      'gl-cursor-pointer': !isEditing,
      'gl-py-3': assignees.length > 0 || isEditing,
      'gl-py-5': assignees.length === 0 && !isEditing,
    }"
    data-testid="cell-assignees"
    @click="handleCellClick"
  >
    <span v-if="!isEditing" class="gl-flex gl-min-w-0 gl-items-center gl-gap-2">
      <gl-avatars-inline
        v-if="assignees.length"
        :avatars="assignees"
        :avatar-size="$options.AVATAR_SIZE"
        :max-visible="$options.MAX_VISIBLE_ASSIGNEES"
        :badge-sr-only-text="hiddenAssigneesText"
        badge-tooltip-prop="name"
        collapsed
        class="avatars-inline-compact gl-shrink-0"
        data-testid="assignee-avatars"
      >
        <template #avatar="{ avatar }">
          <gl-avatar-link v-gl-tooltip :href="avatar.webPath" :title="avatar.name">
            <gl-avatar :src="avatar.avatarUrl" :alt="avatar.name" :size="$options.AVATAR_SIZE" />
          </gl-avatar-link>
        </template>
      </gl-avatars-inline>
      <gl-link
        v-if="singleAssignee"
        :href="singleAssignee.webPath"
        class="gl-group gl-min-w-0 gl-text-default hover:gl-text-default"
        data-testid="assignee-name-link"
      >
        <gl-truncate :text="singleAssignee.name" class="group-hover:gl-underline" />
      </gl-link>
    </span>

    <template v-else>
      <gl-collapsible-listbox
        :items="listboxItems"
        :selected="listboxSelected"
        :multiple="allowsMultipleAssignees"
        :searching="isLoading"
        :header-text="headerText"
        :reset-button-label="s__('WorkItem|Clear')"
        :no-results-text="s__('WorkItem|No matching results')"
        class="gl-w-full"
        block
        start-opened
        searchable
        is-check-centered
        data-testid="assignees-listbox"
        @select="handleSelect"
        @search="debouncedSearch"
        @shown="handleShown"
        @hidden="handleHidden"
        @reset="handleSelect(allowsMultipleAssignees ? [] : null)"
      >
        <template #toggle="{ accessibilityAttributes }">
          <div
            role="button"
            tabindex="0"
            class="gl-relative gl-flex gl-w-full gl-min-w-0 gl-cursor-pointer gl-items-center gl-gap-2 gl-text-left gl-text-sm"
            v-bind="accessibilityAttributes"
          >
            <gl-avatars-inline
              v-if="selectedAssignees.length"
              :avatars="selectedAssignees"
              :avatar-size="$options.AVATAR_SIZE"
              :max-visible="$options.MAX_VISIBLE_ASSIGNEES"
              :badge-sr-only-text="hiddenAssigneesText"
              badge-tooltip-prop="name"
              collapsed
              class="avatars-inline-compact gl-shrink-0"
              data-testid="toggle-assignees"
            >
              <template #avatar="{ avatar }">
                <gl-avatar
                  v-gl-tooltip
                  :src="avatar.avatarUrl"
                  :alt="avatar.name"
                  :title="avatar.name"
                  :size="$options.AVATAR_SIZE"
                />
              </template>
            </gl-avatars-inline>
            <gl-truncate v-if="singleAssignee" :text="singleAssignee.name" />
            <gl-loading-icon
              v-if="isSaving"
              size="sm"
              inline
              class="gl-absolute gl-right-0 gl-top-1/2 -gl-translate-y-1/2"
            />
          </div>
        </template>
        <template #list-item="{ item: user }">
          <sidebar-participant :user="user" />
        </template>
      </gl-collapsible-listbox>
    </template>
  </span>
</template>
