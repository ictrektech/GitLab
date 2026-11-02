<script>
import { GlFormTextarea } from '@gitlab/ui';
import { MAX_PROMPT_LENGTH, PROMPT_LENGTH_WARNING } from 'ee/ai/tanuki_bot/constants';
import { n__, sprintf } from '~/locale';

export default {
  name: 'PromptTextarea',
  TEXTAREA_MAX_ROWS: 20,
  components: {
    GlFormTextarea,
  },
  props: {
    value: {
      type: String,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    placeholder: {
      type: String,
      required: false,
      default: '',
    },
    autofocus: {
      type: Boolean,
      required: false,
      default: false,
    },
    hasHeaderRow: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input', 'submit', 'focus-change'],
  data() {
    return {
      maxPromptLength: MAX_PROMPT_LENGTH,
      promptLengthWarningCount: MAX_PROMPT_LENGTH - PROMPT_LENGTH_WARNING,
    };
  },
  methods: {
    // `focus` is called by the composer via $refs.
    // eslint-disable-next-line vue/no-unused-properties
    focus() {
      this.$refs.prompt?.focus?.();
    },
    onInputKeydown(e) {
      if (e.key !== 'Enter') return;
      // keyCode 229 is what browsers report while an IME is composing.
      if (e.isComposing || e.keyCode === 229) return;
      if (e.repeat) return;
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;

      e.preventDefault();
      this.$emit('submit');
    },
    handleUndo(event) {
      event.preventDefault();
      document.execCommand?.('undo');
    },
    handleRedo(event) {
      event.preventDefault();
      document.execCommand?.('redo');
    },
    remainingCharacterCountMessage(count) {
      return sprintf(
        n__(
          'DuoAgenticChat|%{count} character remaining.',
          'DuoAgenticChat|%{count} characters remaining.',
          count,
        ),
        { count },
      );
    },
    overLimitCharacterCountMessage(count) {
      return sprintf(
        n__(
          'DuoAgenticChat|%{count} character over limit.',
          'DuoAgenticChat|%{count} characters over limit.',
          count,
        ),
        { count },
      );
    },
  },
};
</script>
<template>
  <gl-form-textarea
    ref="prompt"
    :value="value"
    :disabled="disabled"
    data-testid="chat-prompt-input"
    :placeholder="placeholder"
    :character-count-limit="maxPromptLength"
    :max-rows="$options.TEXTAREA_MAX_ROWS"
    no-resize
    :textarea-classes="[
      'agentic-chat-textarea',
      '!gl-bg-transparent',
      '!gl-shadow-none',
      '!gl-rounded-t-none',
      'gl-w-full',
      'forced-colors:!gl-border-l-0',
      'forced-colors:!gl-border-r-0',
      'forced-colors:!gl-border-b-0',
      '!gl-pr-2',
      /* without the header row above, the input needs its own top
         breathing room; ! beats the textarea's default padding-top, and the
         min-height floor in duo_chat.scss has to match it */
      { '!gl-pt-4': !hasHeaderRow, 'agentic-chat-textarea-padded': !hasHeaderRow },
    ]"
    :autofocus="autofocus"
    :aria-label="s__('DuoAgenticChat|Chat prompt input')"
    @input="$emit('input', $event)"
    @keydown.enter.exact.prevent
    @keydown.ctrl.z.exact="handleUndo"
    @keydown.meta.z.exact="handleUndo"
    @keydown.ctrl.shift.z.exact="handleRedo"
    @keydown.meta.shift.z.exact="handleRedo"
    @keydown.ctrl.y.exact="handleRedo"
    @keydown.meta.y.exact="handleRedo"
    @keydown="onInputKeydown"
    @focusin="$emit('focus-change', true)"
    @focusout="$emit('focus-change', false)"
  >
    <template #remaining-character-count-text="{ count }">
      <span
        v-if="count <= promptLengthWarningCount"
        class="gl-my-2 gl-flex gl-justify-end gl-pr-3 gl-text-sm"
      >
        {{ remainingCharacterCountMessage(count) }}
      </span>
    </template>
    <template #character-count-over-limit-text="{ count }">
      <span class="gl-my-2 gl-flex gl-justify-end gl-pr-3 gl-text-sm">{{
        overLimitCharacterCountMessage(count)
      }}</span>
    </template>
  </gl-form-textarea>
</template>
