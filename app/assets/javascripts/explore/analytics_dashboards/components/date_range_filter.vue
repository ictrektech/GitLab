<script>
import {
  GlBadge,
  GlCollapsibleListbox,
  GlDaterangePicker,
  GlFormGroup,
  GlIcon,
  GlTooltipDirective,
} from '@gitlab/ui';
import { createDateTimeFormat, n__ } from '~/locale';
import { dateRangeFilterToUtc, dateRangeOptionToFilter, getDateRangeOption } from './utils';
import {
  TODAY,
  DATE_RANGE_OPTIONS,
  DATE_RANGE_OPTION_KEYS,
  DEFAULT_DATE_RANGE_OPTIONS,
  DEFAULT_SELECTED_DATE_RANGE_OPTION,
} from './constants';

export default {
  name: 'AnalyticsDashboardsDateRangeFilter',
  components: {
    GlBadge,
    GlCollapsibleListbox,
    GlDaterangePicker,
    GlFormGroup,
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    defaultOption: {
      type: String,
      required: false,
      default: DEFAULT_SELECTED_DATE_RANGE_OPTION,
    },
    startDate: {
      type: Date,
      required: false,
      default: null,
    },
    endDate: {
      type: Date,
      required: false,
      default: null,
    },
    dateRangeLimit: {
      type: Number,
      required: false,
      default: 0,
    },
    options: {
      type: Array,
      required: false,
      default: () => DEFAULT_DATE_RANGE_OPTIONS,
    },
  },
  emits: ['change'],
  data() {
    return {
      selectedItem: this.options.includes(this.defaultOption)
        ? getDateRangeOption(this.defaultOption)
        : getDateRangeOption(DEFAULT_SELECTED_DATE_RANGE_OPTION),
    };
  },
  computed: {
    dateRange: {
      get() {
        return { startDate: this.startDate, endDate: this.endDate };
      },
      // GlDaterangePicker emits each bound as the user picks it, so a custom range arrives
      // half filled. A panel would fill the missing bound with a default and query a window
      // nobody asked for, so hold the change until both are set.
      set({ startDate, endDate }) {
        if (!startDate || !endDate) return;

        this.$emit(
          'change',
          dateRangeOptionToFilter({
            ...this.selectedItem,
            startDate,
            endDate,
          }),
        );
      },
    },
    showDateRangeLimit() {
      return Boolean(this.selectedItem.showDateRangePicker && this.dateRangeLimit);
    },
    dateRangeLimitText() {
      return n__(
        'Analytics|Limited to %d day',
        'Analytics|Limited to %d days',
        this.dateRangeLimit,
      );
    },
    // The presets are already whole UTC days, but a custom range is picked in local time.
    displayedDateRange() {
      if (!this.selectedItem.showDateRangePicker) return this.selectedItem;

      return dateRangeFilterToUtc(
        dateRangeOptionToFilter({ ...this.selectedItem, ...this.dateRange }),
      );
    },
    dateRangeText() {
      const { startDate, endDate } = this.displayedDateRange;
      if (!startDate || !endDate) return '';

      return createDateTimeFormat({ dateStyle: 'medium', timeZone: 'UTC' }).formatRange(
        startDate,
        endDate,
      );
    },
    dropdownItems() {
      return this.options
        .filter((opt) => DATE_RANGE_OPTION_KEYS.includes(opt))
        .map((key) => {
          const item = getDateRangeOption(key);
          return { text: item.text, value: key };
        });
    },
  },
  methods: {
    selectItem(key) {
      const item = getDateRangeOption(key);
      this.selectedItem = item;

      const { startDate, endDate, showDateRangePicker = false } = item;
      if (!showDateRangePicker && startDate && endDate) {
        this.dateRange = { startDate, endDate };
      }
    },
  },
  DATE_RANGE_OPTIONS,
  TODAY,
};
</script>

<template>
  <div
    data-testid="dashboard-filters-date-range"
    class="gl-flex gl-w-full gl-gap-3 @sm/panel:gl-w-auto @sm/panel:gl-flex-row @sm/panel:gl-items-end"
    :class="{ 'gl-flex-col': selectedItem.showDateRangePicker }"
  >
    <gl-form-group class="gl-mb-0">
      <template #label>
        {{ s__('AnalyticsDashboards|Date range') }}
        <gl-icon
          v-gl-tooltip
          :title="s__('Analytics|Dates and times are displayed in the UTC timezone.')"
          name="information-o"
          variant="subtle"
        />
      </template>
      <gl-collapsible-listbox
        class="gl-w-full @sm/panel:gl-w-auto"
        :items="dropdownItems"
        :selected="selectedItem.key"
        @select="selectItem($event)"
      />
    </gl-form-group>
    <gl-daterange-picker
      v-if="selectedItem.showDateRangePicker"
      v-model="dateRange"
      :default-start-date="dateRange.startDate"
      :default-end-date="dateRange.endDate"
      :default-max-date="$options.TODAY"
      :max-date-range="dateRangeLimit"
      :to-label="__('To')"
      :from-label="__('From')"
      start-picker-class="gl-flex-col @sm:gl-gap-y-0"
      end-picker-class="gl-flex-col @sm:gl-gap-y-0"
      same-day-selection
    />
    <div
      v-if="dateRangeText || showDateRangeLimit"
      class="gl-flex gl-min-h-7 gl-flex-wrap gl-items-center gl-gap-3"
    >
      <span v-if="dateRangeText" data-testid="date-range-text">{{ dateRangeText }}</span>
      <gl-badge v-if="showDateRangeLimit" variant="info" icon="information-o">
        {{ dateRangeLimitText }}
      </gl-badge>
    </div>
  </div>
</template>
