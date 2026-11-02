<script>
import { GlIcon, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'ReadinessRow',
  components: {
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    row: {
      type: Object,
      required: true,
    },
  },
};
</script>

<template>
  <li data-testid="readiness-row" class="gl-flex gl-items-center gl-gap-3 gl-px-4 gl-py-2">
    <gl-icon
      :name="row.icon"
      :size="16"
      :variant="row.variant"
      :aria-label="row.stateLabel"
      class="gl-shrink-0"
    />
    <!-- The dotted underline marks the label as the place to hover for the details. -->
    <span
      v-if="row.detail"
      v-gl-tooltip
      :title="row.detail"
      tabindex="0"
      class="gl-min-w-0 gl-font-bold gl-underline gl-decoration-dotted gl-underline-offset-4"
      data-testid="readiness-row-label"
    >
      {{ row.label }}
    </span>
    <!-- A tooltip is never read out while browsing, and the detail is essential status. -->
    <span v-if="row.detail" class="gl-sr-only" data-testid="readiness-row-detail">
      {{ row.detail }}
    </span>
    <span v-else class="gl-min-w-0 gl-font-bold" data-testid="readiness-row-label">
      {{ row.label }}
    </span>
  </li>
</template>
