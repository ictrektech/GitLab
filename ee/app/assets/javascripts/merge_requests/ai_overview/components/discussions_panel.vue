<script>
import {
  GlAnimatedChevronLgDownUpIcon,
  GlButton,
  GlIcon,
  GlLink,
  GlLoadingIcon,
  GlTooltipDirective,
} from '@gitlab/ui';
import { produce } from 'immer';
import { uniqueId } from 'lodash-es';
import Api from '~/api';
import { __, sprintf } from '~/locale';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { joinPaths } from '~/lib/utils/url_utility';
import { withLinkedFileUrlParams } from '~/rapid_diffs/utils/linked_file';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import FileIcon from '~/vue_shared/components/file_icon.vue';
import discussionsQuery from '../queries/mr_ai_overview_discussions.query.graphql';
import createNoteMutation from '../queries/mr_ai_overview_create_note.mutation.graphql';
import toggleResolveMutation from '../queries/mr_ai_overview_toggle_resolve.mutation.graphql';
import ConversationForm from './conversation_form.vue';
import ConversationNote from './conversation_note.vue';

const DIFF_REFS = ['baseSha', 'startSha', 'headSha'];
const NEW_COMMENT = Symbol('newComment');

// The design's snippet is a few lines: the suggested change, or else the lines the comment is on.
const SNIPPET_MAX_LINES = 6;
const SNIPPET_CONTEXT_LINES = 3;
// The same line backgrounds as a suggestion diff; the theme class on the snippet scopes the variables.
const SNIPPET_LINE_TYPES = {
  old: { sign: '-', classes: 'gl-bg-[var(--code-old-diff-background-color)]' },
  new: { sign: '+', classes: 'gl-bg-[var(--code-new-diff-background-color)]' },
  context: { sign: ' ', classes: 'gl-text-subtle' },
};

const contentLines = (content, type) =>
  content
    .replace(/\n$/, '')
    .split('\n')
    .map((text) => ({ type, text }));

const FILTERS = {
  all: () => true,
  action: (discussion) => discussion.isUnresolved,
  people: (discussion) => !discussion.isAgent,
  agents: (discussion) => discussion.isAgent,
};

export default {
  name: 'DiscussionsPanel',
  NEW_COMMENT,
  components: {
    ConversationForm,
    ConversationNote,
    FileIcon,
    GlAnimatedChevronLgDownUpIcon,
    GlButton,
    GlIcon,
    GlLink,
    GlLoadingIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['projectPath', 'iid'],
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      connection: null,
      hasError: false,
      isLoadingMore: false,
      filter: null,
      replyingTo: null,
      commentFormKey: 0,
      submittingTo: null,
      resolvingIds: [],
      applyingIds: [],
      isExpanded: null,
      contentId: uniqueId('ai-overview-conversations-'),
    };
  },
  apollo: {
    connection: {
      query: discussionsQuery,
      variables() {
        return { projectPath: this.projectPath, iid: this.iid };
      },
      update: (data) => data?.project?.mergeRequest?.discussionsWithActivity,
      // Decided once, so resolving the last open thread does not collapse the card under the user.
      result({ loading }) {
        if (!loading) this.isExpanded ??= this.hasError || this.openCount > 0;
      },
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isInitialLoading() {
      return this.$apollo.queries.connection.loading && !this.connection;
    },
    canCreateNote() {
      return this.mergeRequest.userPermissions.createNote;
    },
    canApplySuggestions() {
      return this.mergeRequest.userPermissions.pushToSourceBranch;
    },
    discussions() {
      return (this.connection?.nodes ?? [])
        .map((discussion) => this.buildDiscussion(discussion))
        .filter(Boolean);
    },
    openCount() {
      return this.discussions.filter(FILTERS.action).length;
    },
    // Opens on Needs action, unless nothing needs action, in which case the card would be empty.
    activeFilter: {
      get() {
        return this.filter ?? (this.openCount ? 'action' : 'all');
      },
      set(filter) {
        this.filter = filter;
      },
    },
    filteredDiscussions() {
      return this.discussions.filter(FILTERS[this.activeFilter]);
    },
    openText() {
      return sprintf(__('%{count} open'), { count: this.openCount });
    },
    // Open while loading, and to show an error.
    isOpen() {
      return this.isExpanded ?? true;
    },
    toggleLabel() {
      return this.isOpen ? __('Collapse') : __('Expand');
    },
  },
  methods: {
    buildDiscussion({
      id,
      replyId,
      resolvable,
      resolved,
      userPermissions,
      truncatedDiffLines,
      notes,
    }) {
      const [note, ...replies] = notes.nodes;
      if (!note) return null;

      const canResolve = userPermissions.resolveNote;
      const isUnresolved = resolvable && !resolved;
      const suggestions = note.suggestions?.nodes ?? [];
      const pendingSuggestionIds = suggestions
        .filter((suggestion) => !suggestion.applied)
        .map((suggestion) => suggestion.id);
      const location = this.diffLocation(note);

      return {
        id,
        replyId,
        note,
        replies,
        resolved,
        canResolve,
        isUnresolved,
        hasActions: isUnresolved && (this.canCreateNote || canResolve),
        canReopen: resolved && canResolve,
        isResolving: this.resolvingIds.includes(id),
        isApplying: this.applyingIds.includes(id),
        isAgent: Boolean(note.author?.bot),
        snippet: this.snippet(suggestions, truncatedDiffLines),
        pendingSuggestionIds,
        // A suggestion on an older diff no longer matches the code, so it cannot be applied.
        canApply:
          this.canApplySuggestions &&
          isUnresolved &&
          !location.isOutdated &&
          pendingSuggestionIds.length > 0,
        ...location,
      };
    },
    snippet(suggestions, diffLines) {
      const lines = suggestions.length
        ? suggestions.flatMap(({ fromContent, toContent }) => [
            ...contentLines(fromContent, 'old'),
            ...contentLines(toContent, 'new'),
          ])
        : (diffLines ?? [])
            .filter(({ type }) => type === null || type === 'old' || type === 'new')
            .slice(-SNIPPET_CONTEXT_LINES)
            // The diff line's text starts with its own +, - or space.
            .map(({ type, text }) => ({ type: type ?? 'context', text: text.slice(1) }));

      return lines.slice(0, SNIPPET_MAX_LINES).map((line) => ({
        ...line,
        ...SNIPPET_LINE_TYPES[line.type],
      }));
    },
    // The new overview replaces the classic thread list, so a diff thread links to its
    // place on the Changes tab rather than to the note's anchor on this page.
    diffLocation({ id, position }) {
      if (!position) return {};

      const line = position.newLine ?? position.oldLine;
      const location = line ? `${position.filePath}:${line}` : position.filePath;

      // Same test as DiffNote#active?: a thread on an older diff is not on the Changes tab.
      const isOutdated = DIFF_REFS.some(
        (ref) => position.diffRefs[ref] !== this.mergeRequest.diffRefs?.[ref],
      );
      if (isOutdated) return { location, filePath: position.filePath, isOutdated };

      return {
        location,
        filePath: position.filePath,
        diffHref: withLinkedFileUrlParams(joinPaths(this.mergeRequest.webPath, 'diffs'), {
          oldPath: position.oldPath,
          newPath: position.newPath,
          hash: `note_${getIdFromGraphQLId(id)}`,
        }).toString(),
      };
    },
    async loadMore() {
      this.isLoadingMore = true;
      try {
        await this.$apollo.queries.connection.fetchMore({
          variables: { after: this.connection.pageInfo.endCursor },
          updateQuery: (previous, { fetchMoreResult }) =>
            produce(fetchMoreResult, (draft) => {
              draft.project.mergeRequest.discussionsWithActivity.nodes.unshift(
                ...previous.project.mergeRequest.discussionsWithActivity.nodes,
              );
            }),
        });
      } catch (error) {
        createAlert({ message: this.$options.i18n.loadError, captureError: true, error });
      } finally {
        this.isLoadingMore = false;
      }
    },
    async toggleResolve({ id, resolved }) {
      this.resolvingIds = [...this.resolvingIds, id];
      try {
        const { data } = await this.$apollo.mutate({
          mutation: toggleResolveMutation,
          variables: { id, resolve: !resolved },
        });
        const [message] = data.discussionToggleResolve.errors;
        if (message) throw new Error(message);
      } catch (error) {
        createAlert({ message: this.$options.i18n.resolveError, captureError: true, error });
      } finally {
        this.resolvingIds = this.resolvingIds.filter((resolvingId) => resolvingId !== id);
      }
    },
    async createNote({ body, discussionId }) {
      this.submittingTo = discussionId ?? NEW_COMMENT;
      try {
        const { data } = await this.$apollo.mutate({
          mutation: createNoteMutation,
          variables: { input: { noteableId: this.mergeRequest.id, body, discussionId } },
          update: (cache, { data: { createNote } }) => this.addToCache(cache, createNote),
        });
        const [message] = data.createNote.errors;
        if (message) throw new Error(message);

        if (discussionId) this.replyingTo = null;
        // Remounting the form clears what was posted.
        else this.commentFormKey += 1;
      } catch (error) {
        createAlert({ message: this.$options.i18n.commentError, captureError: true, error });
      } finally {
        this.submittingTo = null;
      }
    },
    // A new thread belongs after pages that are not loaded yet, so only then is the list fetched again.
    addToCache(cache, { note }) {
      if (!note) return;

      const { discussion } = note;
      const variables = { projectPath: this.projectPath, iid: this.iid };
      const previous = cache.readQuery({ query: discussionsQuery, variables });
      const { nodes, pageInfo } = previous.project.mergeRequest.discussionsWithActivity;
      const index = nodes.findIndex(({ id }) => id === discussion.id);

      if (index === -1 && pageInfo.hasNextPage) {
        this.$apollo.queries.connection.refetch();
        return;
      }

      const data = produce(previous, (draft) => {
        const list = draft.project.mergeRequest.discussionsWithActivity.nodes;
        if (index === -1) list.push(discussion);
        else list[index] = discussion;
      });
      cache.writeQuery({ query: discussionsQuery, variables, data });
    },
    // As in the classic thread list: apply the suggestions, then resolve the thread they came from.
    async applySuggestions(discussion) {
      this.applyingIds = [...this.applyingIds, discussion.id];
      try {
        const ids = discussion.pendingSuggestionIds.map(getIdFromGraphQLId);
        await (ids.length === 1 ? Api.applySuggestion(ids[0]) : Api.applySuggestionBatch(ids));

        if (discussion.canResolve) {
          await this.$apollo
            .mutate({
              mutation: toggleResolveMutation,
              variables: { id: discussion.id, resolve: true },
            })
            .catch(() => {});
        }
        await this.$apollo.queries.connection.refetch();
      } catch (error) {
        createAlert({
          message: error.response?.data?.message || this.$options.i18n.applyError,
          captureError: true,
          error,
        });
      } finally {
        this.applyingIds = this.applyingIds.filter((applyingId) => applyingId !== discussion.id);
      }
    },
  },
  filterOptions: [
    { value: 'action', text: __('Needs action') },
    { value: 'people', text: __('People') },
    { value: 'agents', text: __('Agents') },
    { value: 'all', text: __('All') },
  ],
  i18n: {
    loadError: __('Could not load conversations.'),
    resolveError: __('Could not update the thread.'),
    commentError: __('Could not post your comment.'),
    applyError: __('Something went wrong while applying the suggestion. Please try again.'),
    outdated: __('Outdated: this thread is on an older version of the diff.'),
  },
};
</script>

<template>
  <section class="gl-flex gl-flex-col gl-gap-2">
    <div class="gl-flex gl-flex-col gl-gap-3">
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <h3 class="gl-m-0 gl-text-lg gl-font-bold">{{ __('Conversations') }}</h3>
        <span v-if="openCount" class="gl-text-subtle" data-testid="conversations-open-count">
          {{ openText }}
        </span>
        <div class="gl-ml-auto gl-flex gl-items-center gl-gap-2">
          <div
            v-if="isOpen && discussions.length"
            role="group"
            :aria-label="__('Filter conversations')"
            class="gl-flex gl-flex-wrap gl-gap-2"
            data-testid="conversations-filter"
          >
            <gl-button
              v-for="option in $options.filterOptions"
              :key="option.value"
              size="small"
              :category="activeFilter === option.value ? 'primary' : 'tertiary'"
              :selected="activeFilter === option.value"
              :aria-pressed="String(activeFilter === option.value)"
              @click="activeFilter = option.value"
            >
              {{ option.text }}
            </gl-button>
          </div>
          <gl-button
            v-gl-tooltip
            :title="toggleLabel"
            :aria-label="toggleLabel"
            :aria-expanded="String(isOpen)"
            :aria-controls="contentId"
            category="tertiary"
            size="small"
            class="btn-icon"
            data-testid="conversations-toggle"
            @click="isExpanded = !isOpen"
          >
            <gl-animated-chevron-lg-down-up-icon :is-on="isOpen" variant="default" />
          </gl-button>
        </div>
      </div>
    </div>

    <div
      v-show="isOpen"
      :id="contentId"
      class="gl-flex gl-flex-col gl-gap-2"
      data-testid="conversations-body"
    >
      <p v-if="hasError" class="gl-m-0 gl-py-3 gl-text-danger">
        {{ $options.i18n.loadError }}
      </p>
      <div v-else-if="isInitialLoading" class="gl-py-4">
        <gl-loading-icon />
      </div>
      <ul v-else-if="filteredDiscussions.length" class="gl-m-0 gl-list-none gl-p-0">
        <li
          v-for="discussion in filteredDiscussions"
          :key="discussion.id"
          class="gl-flex gl-flex-col gl-gap-2 gl-py-1"
          :class="{ 'gl-opacity-7': discussion.resolved }"
          data-testid="conversation-row"
        >
          <!-- The opening note is its own hover and focus target, apart from its replies. -->
          <div
            class="gl-group gl-relative -gl-mx-3 gl-flex gl-flex-col gl-gap-3 gl-rounded-lg gl-px-3 gl-py-3 focus-within:gl-bg-subtle hover:gl-bg-subtle"
            data-testid="conversation-opening"
          >
            <conversation-note :note="discussion.note">
              <template #badges>
                <!-- Same icons as the resolve button in the classic thread list. -->
                <gl-icon
                  v-if="discussion.isUnresolved || discussion.resolved"
                  v-gl-tooltip
                  :name="discussion.resolved ? 'check-circle-filled' : 'check-circle'"
                  :title="discussion.resolved ? __('Resolved') : __('Unresolved')"
                  :aria-label="discussion.resolved ? __('Resolved') : __('Unresolved')"
                  :variant="discussion.resolved ? 'success' : 'default'"
                  data-testid="conversation-state"
                />
              </template>

              <gl-link
                v-if="discussion.diffHref"
                :href="discussion.diffHref"
                class="gl-inline-flex gl-items-center gl-gap-2 gl-self-start gl-font-monospace !gl-text-inherit hover:!gl-text-link"
                data-testid="conversation-location"
              >
                <file-icon :file-name="discussion.filePath" aria-hidden="true" />
                {{ discussion.location }}
              </gl-link>
              <span
                v-else-if="discussion.isOutdated"
                v-gl-tooltip
                :title="$options.i18n.outdated"
                tabindex="0"
                class="gl-inline-flex gl-items-center gl-gap-2 gl-self-start gl-font-monospace gl-text-subtle"
                data-testid="conversation-location"
              >
                <file-icon :file-name="discussion.filePath" aria-hidden="true" />
                {{ discussion.location }}
                <span class="gl-sr-only">{{ $options.i18n.outdated }}</span>
              </span>
              <div
                v-if="discussion.snippet.length"
                class="code-syntax-highlight-theme gl-overflow-hidden gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-font-monospace gl-text-sm"
                data-testid="conversation-snippet"
              >
                <div
                  v-for="(line, index) in discussion.snippet"
                  :key="index"
                  class="gl-flex gl-px-3"
                  :class="line.classes"
                >
                  <span class="gl-w-5 gl-shrink-0" aria-hidden="true">{{ line.sign }}</span>
                  <span class="gl-truncate gl-whitespace-pre">{{ line.text }}</span>
                </div>
              </div>
            </conversation-note>

            <div
              v-if="discussion.canApply"
              class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-rounded-lg gl-bg-status-info gl-px-3 gl-py-2"
              data-testid="conversation-suggestion"
            >
              <span
                class="gl-inline-flex gl-items-center gl-gap-2 gl-font-bold gl-text-status-info"
              >
                <gl-icon name="doc-changes" :size="14" />
                {{ __('Suggested change ready') }}
              </span>
              <gl-button
                size="small"
                variant="confirm"
                category="secondary"
                :loading="discussion.isApplying"
                data-testid="conversation-apply"
                @click="applySuggestions(discussion)"
              >
                {{ __('Apply') }}
              </gl-button>
            </div>

            <!-- Transparent rather than hidden, so screen readers and Tab still reach the actions. -->
            <div
              v-if="replyingTo !== discussion.id && (discussion.hasActions || discussion.canReopen)"
              class="gl-absolute -gl-top-3 gl-right-3 gl-flex gl-gap-1 gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-bg-default gl-p-1 gl-opacity-0 gl-shadow-md group-focus-within:gl-opacity-10 group-hover:gl-opacity-10"
              data-testid="conversation-actions"
            >
              <template v-if="discussion.hasActions">
                <gl-button
                  v-if="canCreateNote"
                  size="small"
                  category="tertiary"
                  icon="comment"
                  data-testid="conversation-reply"
                  @click="replyingTo = discussion.id"
                >
                  {{ __('Reply') }}
                </gl-button>
                <gl-button
                  v-if="discussion.canResolve"
                  size="small"
                  category="tertiary"
                  icon="check"
                  :loading="discussion.isResolving"
                  data-testid="conversation-resolve"
                  @click="toggleResolve(discussion)"
                >
                  {{ __('Resolve') }}
                </gl-button>
              </template>
              <gl-button
                v-else
                size="small"
                category="tertiary"
                icon="redo"
                :loading="discussion.isResolving"
                data-testid="conversation-reopen"
                @click="toggleResolve(discussion)"
              >
                {{ __('Reopen thread') }}
              </gl-button>
            </div>
          </div>

          <ul
            v-if="discussion.replies.length"
            class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-1 gl-border-l-2 gl-border-l-default gl-p-0 gl-pl-2 gl-border-l-solid"
            data-testid="conversation-replies"
          >
            <!-- Each reply highlights on its own, so it does not read as part of the note above. -->
            <li
              v-for="reply in discussion.replies"
              :key="reply.id"
              class="gl-rounded-lg gl-px-3 gl-py-2 hover:gl-bg-subtle"
              data-testid="conversation-reply-row"
            >
              <conversation-note :note="reply" compact />
            </li>
          </ul>

          <conversation-form
            v-if="replyingTo === discussion.id"
            :placeholder="__('Reply…')"
            :submit-text="__('Reply')"
            :loading="submittingTo === discussion.replyId"
            @submit="createNote({ body: $event, discussionId: discussion.replyId })"
            @cancel="replyingTo = null"
          />
        </li>
      </ul>
      <p v-else class="gl-m-0 gl-py-3 gl-text-subtle">
        {{ __('No conversations to show.') }}
      </p>

      <div
        v-if="!hasError && connection && connection.pageInfo.hasNextPage"
        class="gl-py-3 gl-text-center"
      >
        <gl-button
          size="small"
          :loading="isLoadingMore"
          data-testid="conversations-load-more"
          @click="loadMore"
        >
          {{ __('Load more') }}
        </gl-button>
      </div>

      <div v-if="canCreateNote" class="gl-py-3">
        <conversation-form
          :key="commentFormKey"
          :placeholder="__('Write a comment…')"
          :submit-text="__('Comment')"
          :loading="submittingTo === $options.NEW_COMMENT"
          :autofocus="false"
          :cancelable="false"
          data-testid="conversations-comment-form"
          @submit="createNote({ body: $event })"
        />
      </div>
    </div>
  </section>
</template>
