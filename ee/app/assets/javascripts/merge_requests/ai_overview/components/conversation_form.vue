<script>
import { GlButton, GlFormTextarea } from '@gitlab/ui';

export default {
  name: 'ConversationForm',
  components: {
    GlButton,
    GlFormTextarea,
  },
  props: {
    placeholder: {
      type: String,
      required: true,
    },
    submitText: {
      type: String,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    autofocus: {
      type: Boolean,
      required: false,
      default: true,
    },
    cancelable: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['submit', 'cancel'],
  data() {
    return {
      body: '',
    };
  },
  mounted() {
    if (this.autofocus) this.$refs.input.$el.focus();
  },
};
</script>

<template>
  <form class="gl-flex gl-flex-col gl-gap-2" @submit.prevent="$emit('submit', body)">
    <gl-form-textarea
      ref="input"
      v-model="body"
      :placeholder="placeholder"
      :aria-label="placeholder"
      :no-resize="false"
      rows="3"
      data-testid="conversation-form-input"
    />
    <div class="gl-flex gl-gap-2">
      <gl-button
        type="submit"
        variant="confirm"
        size="small"
        :disabled="!body"
        :loading="loading"
        data-testid="conversation-form-submit"
      >
        {{ submitText }}
      </gl-button>
      <gl-button v-if="cancelable" size="small" category="tertiary" @click="$emit('cancel')">
        {{ __('Cancel') }}
      </gl-button>
    </div>
  </form>
</template>
