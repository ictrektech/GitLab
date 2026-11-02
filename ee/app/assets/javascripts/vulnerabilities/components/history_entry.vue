<script>
import SafeHtml from '~/vue_shared/directives/safe_html';
import EventItem from 'ee/vue_shared/security_reports/components/event_item.vue';
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';
import HistoryComment from './history_comment.vue';

export default {
  name: 'HistoryEntry',
  components: {
    EventItem,
    HistoryComment,
  },
  directives: {
    SafeHtml,
  },
  mixins: [glListenersMixin],
  props: {
    discussion: {
      type: Object,
      required: true,
    },
  },
  computed: {
    notes() {
      return this.discussion.notes;
    },
    systemNote() {
      return this.notes.find((x) => x.system === true);
    },
    comments() {
      return this.notes.filter((x) => x !== this.systemNote);
    },
  },
  // Remove paragraph tags so that markdown can be displayed inline.
  safeHtmlConfig: { FORBID_TAGS: ['p'] },
};
</script>

<template>
  <!-- `gl-group` lets the event item below drop its top margin when this entry leads the feed,
  so the panel padding frames the first row; the positioning context hosts the spine segments. -->
  <li v-if="systemNote" class="system-note gl-group gl-relative gl-isolate gl-p-0">
    <div
      aria-hidden="true"
      class="gl-absolute -gl-top-5 gl-left-0 -gl-z-1 gl-flex gl-h-5 gl-w-6 gl-justify-center group-first:gl-hidden"
    >
      <div class="gl-w-1 gl-bg-strong"></div>
    </div>
    <div
      aria-hidden="true"
      class="gl-absolute gl-bottom-0 gl-left-0 gl-top-0 -gl-z-1 gl-flex gl-w-6 gl-justify-center group-last:gl-hidden"
    >
      <div class="gl-w-1 gl-bg-strong"></div>
    </div>
    <!-- The icon is a 24px circle on the spine, pinned to the row top (`gl-self-start`) so it
    meets the spine segment even when the text wraps. That circle plus the event item's built-in
    16px gap keeps the text at the feed's shared 40px offset. -->
    <event-item
      :id="systemNote.id"
      :author="systemNote.author"
      :created-at="systemNote.createdAt"
      :icon-name="systemNote.systemNoteIconName"
      is-system-note
      icon-class="gl-flex gl-h-6 gl-w-6 gl-items-center gl-justify-center gl-self-start gl-rounded-full gl-bg-strong gl-text-subtle"
      class="gl-my-5 group-first:gl-mt-0"
    >
      <template #header-message>
        <span v-safe-html:[$options.safeHtmlConfig]="systemNote.bodyHtml" class="md"></span>
      </template>
    </event-item>
    <!-- Replies are indented so they read as belonging to the entry above; the comment card's
    16px inner padding lands their content on the feed's 40px text column. -->
    <history-comment
      v-for="comment in comments"
      :key="comment.id"
      class="gl-ml-6"
      :comment="comment"
      :discussion-id="discussion.replyId"
      data-testid="existing-comment"
      v-on="glListeners()"
    />
    <history-comment
      v-if="!comments.length"
      class="gl-ml-6"
      :discussion-id="discussion.replyId"
      data-testid="new-comment"
      v-on="glListeners()"
    />
  </li>
</template>
