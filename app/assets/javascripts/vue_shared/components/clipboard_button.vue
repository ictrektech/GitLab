<script>
/**
 * Falls back to the code used in `javascripts/behaviors/copy_to_clipboard.js`
 *
 * Renders a button with a clipboard icon that copies the content of `data-clipboard-text`
 * when clicked.
 *
 * After copying, the icon briefly changes to a check (or an error icon when copying
 * failed), and the result is announced to screen readers with `ariaNotify`.
 *
 * @example
 * <clipboard-button
 *   title="Copy"
 *   text="Content to be copied"
 *   css-class="gl-border-0 gl-bg-transparent"
 * />
 */
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { sanitize } from '~/lib/dompurify';

import { __ } from '~/locale';
import {
  CLIPBOARD_SUCCESS_EVENT,
  CLIPBOARD_ERROR_EVENT,
  I18N_ERROR_MESSAGE,
} from '~/behaviors/copy_to_clipboard';
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';

const FEEDBACK_DURATION_MS = 2000;

export default {
  name: 'ClipboardButton',
  i18n: {
    copied: __('Copied to clipboard.'),
    error: I18N_ERROR_MESSAGE,
  },
  CLIPBOARD_SUCCESS_EVENT,
  CLIPBOARD_ERROR_EVENT,
  FEEDBACK_DURATION_MS,
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  components: {
    GlButton,
  },
  mixins: [glListenersMixin, glSlotsMixin],
  props: {
    text: {
      type: String,
      required: true,
    },
    gfm: {
      type: String,
      required: false,
      default: null,
    },
    title: {
      type: String,
      required: true,
    },
    tooltipPlacement: {
      type: String,
      required: false,
      default: 'top',
    },
    tooltipContainer: {
      type: [String, Boolean],
      required: false,
      default: false,
    },
    tooltipBoundary: {
      type: String,
      required: false,
      default: null,
    },
    cssClass: {
      type: String,
      required: false,
      default: null,
    },
    category: {
      type: String,
      required: false,
      default: 'secondary',
    },
    size: {
      type: String,
      required: false,
      default: 'medium',
    },
    variant: {
      type: String,
      required: false,
      default: 'default',
    },
    icon: {
      type: String,
      required: false,
      default: 'copy-to-clipboard',
    },
  },
  data() {
    return {
      feedbackIcon: null,
      feedbackTimeout: null,
    };
  },
  computed: {
    clipboardText() {
      if (this.gfm !== null) {
        return JSON.stringify({ text: this.text, gfm: this.gfm });
      }
      return this.text;
    },
    tooltipDirectiveOptions() {
      return {
        placement: this.tooltipPlacement,
        container: this.tooltipContainer,
        boundary: this.tooltipBoundary,
      };
    },
    sanitizedTitle() {
      return sanitize(this.title);
    },
    currentIcon() {
      return this.feedbackIcon || this.icon;
    },
  },
  beforeDestroy() {
    clearTimeout(this.feedbackTimeout);
  },
  methods: {
    showFeedback(icon, message) {
      this.feedbackIcon = icon;
      this.$el.ariaNotify(message);

      clearTimeout(this.feedbackTimeout);
      this.feedbackTimeout = setTimeout(() => {
        this.feedbackIcon = null;
      }, FEEDBACK_DURATION_MS);
    },
  },
};
</script>

<template>
  <gl-button
    v-gl-tooltip.hover.focus.viewport.html="tooltipDirectiveOptions"
    :class="cssClass"
    :title="sanitizedTitle"
    :data-clipboard-text="clipboardText"
    data-clipboard-handle-tooltip="false"
    :category="category"
    :size="size"
    :icon="currentIcon"
    :variant="variant"
    :aria-label="sanitizedTitle"
    @[$options.CLIPBOARD_SUCCESS_EVENT]="showFeedback('check', $options.i18n.copied)"
    @[$options.CLIPBOARD_ERROR_EVENT]="showFeedback('error', $options.i18n.error)"
    v-on="glListeners()"
  >
    <template v-if="glSlots().default" #default><slot></slot></template>
  </gl-button>
</template>
