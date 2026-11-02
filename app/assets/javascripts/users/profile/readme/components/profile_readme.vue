<script>
import { GlButton } from '@gitlab/ui';
import { handleLocationHash } from '~/lib/utils/common_utils';
import FilePreview from '~/repository/components/preview/index.vue';

export const READ_MORE_HEIGHT = 400;

export default {
  name: 'ProfileReadme',
  components: {
    GlButton,
    FilePreview,
  },
  props: {
    blob: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isExpanded: false,
      isTruncated: false,
    };
  },
  computed: {
    contentStyle() {
      return this.isExpanded ? null : { maxHeight: `${READ_MORE_HEIGHT}px` };
    },
  },
  methods: {
    onRendered() {
      // Expand straight away when the URL points at a heading inside the README,
      // otherwise the anchor would be hidden behind the truncation.
      if (this.hasHashTarget()) {
        this.expand();
        this.$nextTick(handleLocationHash);
        return;
      }

      this.isTruncated = this.$refs.content.scrollHeight > READ_MORE_HEIGHT;
    },
    hasHashTarget() {
      const hash = window.location.hash.slice(1);

      if (!hash) return false;

      let id;

      try {
        id = decodeURIComponent(hash);
      } catch {
        // A malformed hash (e.g. `#%E0%A4%A`) can't point at a README heading.
        return false;
      }

      const target = document.getElementById(`user-content-${id}`);

      return Boolean(target && this.$refs.content.contains(target));
    },
    expand() {
      this.isExpanded = true;
      this.isTruncated = false;
    },
  },
};
</script>

<template>
  <div class="profile-readme gl-border gl-relative gl-overflow-hidden gl-rounded-lg">
    <div
      ref="content"
      :class="{ 'gl-overflow-hidden': !isExpanded }"
      :style="contentStyle"
      data-testid="profile-readme-content"
    >
      <file-preview :blob="blob" @rendered="onRendered" />
    </div>
    <div
      v-if="isTruncated"
      class="description-more gl-inset-x-6 gl-z-2"
      data-testid="profile-readme-read-more"
    >
      <div class="show-all-btn gl-flex gl-w-full gl-items-center gl-justify-center gl-pb-2">
        <gl-button
          variant="confirm"
          category="tertiary"
          :aria-label="__('Expand Readme')"
          @click="expand"
        >
          {{ __('Read more') }}
        </gl-button>
      </div>
    </div>
  </div>
</template>
