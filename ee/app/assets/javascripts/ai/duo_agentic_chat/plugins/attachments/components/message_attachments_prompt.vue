<script>
import { UserMessage } from '@gitlab/duo-ui';
import {
  attachmentsIn,
  isAttachmentReference,
  isGoalPromptMessage,
} from '../../../utils/messages_utils';
import AttachmentChip from '../../../components/prompt_composer/attachment_chip.vue';
import MessageGoalPrompt from '../../goal/components/message_goal_prompt.vue';

// Wraps duo-ui's own user bubble like MessageGoalPrompt does. The files move out of
// duo-ui's collapsed "Included references" list into tiles above the text, so the same
// reference is taken off the context items it would otherwise show twice.
export default {
  name: 'MessageAttachmentsPrompt',
  components: {
    AttachmentChip,
  },
  props: {
    message: {
      type: Object,
      required: true,
    },
    // Declared so duo-ui's MessageMap binds it: it passes on only declared props.
    trustedUrls: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['get-context-item-content'],
  computed: {
    attachments() {
      return attachmentsIn(this.message);
    },
    // A goal turn with files keeps its badge: this widget claims the turn first and
    // lets the goal widget draw the bubble, adding the tiles under the badge.
    bubble() {
      return isGoalPromptMessage(this.message) ? MessageGoalPrompt : UserMessage;
    },
    messageWithoutReferences() {
      const contextItems = (this.message.extras?.contextItems ?? []).filter(
        (item) => !isAttachmentReference(item),
      );

      return { ...this.message, extras: { ...this.message.extras, contextItems } };
    },
  },
};
</script>
<template>
  <component
    :is="bubble"
    :message="messageWithoutReferences"
    :trusted-urls="trustedUrls"
    @get-context-item-content="$emit('get-context-item-content', $event)"
  >
    <template #header>
      <ul
        class="gl-m-0 gl-mb-3 gl-flex gl-list-none gl-flex-wrap gl-gap-3 gl-p-0"
        data-testid="message-attachments"
      >
        <li v-for="attachment in attachments" :key="attachment.id">
          <attachment-chip :attachment="attachment" view-only />
        </li>
      </ul>
    </template>
  </component>
</template>
