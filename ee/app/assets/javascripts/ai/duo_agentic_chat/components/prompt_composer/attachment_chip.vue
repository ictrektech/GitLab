<script>
import { GlButton, GlIcon, GlTooltipDirective } from '@gitlab/ui';
import { numberToHumanSize } from '~/lib/utils/number_utils';
import { s__, sprintf } from '~/locale';

// One attachment as a square thumbnail tile. The composer shows it with a remove
// button; a sent message shows the same tile view-only. A reference echoed back after a
// reload carries neither preview nor size, so both are optional.
export default {
  name: 'AttachmentChip',
  components: {
    GlButton,
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    attachment: {
      type: Object,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    viewOnly: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['remove'],
  computed: {
    label() {
      const { filename, byteSize } = this.attachment;

      return Number.isFinite(byteSize)
        ? sprintf(
            s__('DuoAgenticChat|%{filename} (%{size})'),
            {
              filename,
              size: numberToHumanSize(byteSize),
            },
            false,
          )
        : filename;
    },
    removeLabel() {
      return sprintf(
        s__('DuoAgenticChat|Remove %{filename}'),
        {
          filename: this.attachment.filename,
        },
        false,
      );
    },
  },
};
</script>
<template>
  <!-- The composer tile has a round remove button on the corner. A sent message shows
       the same tile view-only. -->
  <div
    class="gl-relative gl-h-12 gl-w-12 gl-shrink-0 gl-rounded-lg gl-border-1 gl-border-solid gl-border-strong gl-bg-subtle"
    data-testid="attachment-chip"
  >
    <img
      v-if="attachment.previewUrl"
      v-gl-tooltip.viewport
      :title="label"
      :src="attachment.previewUrl"
      :alt="label"
      class="gl-h-full gl-w-full gl-rounded-lg gl-object-contain"
      data-testid="attachment-thumbnail"
    />
    <div
      v-else
      v-gl-tooltip.viewport
      :title="label"
      role="img"
      :aria-label="label"
      class="gl-flex gl-h-full gl-w-full gl-items-center gl-justify-center gl-rounded-lg gl-text-subtle"
    >
      <gl-icon name="doc-image" :size="24" />
    </div>
    <gl-button
      v-if="!viewOnly"
      v-gl-tooltip.viewport
      :title="__('Remove')"
      icon="close-xs"
      category="primary"
      size="small"
      class="gl-absolute -gl-right-2 -gl-top-2 !gl-rounded-full !gl-border-strong !gl-bg-overlap !gl-p-0"
      :disabled="disabled"
      :aria-label="removeLabel"
      @click="$emit('remove', attachment.id)"
    />
  </div>
</template>
