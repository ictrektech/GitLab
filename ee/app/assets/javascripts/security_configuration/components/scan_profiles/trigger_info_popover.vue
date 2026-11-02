<script>
import { GlButton, GlLink, GlPopover } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';

export default {
  name: 'TriggerInfoPopover',
  components: {
    GlButton,
    GlLink,
    GlPopover,
  },
  props: {
    anchor: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      required: false,
      default: '',
    },
    helpLink: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    buttonId() {
      // eslint-disable-next-line @gitlab/require-i18n-strings
      return `${this.anchor}-info`;
    },
    label() {
      return sprintf(s__('ScanProfiles|About %{trigger}'), { trigger: this.title });
    },
  },
};
</script>

<template>
  <span>
    <gl-button
      :id="buttonId"
      category="tertiary"
      size="small"
      icon="information-o"
      class="btn-icon"
      :aria-label="label"
      data-testid="trigger-info-button"
    />
    <gl-popover :target="buttonId" placement="top" boundary="viewport">
      {{ description }}
      <gl-link v-if="helpLink" :href="helpLink" target="_blank">{{ __('Learn more') }}</gl-link>
    </gl-popover>
  </span>
</template>
