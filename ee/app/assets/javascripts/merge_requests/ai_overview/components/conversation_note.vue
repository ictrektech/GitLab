<script>
import { GlAvatar, GlLink } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { TODO_NOTE_PREVIEW_SAFE_HTML_CONFIG } from '~/todos/constants';
import SafeHtml from '~/vue_shared/directives/safe_html';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';

export default {
  name: 'ConversationNote',
  components: {
    GlAvatar,
    GlLink,
    TimeAgoTooltip,
  },
  directives: {
    SafeHtml,
  },
  props: {
    note: {
      type: Object,
      required: true,
    },
    compact: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    author() {
      return this.note.author;
    },
    authorId() {
      return getIdFromGraphQLId(this.author.id);
    },
  },
  safeHtmlConfig: TODO_NOTE_PREVIEW_SAFE_HTML_CONFIG,
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-2">
    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
      <gl-link
        v-if="author"
        :href="author.webPath"
        :data-user-id="authorId"
        :data-username="author.username"
        class="js-user-link gl-inline-flex gl-items-center gl-gap-2 gl-font-bold !gl-text-heading hover:!gl-text-link"
        data-testid="conversation-author"
      >
        <gl-avatar :src="author.avatarUrl" :entity-name="author.name" :size="compact ? 16 : 24" />
        {{ author.name }}
      </gl-link>
      <time-ago-tooltip :time="note.createdAt" class="gl-text-sm gl-text-subtle" />
      <slot name="badges"></slot>
    </div>
    <slot></slot>
    <p
      v-safe-html:[$options.safeHtmlConfig]="note.bodyFirstLineHtml"
      class="gl-m-0 gl-break-words"
      data-testid="conversation-body"
    ></p>
  </div>
</template>
