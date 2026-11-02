<script>
import { GlButton, GlLink, GlPopover } from '@gitlab/ui';

export default {
  name: 'FlowUnavailableButton',
  components: {
    GlButton,
    GlLink,
    GlPopover,
  },
  // Bound by hand so the explicit `disabled` below beats a caller's `:disabled`
  // under Vue 3, where fallthrough attrs would otherwise win.
  inheritAttrs: false,
  props: {
    message: {
      type: String,
      required: false,
      default: '',
    },
    helpPath: {
      type: String,
      required: false,
      default: '',
    },
    size: {
      type: String,
      default: 'small',
      required: false,
    },
    variant: {
      type: String,
      default: 'default',
      required: false,
    },
    category: {
      type: String,
      default: 'primary',
      required: false,
    },
  },
};
</script>

<template>
  <gl-button
    ref="button"
    v-bind="$attrs"
    disabled
    accessible-disabled
    :category="category"
    icon="tanuki-ai"
    :size="size"
    :variant="variant"
    data-testid="duo-workflow-action-button"
  >
    <gl-popover
      :target="() => $refs.button && $refs.button.$el"
      triggers="hover focus"
      placement="top"
      boundary="viewport"
    >
      <p class="gl-mb-0">
        <slot name="message">{{ message }}</slot>
        <template v-if="helpPath">
          <gl-link :href="helpPath" target="_blank">{{ __('Learn more') }}</gl-link
          >.
        </template>
      </p>
    </gl-popover>
    <slot></slot>
  </gl-button>
</template>
