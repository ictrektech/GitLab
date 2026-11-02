<script>
import { GlTokenSelector } from '@gitlab/ui';
import { textToStringList } from './utils';

export default {
  name: 'StringListTokenSelector',
  components: { GlTokenSelector },
  props: {
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
    ariaLabel: {
      type: String,
      required: true,
    },
    placeholder: {
      type: String,
      required: false,
      default: null,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    textInputAttrs: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  computed: {
    tokens() {
      return (this.value ?? []).map((name, index) => ({ id: index, name }));
    },
  },
  methods: {
    handleTokensInput(tokens) {
      this.$emit(
        'input',
        tokens.flatMap(({ name }) => textToStringList(name)),
      );
    },
    handleEnter(event) {
      if (event.target.value !== '') {
        event.preventDefault();
      }
    },
    handleKeydown(event) {
      if (event.key !== ',') return;

      event.preventDefault();
      if (event.target.value.trim() !== '') {
        this.$refs.tokenSelector.handleEnter();
      }
    },
    handleBlur(event) {
      if (event.target.value.trim() !== '') {
        this.$refs.tokenSelector.handleEnter();
      }
    },
    handlePaste(event) {
      const pasted = textToStringList(event.clipboardData?.getData('text') ?? '');
      if (pasted.length < 2) return;

      event.preventDefault();
      this.$emit('input', [...(this.value ?? []), ...pasted]);
    },
  },
};
</script>

<template>
  <div class="gl-grow" @paste="handlePaste">
    <gl-token-selector
      ref="tokenSelector"
      :selected-tokens="tokens"
      container-class="!gl-h-auto"
      menu-class="!gl-hidden"
      allow-user-defined-tokens
      hide-dropdown-with-no-items
      :aria-label="ariaLabel"
      :placeholder="placeholder"
      :view-only="disabled"
      :text-input-attrs="textInputAttrs"
      @input="handleTokensInput"
      @keydown.enter="handleEnter"
      @keydown="handleKeydown"
      @blur="handleBlur"
    />
  </div>
</template>
