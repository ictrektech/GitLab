<script>
import { defineComponent } from 'vue';
import { GlLoadingIcon, GlSprintf, GlTooltipDirective } from '@gitlab/ui';
import { formatNumber, n__, s__, sprintf } from '~/locale';
import { DOMAIN_COLORS, ORBIT_AREAS } from 'ee/orbit/constants';
import { LOAD_STATUS, ROUTE_SCHEMA } from '../constants';

const COMPACT_NUMBER = { notation: 'compact', maximumFractionDigits: 1 };

export default defineComponent({
  name: 'OverviewStatsCard',
  components: { GlLoadingIcon, GlSprintf },
  directives: { GlTooltip: GlTooltipDirective },
  props: {
    groupCount: {
      type: Number,
      required: true,
    },
    graphStats: {
      type: Object,
      required: false,
      default: null,
    },
    status: {
      type: String,
      required: true,
      validator: (status) => Object.values(LOAD_STATUS).includes(status),
    },
  },
  computed: {
    isLoading() {
      return this.status === LOAD_STATUS.LOADING;
    },
    hasFailed() {
      return this.status === LOAD_STATUS.FAILED;
    },
    totalMessage() {
      return n__(
        'Orbit|%{count} %{labelStart}item%{labelEnd}',
        'Orbit|%{count} %{labelStart}items%{labelEnd}',
        this.total,
      );
    },
    total() {
      return Object.values(this.graphStats.domains).reduce((sum, count) => sum + count, 0);
    },
    compactTotal() {
      return formatNumber(this.total, COMPACT_NUMBER);
    },
    exactTotal() {
      return formatNumber(this.total);
    },
    areas() {
      return ORBIT_AREAS.map((area) => ({
        ...area,
        color: DOMAIN_COLORS[area.key],
        count: formatNumber(this.graphStats.domains[area.key] ?? 0),
      }));
    },
    projectCount() {
      return this.graphStats.indexedProjects;
    },
    scopeText() {
      return sprintf(s__('Orbit|in %{groups} and %{projects}'), {
        groups: sprintf(n__('Orbit|%{count} group', 'Orbit|%{count} groups', this.groupCount), {
          count: formatNumber(this.groupCount),
        }),
        projects: sprintf(
          n__('Orbit|%{count} project', 'Orbit|%{count} projects', this.projectCount),
          {
            count: formatNumber(this.projectCount),
          },
        ),
      });
    },
  },
  ROUTE_SCHEMA,
});
</script>

<template>
  <div
    class="gl-border gl-rounded-xl gl-border-default gl-bg-default gl-p-5 gl-shadow-sm"
    data-testid="overview-stats-card"
  >
    <p class="gl-mb-3 gl-text-sm gl-font-bold gl-text-default">{{ s__('Orbit|On your map') }}</p>

    <gl-loading-icon v-if="isLoading" size="md" class="gl-my-5" />

    <p
      v-else-if="hasFailed"
      class="gl-mb-3 gl-text-sm gl-text-subtle"
      data-testid="overview-stats-failed"
    >
      {{ s__('Orbit|Counts are not available right now. Try again later.') }}
    </p>

    <template v-else>
      <p
        class="gl-mb-1 gl-flex gl-flex-wrap gl-items-baseline gl-gap-x-2 gl-text-size-h-display gl-font-bold gl-leading-1"
        data-testid="overview-stats-total"
      >
        <gl-sprintf :message="totalMessage">
          <template #count>
            <span
              v-gl-tooltip
              :title="exactTotal"
              tabindex="0"
              data-testid="overview-stats-total-count"
              >{{ compactTotal }}</span
            >
          </template>
          <template #label="{ content }">
            <span class="gl-text-base gl-font-normal gl-text-subtle">{{ content }}</span>
          </template>
        </gl-sprintf>
      </p>
      <p class="gl-mb-0 gl-text-sm gl-text-subtle" data-testid="overview-stats-scope">
        {{ scopeText }}
      </p>

      <hr class="gl-my-3" />

      <ul class="gl-m-0 gl-list-none gl-p-0">
        <li
          v-for="area in areas"
          :key="area.key"
          class="gl-mb-3 gl-flex gl-items-center gl-justify-between gl-gap-3 gl-text-sm"
        >
          <span class="gl-flex gl-items-center gl-gap-3">
            <span
              class="gl-inline-block gl-h-2 gl-w-2 gl-shrink-0 gl-rounded-full"
              :style="{ backgroundColor: area.color }"
            ></span>
            {{ area.label }}
          </span>
          <span class="gl-tabular-nums gl-text-default">{{ area.count }}</span>
        </li>
      </ul>
    </template>

    <router-link :to="{ name: $options.ROUTE_SCHEMA }" class="gl-text-sm">
      {{ s__('Orbit|View the schema of each area') }}
    </router-link>
  </div>
</template>
