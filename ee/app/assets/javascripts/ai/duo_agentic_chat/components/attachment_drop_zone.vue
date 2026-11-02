<script>
import { GlAnimatedUploadIcon } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { numberToHumanSize } from '~/lib/utils/number_utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  MAX_ATTACHMENT_BYTES,
  dragHasSupportedFile,
  filesFromDataTransfer,
  isFileDrag,
} from '../utils/attachment_utils';

// Browsers keep firing `dragover` while a drag is in progress, every 350ms at the
// slowest, so a silence this long means the drag left the window or was cancelled.
// A file dragged in from outside the page produces no event for either.
const DRAG_IDLE_MS = 1000;

// Overlay states. NEARBY: a supported file is dragged elsewhere in the page.
// OVER: a supported file is over the chat. UNSUPPORTED: an unsupported file is
// over the chat. An unsupported file elsewhere in the page shows nothing.
const NEARBY = 'nearby';
const OVER = 'over';
const UNSUPPORTED = 'unsupported';

/**
 * Makes the chat panel a drop target for attachments and shows an overlay while a
 * file is dragged. Listens on `document` because the panel reacts to a file dragged
 * anywhere in the page, not only over itself.
 *
 * Emits `drop` with the dropped files; the composer decides what to do with them.
 */
export default {
  name: 'AttachmentDropZone',
  OVERLAY_BACKGROUND: {
    [NEARBY]: 'gl-bg-strong',
    [OVER]: 'gl-bg-feedback-info',
    [UNSUPPORTED]: 'gl-bg-feedback-danger',
  },
  UNSUPPORTED,
  components: {
    GlAnimatedUploadIcon,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['drop'],
  data() {
    return {
      dragState: null,
      idleTimer: null,
    };
  },
  computed: {
    isEnabled() {
      return Boolean(this.glFeatures?.dapWebChatFileAttachments);
    },
    canAttach() {
      return this.isEnabled && !this.disabled;
    },
    fileLimit() {
      return sprintf(s__('DuoAgenticChat|File limit: %{limit}'), {
        limit: numberToHumanSize(MAX_ATTACHMENT_BYTES, 0),
      });
    },
  },
  mounted() {
    if (!this.isEnabled) return;

    // Capture phase, so a drop zone elsewhere in the page that stops propagation
    // cannot leave the overlay up.
    document.addEventListener('dragover', this.onDocumentDragOver, true);
    document.addEventListener('drop', this.reset, true);
  },
  beforeDestroy() {
    document.removeEventListener('dragover', this.onDocumentDragOver, true);
    document.removeEventListener('drop', this.reset, true);
    clearTimeout(this.idleTimer);
  },
  methods: {
    stateFor(event) {
      if (!this.canAttach || !isFileDrag(event)) return null;

      const isOver = this.$el.contains(event.target);

      if (!dragHasSupportedFile(event)) return isOver ? UNSUPPORTED : null;

      return isOver ? OVER : NEARBY;
    },
    onDocumentDragOver(event) {
      this.dragState = this.stateFor(event);

      clearTimeout(this.idleTimer);
      this.idleTimer = setTimeout(this.reset, DRAG_IDLE_MS);
    },
    reset() {
      clearTimeout(this.idleTimer);
      this.dragState = null;
    },
    onDragOver(event) {
      // Required, or the browser navigates to the dropped file instead of firing `drop`.
      // Unsupported files are allowed through too: the composer then says why each was
      // refused, which beats the tab navigating away to a PDF.
      if (this.canAttach && isFileDrag(event)) event.preventDefault();
    },
    onDrop(event) {
      if (!this.canAttach || !isFileDrag(event)) return;

      event.preventDefault();
      this.$emit('drop', filesFromDataTransfer(event.dataTransfer));
    },
  },
};
</script>
<template>
  <div class="gl-relative" @dragover="onDragOver" @drop="onDrop">
    <slot></slot>
    <div
      v-if="dragState"
      class="gl-pointer-events-none gl-absolute gl-inset-0 gl-z-200"
      data-testid="attachment-drop-overlay"
    >
      <div
        class="gl-absolute gl-inset-0 gl-opacity-8"
        :class="$options.OVERLAY_BACKGROUND[dragState]"
      ></div>
      <div
        class="gl-relative gl-flex gl-h-full gl-flex-col gl-items-center gl-justify-center gl-gap-3 gl-p-5 gl-text-center gl-text-default"
      >
        <template v-if="dragState === $options.UNSUPPORTED">
          <p class="gl-mb-0 gl-text-lg gl-font-bold">
            {{ s__('DuoAgenticChat|File type not supported') }}
          </p>
          <p class="gl-mb-0">{{ s__('DuoAgenticChat|Supported formats: PNG, JPEG, WebP') }}</p>
          <p class="gl-mb-0">{{ fileLimit }}</p>
        </template>
        <div v-else class="gl-flex gl-items-center gl-gap-3 gl-text-lg gl-font-bold">
          <gl-animated-upload-icon is-on class="gl-h-6 gl-w-6" />
          <span>{{ s__('DuoAgenticChat|Drop to add file') }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
