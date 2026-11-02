<script>
import { GlButton, GlCard, GlSkeletonLoader } from '@gitlab/ui';
import { formatNumber } from '~/locale';

export default {
  name: 'OrganizationAccessMemberStats',
  components: { GlButton, GlCard, GlSkeletonLoader },
  props: {
    stats: {
      type: Array,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['filter'],
  methods: {
    formatNumber,
  },
};
</script>

<template>
  <div class="gl-grid gl-gap-5 md:gl-grid-cols-3">
    <gl-card v-for="stat in stats" :key="stat.title" data-testid="member-stat">
      <template #header>
        <h2 class="gl-heading-5 gl-m-0" data-testid="member-stat-title">{{ stat.title }}</h2>
      </template>
      <gl-skeleton-loader v-if="loading" :lines="1" :width="100" data-testid="member-stat-loader" />
      <div v-else class="gl-heading-1 gl-m-0" data-testid="member-stat-value">
        {{ formatNumber(stat.value) }}
      </div>
      <gl-button
        v-if="stat.filter"
        variant="link"
        size="small"
        :aria-label="stat.filterLabel"
        data-testid="member-stat-filter"
        @click="$emit('filter', stat.filter)"
      >
        {{ s__('OrganizationAccess|Filter list') }}
      </gl-button>
    </gl-card>
  </div>
</template>
