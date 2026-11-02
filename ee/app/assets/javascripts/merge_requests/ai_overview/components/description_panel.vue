<script>
import { GlAvatar, GlButton, GlLink, GlSprintf } from '@gitlab/ui';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { getLocationHash } from '~/lib/utils/url_utility';
import SafeHtml from '~/vue_shared/directives/safe_html';

// Shorter than a work item's 80vh, since this is one card among several. The buffer, as on
// work items, avoids hiding only a line or two behind Read more.
const COLLAPSED_HEIGHT_PX = 248; // gl-max-h-31
const TRUNCATE_BUFFER_PX = 96;

export default {
  name: 'DescriptionPanel',
  components: {
    GlAvatar,
    GlButton,
    GlLink,
    GlSprintf,
  },
  directives: {
    SafeHtml,
  },
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isTruncated: false,
      isShowingAll: false,
    };
  },
  computed: {
    author() {
      return this.mergeRequest.author;
    },
    authorId() {
      return getIdFromGraphQLId(this.author.id);
    },
  },
  watch: {
    'mergeRequest.descriptionHtml': function onDescriptionChange() {
      this.$nextTick(this.renderDescription);
    },
  },
  mounted() {
    window.addEventListener('hashchange', this.onHashChange);
    this.renderDescription();
  },
  beforeDestroy() {
    window.removeEventListener('hashchange', this.onHashChange);
  },
  methods: {
    renderDescription() {
      const container = this.$refs.gfmContainer;
      if (!container) return;

      renderGFM(container);
      this.truncate();
    },
    // Runs again as images load, since they can grow the description past the limit.
    truncate() {
      const container = this.$refs.gfmContainer;
      if (!container || this.isShowingAll) return;

      // A link to a heading in the description must not land on hidden text.
      if (this.findAnchorTarget()) {
        this.showAll();
        return;
      }

      // scrollHeight, unlike clientHeight, is the full height even while truncated.
      this.isTruncated = container.scrollHeight > COLLAPSED_HEIGHT_PX + TRUNCATE_BUFFER_PX;
    },
    findAnchorTarget() {
      const hash = getLocationHash();
      if (!hash) return null;

      let id;
      try {
        id = decodeURIComponent(hash);
      } catch {
        return null;
      }
      // Rendered markdown prefixes heading ids, as handled in common_utils' handleLocationHash.
      return (
        Array.from(this.$refs.gfmContainer?.querySelectorAll('[id]') ?? []).find(
          (el) => el.id === id || el.id === `user-content-${id}`,
        ) ?? null
      );
    },
    onHashChange() {
      if (!this.isTruncated) return;

      const target = this.findAnchorTarget();
      if (!target) return;

      this.showAll();
      this.$nextTick(() => target.scrollIntoView());
    },
    showAll() {
      this.isShowingAll = true;
      this.isTruncated = false;
    },
  },
};
</script>

<template>
  <section
    class="gl-overflow-hidden gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-bg-default"
  >
    <slot></slot>
    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3 gl-px-4 gl-py-3">
      <h3 class="gl-m-0 gl-mr-auto gl-text-base gl-font-bold">{{ __('Description') }}</h3>
      <span
        v-if="author"
        class="gl-flex gl-items-center gl-gap-2 gl-text-subtle"
        data-testid="description-author"
      >
        <gl-sprintf :message="__('Created by %{author}')">
          <template #author>
            <gl-link
              :href="author.webPath"
              :data-user-id="authorId"
              :data-username="author.username"
              class="js-user-link gl-inline-flex gl-items-center gl-gap-2 !gl-text-inherit hover:!gl-text-link"
            >
              <gl-avatar :src="author.avatarUrl" :entity-name="author.name" :size="16" />
              {{ author.name }}
            </gl-link>
          </template>
        </gl-sprintf>
      </span>
    </div>
    <div
      v-if="mergeRequest.descriptionHtml"
      class="gl-relative gl-border-t-1 gl-border-t-default gl-px-4 gl-py-4 gl-border-t-solid"
    >
      <div
        ref="gfmContainer"
        v-safe-html="mergeRequest.descriptionHtml"
        class="md"
        :class="{ 'gl-max-h-31 gl-overflow-hidden': isTruncated }"
        data-testid="description-content"
        @load.capture="truncate"
      ></div>
      <!-- The same fade and Read more bar as a long work item description. -->
      <div v-if="isTruncated" class="description-more gl-left-0 gl-z-1 gl-block gl-w-full">
        <div class="show-all-btn gl-flex gl-w-full gl-items-center gl-justify-center gl-pb-2">
          <gl-button
            variant="confirm"
            category="tertiary"
            class="gl-mx-4"
            data-testid="description-read-more"
            @click="showAll"
          >
            {{ __('Read more') }}
          </gl-button>
        </div>
      </div>
    </div>
    <p
      v-else
      class="gl-m-0 gl-border-t-1 gl-border-t-default gl-px-4 gl-py-3 gl-text-subtle gl-border-t-solid"
    >
      {{ __('No description') }}
    </p>
  </section>
</template>
