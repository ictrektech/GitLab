<script>
import { GlSprintf, GlLink } from '@gitlab/ui';
import { __ } from '~/locale';
import {
  BLOB_RENDER_ERRORS,
  BLOB_RENDER_EVENT_LOAD,
  BLOB_RENDER_EVENT_SHOW_SOURCE,
  SNIPPET_EXPAND_MAX_SIZE,
} from './constants';

export default {
  name: 'BlobContentError',
  components: {
    GlSprintf,
    GlLink,
  },
  props: {
    viewerError: {
      type: String,
      required: true,
    },
    blob: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    isSnippet: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: [BLOB_RENDER_EVENT_LOAD, BLOB_RENDER_EVENT_SHOW_SOURCE],
  computed: {
    notStoredExternally() {
      return this.viewerError !== BLOB_RENDER_ERRORS.REASONS.EXTERNAL.id;
    },
    renderErrorReason() {
      const defaultReasonPath = Object.keys(BLOB_RENDER_ERRORS.REASONS).find(
        (reason) => BLOB_RENDER_ERRORS.REASONS[reason].id === this.viewerError,
      );
      const defaultReason = BLOB_RENDER_ERRORS.REASONS[defaultReasonPath].text;
      return this.notStoredExternally
        ? defaultReason
        : defaultReason[this.blob.externalStorage || 'default'];
    },
    renderErrorOptions() {
      const load = {
        ...BLOB_RENDER_ERRORS.OPTIONS.LOAD,
        href: this.isSnippet
          ? `${BLOB_RENDER_ERRORS.OPTIONS.LOAD.href}&path=${encodeURIComponent(this.blob.path)}`
          : BLOB_RENDER_ERRORS.OPTIONS.LOAD.href,
        condition: this.shouldShowLoadBtn,
      };
      const showSource = {
        ...BLOB_RENDER_ERRORS.OPTIONS.SHOW_SOURCE,
        condition: this.shouldShowSourceBtn,
      };
      const download = {
        ...BLOB_RENDER_ERRORS.OPTIONS.DOWNLOAD,
        href: this.blob.rawPath,
      };
      return [load, showSource, download];
    },
    isSnippetOverExpandLimit() {
      return this.isSnippet && this.blob.size >= SNIPPET_EXPAND_MAX_SIZE;
    },
    shouldShowLoadBtn() {
      return (
        this.viewerError === BLOB_RENDER_ERRORS.REASONS.COLLAPSED.id &&
        !this.isSnippetOverExpandLimit
      );
    },
    shouldShowSourceBtn() {
      return (
        this.blob.richViewer &&
        this.blob.renderedAsText &&
        this.notStoredExternally &&
        !this.isSnippetOverExpandLimit
      );
    },
  },
  errorMessage: __(
    'Content could not be displayed: %{reason}. Options to address this: %{options}.',
  ),
};
</script>
<template>
  <div class="file-content code">
    <div class="!gl-py-6 !gl-text-center">
      <gl-sprintf :message="$options.errorMessage">
        <template #reason>{{ renderErrorReason }}</template>
        <template #options>
          <template v-for="option in renderErrorOptions">
            <span v-if="option.condition" :key="option.text">
              <gl-link
                :href="option.href"
                :target="option.target"
                @click="option.event && $emit(option.event)"
                >{{ option.text }}</gl-link
              >
              {{ option.conjunction }}
            </span>
          </template>
        </template>
      </gl-sprintf>
    </div>
  </div>
</template>
