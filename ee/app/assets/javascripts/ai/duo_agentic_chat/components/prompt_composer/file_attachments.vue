<script>
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { EventsTracker } from '../../observability/events_tracker';
import {
  ALLOWED_IMAGE_MIME_TYPES,
  ATTACHMENT_METHODS,
  buildAttachments,
  filesFromDataTransfer,
  isSupportedAttachmentType,
} from '../../utils/attachment_utils';
import AttachmentPreviews from './attachment_previews.vue';

/**
 * Every way a file can reach the composer -- the picker, a paste, a drop on the chat
 * panel -- and everything that follows from one: validation and the previews. The
 * rejection notices go up with `errors`, and the composer shows them above its input.
 * The drop target itself is the panel's `<attachment-drop-zone>`, which hands the
 * files down to `addFiles`.
 *
 * The attachments themselves live on the composer's draft rather than here, so that
 * one object carries the whole prompt. This component reads them as a prop and asks
 * for changes, which keeps the draft the single source of truth for what will be sent.
 */
export default {
  name: 'FileAttachments',
  ACCEPTED_IMAGE_TYPES: ALLOWED_IMAGE_MIME_TYPES.join(','),
  components: {
    AttachmentPreviews,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    attachments: {
      type: Array,
      required: false,
      default: () => [],
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['add', 'remove', 'errors'],
  computed: {
    isEnabled() {
      return Boolean(this.glFeatures?.dapWebChatFileAttachments);
    },
    // Rendering stays on `isEnabled` alone: a draft composed before the chat became
    // unavailable keeps its previews and notices, only new files are turned away.
    canAttach() {
      return this.isEnabled && !this.disabled;
    },
  },
  methods: {
    // The single gate for every entry point. Nothing reaches `buildAttachments`
    // without passing through here, so the flag and the limits cannot be bypassed
    // by one route while holding on another. Also called by the composer via $refs
    // for files dropped on the chat panel. `method` only feeds tracking.
    async addFiles(files, { method } = {}) {
      if (!this.canAttach || !files.length) return;

      const { attachments, errors, rejections } = await buildAttachments({
        files,
        existing: this.attachments,
      });

      attachments.forEach(({ mimeType, byteSize }) =>
        EventsTracker.trackAttachFile({ method, mimeType, byteSize }),
      );
      rejections.forEach(({ reason, count }) =>
        EventsTracker.trackRejectFileAttachment({ method, reason, count }),
      );

      // Deduplicated because the notices are keyed by their text: two files rejected for
      // the same reason under the same name (pasted images share a generated filename)
      // would otherwise collide as keys and dismiss together. Emitted even when empty,
      // so a clean batch replaces the notices of the previous one.
      this.$emit('errors', [...new Set(errors)]);

      if (attachments.length) this.$emit('add', attachments);
    },
    // Called by the composer via $refs.
    // eslint-disable-next-line vue/no-unused-properties
    openFilePicker() {
      if (!this.canAttach) return;

      this.$refs.fileInput?.click();
    },
    onRemove(id) {
      this.$emit('remove', id);
    },
    async onFileInputChange(event) {
      const input = event.target;

      await this.addFiles(Array.from(input.files || []), {
        method: ATTACHMENT_METHODS.PLUS_MENU,
      });
      // Reset so re-picking the same file fires `change` again.
      input.value = '';
    },
    // Called by the composer via $refs.
    // eslint-disable-next-line vue/no-unused-properties
    onPaste(event) {
      if (!this.canAttach) return;

      const files = filesFromDataTransfer(event.clipboardData);

      // Claimed only when there is an image to take. Rich text can carry a file
      // alongside the text, and swallowing that paste would lose the text.
      if (!files.some(isSupportedAttachmentType)) return;

      event.preventDefault();
      this.addFiles(files, { method: ATTACHMENT_METHODS.PASTE });
    },
  },
};
</script>
<template>
  <div v-if="isEnabled" data-testid="file-attachments">
    <input
      ref="fileInput"
      type="file"
      multiple
      class="gl-sr-only"
      :accept="$options.ACCEPTED_IMAGE_TYPES"
      data-testid="attachment-file-input"
      @change="onFileInputChange"
    />
    <attachment-previews :attachments="attachments" :disabled="disabled" @remove="onRemove" />
  </div>
</template>
