<script>
import { GlButton, GlForm, GlFormGroup, GlFormInput } from '@gitlab/ui';
import Iframe, { embedNotAllowedMessage, iframeInsertPluginKey } from '../../extensions/iframe';
import BubbleMenu from './bubble_menu.vue';

export default {
  name: 'IframeInsertBubbleMenu',
  components: {
    BubbleMenu,
    GlButton,
    GlForm,
    GlFormGroup,
    GlFormInput,
  },
  inject: ['tiptapEditor', 'contentEditor'],
  data() {
    return {
      canonicalSrc: '',
      alt: '',
      embedError: null,
      isUpdating: false,
    };
  },
  computed: {
    srcState() {
      return this.embedError ? false : null;
    },
  },
  methods: {
    shouldShow({ state }) {
      return Boolean(iframeInsertPluginKey.getState(state));
    },

    insertRange() {
      return iframeInsertPluginKey.getState(this.tiptapEditor.state);
    },

    cancel() {
      this.tiptapEditor.chain().focus().setMeta(iframeInsertPluginKey, null).run();
    },

    async insert() {
      this.isUpdating = true;

      const { canonicalSrc } = this;
      const embed = await this.contentEditor.resolveEmbed(canonicalSrc);

      this.isUpdating = false;

      if (!embed) {
        this.embedError = embedNotAllowedMessage();
        return;
      }

      const range = this.insertRange();
      if (!range) return;

      this.tiptapEditor
        .chain()
        .focus()
        .insertContentAt(range, {
          type: Iframe.name,
          attrs: {
            src: embed.src,
            canonicalSrc,
            providerId: embed.providerId,
            alt: this.alt || null,
          },
        })
        .setMeta(iframeInsertPluginKey, null)
        .run();
    },

    onHidden() {
      this.canonicalSrc = '';
      this.alt = '';
      this.embedError = null;

      if (this.insertRange()) {
        this.tiptapEditor.commands.setMeta(iframeInsertPluginKey, null);
      }
    },
  },
};
</script>
<template>
  <bubble-menu
    data-testid="iframe-insert-bubble-menu"
    class="gl-rounded-lg gl-bg-overlap gl-shadow"
    plugin-key="bubbleMenuIframeInsert"
    :should-show="shouldShow"
    @hidden="onHidden"
  >
    <gl-form
      class="bubble-menu-form gl-w-full gl-p-4"
      :aria-label="s__('ContentEditor|Insert embedded content')"
      @submit.prevent="insert"
    >
      <gl-form-group
        :label="__('URL')"
        label-for="iframe-insert-src"
        :state="srcState"
        :invalid-feedback="embedError"
      >
        <gl-form-input
          id="iframe-insert-src"
          v-model="canonicalSrc"
          data-testid="iframe-insert-src"
          :state="srcState"
          autofocus
          @input="embedError = null"
        />
      </gl-form-group>
      <gl-form-group :label="__('Title')" label-for="iframe-insert-alt">
        <gl-form-input id="iframe-insert-alt" v-model="alt" data-testid="iframe-insert-alt" />
      </gl-form-group>
      <div class="gl-flex gl-justify-end">
        <gl-button class="gl-mr-3" data-testid="cancel-iframe-insert" @click="cancel">{{
          __('Cancel')
        }}</gl-button>
        <gl-button variant="confirm" type="submit" :loading="isUpdating">{{
          __('Insert')
        }}</gl-button>
      </div>
    </gl-form>
  </bubble-menu>
</template>
