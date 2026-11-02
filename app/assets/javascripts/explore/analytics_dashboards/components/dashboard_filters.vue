<script>
import { GlFormGroup } from '@gitlab/ui';
import { s__ } from '~/locale';
import DateRangeFilter from './date_range_filter.vue';
import ScopePicker from './scope_picker.vue';
import { DATE_RANGE_OPTION_LAST_30_DAYS } from './constants';

export default {
  name: 'DashboardFilters',
  components: {
    GlFormGroup,
    DateRangeFilter,
    ScopePicker,
  },
  i18n: {
    region: s__('AnalyticsDashboards|Dashboard filters'),
    scopeLabel: s__('AnalyticsDashboards|Scope'),
  },
  props: {
    dashboardFilters: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    scopePaths: {
      type: Array,
      required: false,
      default: () => [],
    },
    // The range the page resolved for this load from the URL. The date
    // filter owns its selection after mount, so this only seeds it.
    dateRangeFilter: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['set-date-range', 'set-scope', 'ready', 'error', 'no-qualifying-groups'],
  computed: {
    scopeConfig() {
      return this.dashboardFilters?.scope ?? {};
    },
    showScopePicker() {
      return this.scopeConfig.enabled !== false;
    },
    scopeMultiSelect() {
      return this.scopeConfig.multiSelect === true;
    },
    scopeRequirePermissions() {
      return this.scopeConfig.requirePermissions ?? [];
    },
    scopeRequireDuoAgentPlatform() {
      return this.scopeConfig.requireDuoAgentPlatform === true;
    },
    dateRangeConfig() {
      return this.dashboardFilters?.dateRange ?? {};
    },
    showDateRangeFilter() {
      return this.dateRangeConfig.enabled !== false;
    },
    dateRangeDefaultOption() {
      return this.dateRangeConfig.defaultOption ?? DATE_RANGE_OPTION_LAST_30_DAYS;
    },
    dateRangeOptions() {
      return this.dateRangeConfig.options;
    },
    dateRangeLimit() {
      return this.dateRangeConfig.numberOfDaysLimit ?? 0;
    },
    dateRangeSelectedOption() {
      return this.dateRangeFilter.dateRangeOption ?? this.dateRangeDefaultOption;
    },
  },
  mounted() {
    // Call ready immediately if the scope picker is disabled
    if (!this.showScopePicker) this.$emit('ready');
  },
};
</script>
<template>
  <div
    data-testid="dashboard-filters"
    role="group"
    :aria-label="$options.i18n.region"
    class="gl-flex gl-flex-col gl-gap-5 md:gl-flex-row md:gl-gap-3"
  >
    <gl-form-group
      v-if="showScopePicker"
      class="gl-full-w gl-mb-0"
      :label="$options.i18n.scopeLabel"
    >
      <scope-picker
        :multi-select="scopeMultiSelect"
        :require-permissions="scopeRequirePermissions"
        :require-duo-agent-platform="scopeRequireDuoAgentPlatform"
        :initial-paths="scopePaths"
        @change="$emit('set-scope', $event)"
        @ready="$emit('ready')"
        @error="$emit('error', $event)"
        @no-qualifying-groups="$emit('no-qualifying-groups')"
      />
    </gl-form-group>
    <date-range-filter
      v-if="showDateRangeFilter"
      :default-option="dateRangeSelectedOption"
      :start-date="dateRangeFilter.startDate || null"
      :end-date="dateRangeFilter.endDate || null"
      :options="dateRangeOptions"
      :date-range-limit="dateRangeLimit"
      @change="$emit('set-date-range', $event)"
    />
  </div>
</template>
