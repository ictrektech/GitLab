<script>
import { GlPopover } from '@gitlab/ui';
import { SCAN_PROFILE_I18N } from '~/security_configuration/constants';

const i18n = {
  tooltipTitle: SCAN_PROFILE_I18N.tooltipTitle,
};

export default {
  name: 'InsufficientPermissionsPopover',
  components: {
    GlPopover,
  },
  props: {
    target: {
      type: [String, Function],
      required: true,
    },
    placement: {
      type: String,
      required: false,
      default: 'top',
    },
    description: {
      type: String,
      required: false,
      default: SCAN_PROFILE_I18N.accessLevelTooltipDescription,
    },
  },
  i18n,
};
</script>

<template>
  <gl-popover :target="target" :placement="placement" boundary="viewport">
    <template #title>
      {{ $options.i18n.tooltipTitle }}
    </template>
    {{ description }}
  </gl-popover>
</template>
