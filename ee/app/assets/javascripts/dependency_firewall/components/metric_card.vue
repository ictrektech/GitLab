<script>
import { GlCard, GlIcon, GlSkeletonLoader } from '@gitlab/ui';
import { formatNumber } from '~/locale';
import { ICON_VARIANT_TEXT_CLASSES } from '../constants';

export default {
  name: 'DependencyFirewallMetricCard',
  components: {
    GlCard,
    GlIcon,
    GlSkeletonLoader,
  },
  props: {
    title: {
      type: String,
      required: true,
    },
    value: {
      type: Number,
      required: true,
    },
    breakdown: {
      type: Array,
      required: false,
      default: () => [],
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    formattedValue() {
      return formatNumber(this.value);
    },
  },
  methods: {
    formatNumber,
    iconClass(variant) {
      return ICON_VARIANT_TEXT_CLASSES[variant];
    },
  },
};
</script>

<template>
  <gl-card>
    <gl-skeleton-loader v-if="loading" />
    <template v-else>
      <h2 class="gl-font-medium gl-m-0 gl-text-sm gl-text-subtle">{{ title }}</h2>
      <p class="gl-heading-1 gl-my-3 gl-tabular-nums">{{ formattedValue }}</p>
      <hr class="gl-my-3 gl-border-t-1 gl-border-subtle gl-border-t-solid" />
      <div class="gl-flex gl-flex-wrap gl-gap-4">
        <span
          v-for="item in breakdown"
          :key="item.key"
          class="gl-inline-flex gl-items-center gl-gap-2"
          :data-testid="`metric-breakdown-${item.key}`"
        >
          <gl-icon :name="item.icon" :class="iconClass(item.variant)" />
          <span class="gl-font-bold">{{ formatNumber(item.value) }}</span>
          <span class="gl-text-subtle">{{ item.label }}</span>
        </span>
      </div>
    </template>
  </gl-card>
</template>
