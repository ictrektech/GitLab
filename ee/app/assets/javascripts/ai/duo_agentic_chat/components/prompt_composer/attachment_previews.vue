<script>
import AttachmentChip from './attachment_chip.vue';

export default {
  name: 'AttachmentPreviews',
  components: {
    AttachmentChip,
  },
  props: {
    attachments: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['remove'],
};
</script>
<template>
  <ul
    v-if="attachments.length"
    class="gl-m-0 gl-flex gl-list-none gl-flex-wrap gl-gap-4 gl-px-4 gl-pt-4"
    data-testid="attachment-previews"
  >
    <li v-for="attachment in attachments" :key="attachment.id" data-testid="attachment-preview">
      <attachment-chip
        :attachment="attachment"
        :disabled="disabled"
        @remove="$emit('remove', $event)"
      />
    </li>
  </ul>
</template>
