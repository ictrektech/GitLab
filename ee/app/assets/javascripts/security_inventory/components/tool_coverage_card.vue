<script>
import { GlButton, GlCollapsibleListbox, GlLink, GlPopover, GlSkeletonLoader } from '@gitlab/ui';
import { mapValues } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, __, formatNumber } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { aggregateAnalyzerStatuses, visibleScannerGroups } from 'ee/security_inventory/utils';
import {
  ALL_SCANNERS_KEY,
  SECURITY_CONFIGURATION_PATH,
  SCANNER_POPOVER_LABELS,
  SCANNER_TYPES,
  TOOL_NOT_ENABLED,
  TOOL_STATUS_CONFIG,
} from '../constants';
import GroupToolCoverageQuery from '../graphql/group_tool_coverage.query.graphql';
import EnableScannersLink from './enable_scanners_link.vue';
import ToolCoverageChart from './tool_coverage_chart.vue';

export default {
  name: 'ToolCoverageCard',
  components: {
    GlButton,
    GlCollapsibleListbox,
    GlLink,
    GlPopover,
    GlSkeletonLoader,
    EnableScannersLink,
    ToolCoverageChart,
  },
  props: {
    fullPath: {
      type: String,
      required: true,
    },
    selection: {
      type: Object,
      required: false,
      default: () => ({ scanner: ALL_SCANNERS_KEY, status: null }),
    },
  },
  emits: ['update:selection'],
  data() {
    return {
      group: null,
      hasError: false,
      hoveredKey: null,
    };
  },
  apollo: {
    group: {
      query: GroupToolCoverageQuery,
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
    scannerGroups() {
      return visibleScannerGroups();
    },
    subScannersByTile() {
      return mapValues(this.scannerGroups, (scanners, tile) =>
        scanners.filter((scanner) => scanner !== tile),
      );
    },
    scannerItems() {
      const items = [{ value: ALL_SCANNERS_KEY, text: this.$options.i18n.allScanners }];

      Object.entries(this.subScannersByTile).forEach(([tile, subScanners]) => {
        items.push({ value: tile, text: SCANNER_TYPES[tile].name });
        subScanners.forEach((subScanner) => {
          items.push({ value: subScanner, text: SCANNER_POPOVER_LABELS[subScanner] });
        });
      });

      return items;
    },
    selectedScanner() {
      return this.selection.scanner;
    },
    isSubScannerSelected() {
      return Object.values(this.subScannersByTile).flat().includes(this.selectedScanner);
    },
    selectedAnalyzerTypes() {
      if (this.selectedScanner === ALL_SCANNERS_KEY) {
        return Object.values(this.scannerGroups).flat();
      }
      return this.scannerGroups[this.selectedScanner] ?? [];
    },
    statusCounts() {
      // aggregateAnalyzerStatuses drops or remaps sub-scanners, so read their own row.
      if (this.isSubScannerSelected) {
        return (
          this.group?.analyzerStatuses?.find(
            ({ analyzerType }) => analyzerType === this.selectedScanner,
          ) ?? {}
        );
      }
      return aggregateAnalyzerStatuses(this.group?.analyzerStatuses, this.selectedAnalyzerTypes);
    },
    segments() {
      const rows = Object.entries(TOOL_STATUS_CONFIG).map(([status, { text, fieldKey, color }]) => {
        const count = this.statusCounts[fieldKey] ?? 0;
        return {
          key: status,
          label: text,
          count,
          color,
          isSelected: this.selection.status === status,
          isHovered: this.hoveredKey === status,
        };
      });

      const total = rows.reduce((sum, { count }) => sum + count, 0);

      return rows.map((row) => ({
        ...row,
        formattedCount: formatNumber(row.count),
        formattedPercent: total > 0 ? `${Math.round((row.count / total) * 100)}%` : '0%',
      }));
    },
    configurationPath() {
      if (!this.group?.webPath) return null;
      return `${this.group.webPath}${SECURITY_CONFIGURATION_PATH}`;
    },
  },
  methods: {
    helpPopoverTarget() {
      return this.$refs.helpTrigger?.$el;
    },
    selectScanner(scanner) {
      if (scanner === this.selectedScanner) return;

      this.$emit('update:selection', { scanner, status: null });
    },
    toggleStatus(status) {
      const nextStatus = this.selection.status === status ? null : status;

      this.$emit('update:selection', { scanner: this.selectedScanner, status: nextStatus });
    },
    hoverStatus(key) {
      this.hoveredKey = key;
    },
  },
  i18n: {
    title: s__('SecurityInventory|Tool coverage'),
    helpContent: s__(
      'SecurityInventory|Coverage across all scanners, or for a single scanner, based on the scan status of the most recent pipeline on the default branch.',
    ),
    helpAriaLabel: s__('SecurityInventory|More information about tool coverage'),
    learnMore: __('Learn more'),
    allScanners: s__('SecurityInventory|Any scanner'),
    viewConfiguration: s__('SecurityInventory|Scanners configuration'),
  },
  notEnabledStatus: TOOL_NOT_ENABLED,
  helpPagePath: helpPagePath('user/application_security/security_inventory/_index', {
    anchor: 'scanner-coverage',
  }),
};
</script>

<template>
  <div
    v-if="!hasError"
    class="gl-border gl-mb-5 gl-max-w-62 gl-rounded-base gl-border-default gl-p-5"
    data-testid="tool-coverage-card"
  >
    <div class="gl-mb-3 gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
      <h2 class="gl-heading-4 gl-mb-0 gl-flex gl-items-center gl-gap-2">
        {{ $options.i18n.title }}
        <gl-button
          ref="helpTrigger"
          icon="information-o"
          variant="link"
          class="gl-text-subtle"
          :aria-label="$options.i18n.helpAriaLabel"
        />
        <gl-popover :target="helpPopoverTarget" :title="$options.i18n.title">
          <p class="gl-mb-3">{{ $options.i18n.helpContent }}</p>
          <gl-link :href="$options.helpPagePath" target="_blank" data-testid="learn-more-link">
            {{ $options.i18n.learnMore }}
          </gl-link>
        </gl-popover>
      </h2>
      <gl-collapsible-listbox
        :selected="selectedScanner"
        :items="scannerItems"
        :disabled="isLoading"
        size="small"
        data-testid="scanner-listbox"
        @select="selectScanner"
      />
    </div>

    <gl-skeleton-loader v-if="isLoading" :height="60">
      <rect y="6" width="180" height="12" rx="2" />
      <rect y="26" width="240" height="12" rx="2" />
      <rect y="46" width="140" height="12" rx="2" />
    </gl-skeleton-loader>

    <template v-else>
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-6">
        <tool-coverage-chart
          :segments="segments"
          @select-status="toggleStatus"
          @hover-status="hoverStatus"
        />

        <ul class="gl-m-0 gl-grow gl-list-none gl-p-0">
          <li
            v-for="segment in segments"
            :key="segment.key"
            class="gl-group gl-flex gl-items-center gl-gap-3 gl-rounded-base gl-p-2"
            :class="
              segment.isSelected
                ? 'gl-bg-feedback-info gl-font-bold'
                : 'gl-bg-transparent hover:gl-bg-strong'
            "
            :data-testid="`legend-item-${segment.key}`"
          >
            <button
              type="button"
              class="gl-flex gl-items-center gl-gap-3 gl-border-0 gl-bg-transparent gl-p-0 gl-text-left gl-shadow-none focus:gl-focus"
              :aria-pressed="String(segment.isSelected)"
              :data-testid="`legend-row-${segment.key}`"
              @click="toggleStatus(segment.key)"
              @mouseenter="hoverStatus(segment.key)"
              @mouseleave="hoverStatus(null)"
            >
              <span
                class="gl-size-4 gl-shrink-0 gl-rounded-md"
                :style="{ backgroundColor: segment.color }"
              ></span>
              <span>{{ segment.label }}</span>
            </button>
            <enable-scanners-link
              v-if="segment.key === $options.notEnabledStatus"
              :web-path="group?.webPath"
            />
            <span class="gl-ml-auto gl-font-bold" data-testid="legend-percent">{{
              segment.formattedPercent
            }}</span>
            <span class="gl-text-subtle" data-testid="legend-count">{{
              segment.formattedCount
            }}</span>
          </li>
        </ul>
      </div>
    </template>

    <gl-link
      v-if="configurationPath"
      :href="configurationPath"
      class="gl-mt-3 gl-inline-block"
      data-testid="view-configuration-link"
    >
      {{ $options.i18n.viewConfiguration }}
    </gl-link>
  </div>
</template>
