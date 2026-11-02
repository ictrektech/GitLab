<script>
import { UserMessage } from '@gitlab/duo-ui';
import { goalIn } from '../../../utils/messages_utils';
import GoalToken from '../../../components/prompt_composer/goal_token.vue';

// Wraps duo-ui's own user bubble rather than rebuilding it, so a goal turn renders like
// every other user message apart from the badge and the token taken off the text.
export default {
  name: 'MessageGoalPrompt',
  components: {
    GoalToken,
    UserMessage,
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
    goal() {
      return { ...this.message, content: goalIn(this.message.content) };
    },
  },
};
</script>
<template>
  <user-message
    :message="goal"
    :trusted-urls="trustedUrls"
    @get-context-item-content="$emit('get-context-item-content', $event)"
  >
    <template #header>
      <goal-token view-only class="gl-mb-3" />
      <slot name="header"></slot>
    </template>
  </user-message>
</template>
