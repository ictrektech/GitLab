<script>
import { GlSkeletonLoader } from '@gitlab/ui';
import { formatNumber, s__, sprintf } from '~/locale';

export default {
  name: 'StatsBarItem',
  components: {
    GlSkeletonLoader,
  },
  props: {
    label: {
      type: String,
      required: true,
    },
    // Null is "we could not read this", which must not render as a confident 0.
    value: {
      type: Number,
      required: false,
      default: null,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    // A capped count comes back as limit + 1, which reads as "limit+".
    limit: {
      type: Number,
      required: false,
      default: null,
    },
  },
  computed: {
    isUnknown() {
      return this.value === null;
    },
    formattedValue() {
      if (this.limit !== null && this.value > this.limit) {
        return sprintf(s__('PolicyStore|%{count}+'), { count: formatNumber(this.limit) });
      }

      return formatNumber(this.value);
    },
  },
};
</script>

<template>
  <div class="gl-flex-1 gl-rounded-lg gl-bg-subtle gl-p-2">
    <p class="gl-mb-2 gl-px-2 gl-pt-1 gl-text-sm gl-font-bold gl-text-secondary">{{ label }}</p>
    <div class="gl-border gl-rounded-base gl-border-default gl-bg-default gl-px-4 gl-py-3">
      <!-- The box is sized to the value's line box because the skeleton svg
           fills its container; without it the tile shifts when the value lands. -->
      <div v-if="loading" class="gl-flex gl-h-8 gl-w-12 gl-items-center">
        <gl-skeleton-loader :width="80" :height="16">
          <rect width="80" height="16" rx="4" />
        </gl-skeleton-loader>
      </div>
      <span v-else class="gl-text-size-h-display gl-font-bold" data-testid="stats-bar-item-value">
        <template v-if="isUnknown">
          <span aria-hidden="true">&mdash;</span>
          <span class="gl-sr-only">{{ s__('PolicyStore|Not available') }}</span>
        </template>
        <template v-else>{{ formattedValue }}</template>
      </span>
    </div>
  </div>
</template>
