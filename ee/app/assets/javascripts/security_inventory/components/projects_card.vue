<script>
import { GlButton, GlPopover, GlSkeletonLoader } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, n__, formatNumber, sprintf } from '~/locale';
import GroupSecurityPostureCountersQuery from 'ee/security_configuration/graphql/scan_profiles/group_security_posture_counters.query.graphql';
import {
  LIGHT_GRAY,
  PROJECTS_CARD_STATUSES,
  STATUS_FILTER_LABELS,
  STATUS_FILTER_TO_TOOL_STATUS,
  STATUS_UNPROTECTED,
  TOOL_STATUS_CONFIG,
} from '../constants';
import EnableScannersLink from './enable_scanners_link.vue';
import SegmentedBar from './segmented_bar.vue';

export default {
  name: 'ProjectsCard',
  components: {
    GlButton,
    GlPopover,
    GlSkeletonLoader,
    EnableScannersLink,
    SegmentedBar,
  },
  props: {
    fullPath: {
      type: String,
      required: true,
    },
    selectedStatus: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['update:selected-status'],
  data() {
    return {
      group: null,
      hasError: false,
    };
  },
  apollo: {
    group: {
      query: GroupSecurityPostureCountersQuery,
      variables() {
        return { fullPath: this.fullPath };
      },
      update({ group }) {
        this.hasError = false;
        return group;
      },
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.group.loading;
    },
    counters() {
      return this.group?.securityPostureCounters ?? {};
    },
    total() {
      return this.counters.total ?? 0;
    },
    countByStatus() {
      const { withFailures = 0, withStale = 0, withScanners = 0 } = this.counters;

      return {
        NEEDS_ATTENTION: withFailures,
        STALE_SCANS: withStale,
        UNPROTECTED: Math.max(this.total - withScanners, 0),
      };
    },
    rows() {
      return PROJECTS_CARD_STATUSES.map((status) => {
        const count = this.countByStatus[status];
        const { color } = TOOL_STATUS_CONFIG[STATUS_FILTER_TO_TOOL_STATUS[status]];

        return {
          key: status,
          label: STATUS_FILTER_LABELS[status],
          count,
          isSelected: this.selectedStatus === status,
          formattedCount: formatNumber(count),
          formattedPercent: this.total > 0 ? `${Math.round((count / this.total) * 100)}%` : '0%',
          barSegments: [
            { key: 'filled', count, color },
            { key: 'track', count: Math.max(this.total - count, 0), color: LIGHT_GRAY },
          ],
        };
      });
    },
    totalText() {
      return sprintf(
        n__(
          'SecurityInventory|of %{total} project',
          'SecurityInventory|of %{total} projects',
          this.total,
        ),
        { total: formatNumber(this.total) },
      );
    },
  },
  i18n: {
    title: s__('SecurityInventory|Projects'),
    helpContent: s__(
      'SecurityInventory|Counts of projects that need attention, have stale scans, or are unprotected, out of all projects in this group. A project can appear in more than one category.',
    ),
    helpAriaLabel: s__('SecurityInventory|More information about projects'),
  },
  methods: {
    helpPopoverTarget() {
      return this.$refs.helpTrigger?.$el;
    },
    toggleStatus(status) {
      const nextStatus = this.selectedStatus === status ? null : status;

      this.$emit('update:selected-status', nextStatus);
    },
  },
  unprotectedStatus: STATUS_UNPROTECTED,
};
</script>

<template>
  <div
    v-if="!hasError"
    class="gl-border gl-mb-5 gl-w-62 gl-rounded-base gl-border-default gl-p-5"
    data-testid="projects-card"
  >
    <h2 class="gl-heading-4 gl-mb-3 gl-flex gl-items-center gl-gap-2">
      {{ $options.i18n.title }}
      <gl-button
        ref="helpTrigger"
        icon="information-o"
        variant="link"
        class="gl-text-subtle"
        :aria-label="$options.i18n.helpAriaLabel"
      />
      <gl-popover :target="helpPopoverTarget" :title="$options.i18n.title">
        <p class="gl-mb-0">{{ $options.i18n.helpContent }}</p>
      </gl-popover>
    </h2>

    <gl-skeleton-loader v-if="isLoading" :height="60">
      <rect y="6" width="180" height="12" rx="2" />
      <rect y="26" width="240" height="12" rx="2" />
      <rect y="46" width="140" height="12" rx="2" />
    </gl-skeleton-loader>

    <template v-else>
      <ul class="gl-m-0 gl-list-none gl-p-0">
        <li
          v-for="row in rows"
          :key="row.key"
          class="gl-group gl-mb-3 gl-rounded-base gl-p-2 last:gl-mb-0"
          :class="
            row.isSelected
              ? 'gl-bg-feedback-info gl-font-bold'
              : 'gl-bg-transparent hover:gl-bg-strong'
          "
          :data-testid="`project-status-row-${row.key}`"
        >
          <button
            type="button"
            class="gl-w-full gl-border-0 gl-bg-transparent gl-p-0 gl-text-left gl-shadow-none focus:gl-focus"
            :aria-pressed="String(row.isSelected)"
            :data-testid="`project-status-button-${row.key}`"
            @click="toggleStatus(row.key)"
          >
            <div class="gl-flex gl-items-center gl-gap-3">
              <span>{{ row.label }}</span>
              <enable-scanners-link
                v-if="row.key === $options.unprotectedStatus"
                :web-path="group?.webPath"
              />
              <span class="gl-ml-auto">
                <span class="gl-text-subtle" data-testid="row-count">{{ row.formattedCount }}</span>
                <span class="gl-ml-2 gl-font-bold" data-testid="row-percent">{{
                  row.formattedPercent
                }}</span>
              </span>
            </div>
            <segmented-bar class="gl-mt-2" :segments="row.barSegments" />
          </button>
        </li>
      </ul>

      <p class="gl-mb-0 gl-mt-3 gl-text-subtle" data-testid="total-projects">
        {{ totalText }}
      </p>
    </template>
  </div>
</template>
