<script>
import {
  GlAlert,
  GlCollapsibleListbox,
  GlExperimentBadge,
  GlFormGroup,
  GlLink,
  GlSkeletonLoader,
  GlSprintf,
  GlTab,
  GlTableLite,
  GlTabs,
} from '@gitlab/ui';
import axios from '~/lib/utils/axios_utils';
import { dayAfter, isValidDate, localeDateFormat, nDaysBefore } from '~/lib/utils/datetime_utility';
import { helpPagePath } from '~/helpers/help_page_helper';
import {
  activeSessionHistoryAdminDatabaseDiagnosticsPath,
  metricsAndProfilingAdminApplicationSettingsPath,
} from '~/lib/utils/path_helpers/instance_admin';
import { s__, sprintf } from '~/locale';
import DatetimeRangePicker from '~/observability/components/datetime_range_picker.vue';
import {
  CUSTOM_DATE_RANGE_OPTION,
  TIME_RANGE_OPTIONS,
  TIME_RANGE_OPTIONS_VALUES,
} from '~/observability/constants';
import { periodToDate } from '~/observability/utils';
import {
  activeSessionHistoryErrorMessage,
  activeSessionHistoryNumberFields,
  formatActiveSessions,
  formatShareOfLoad,
} from '../utils';
import ActiveSessionHistoryQueries from './active_session_history_queries.vue';

// Anything but this endpoint's JSON, such as a sign-in page, is an error.
const assertJson = (data, key) => {
  if (typeof data?.[key] !== 'boolean') throw new Error();
};

const MINUTE_MS = 60 * 1000;
// The endpoint reads pg_ash's rollups, for up to 24 hours starting up to 30 days back.
const MAX_RANGE_MS = 24 * 60 * MINUTE_MS;
// The endpoint widens a shorter time range to this, so pg_ash reads its rollups.
const MIN_RANGE_MS = 61 * MINUTE_MS;
// In calendar days, counting the start day, so a range can cross midnight.
const MAX_RANGE_DAYS = 2;
const LOOKBACK_DAYS = 30;
const { ONE_HOUR, FOUR_HOURS, TWELVE_HOURS, ONE_DAY } = TIME_RANGE_OPTIONS_VALUES;

export default {
  name: 'ActiveSessionHistoryApp',
  components: {
    ActiveSessionHistoryQueries,
    DatetimeRangePicker,
    GlAlert,
    GlCollapsibleListbox,
    GlExperimentBadge,
    GlFormGroup,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
    GlTab,
    GlTableLite,
    GlTabs,
  },
  data() {
    return {
      isLoading: false,
      error: null,
      summary: null,
      loadId: 0,
      resultsTabIndex: 0,
      dateRange: { value: ONE_HOUR, startDate: null, endDate: null },
      now: new Date(),
    };
  },
  computed: {
    isInstalled() {
      return Boolean(this.summary?.installed);
    },
    isSupported() {
      return this.summary?.supported !== false;
    },
    hasSamples() {
      return this.isInstalled && this.isSupported && this.summary.wait_event_types.length > 0;
    },
    settingsPath() {
      return metricsAndProfilingAdminApplicationSettingsPath({ anchor: 'js-pg-ash-settings' });
    },
    // The server counts 30 days in UTC, so a clock change does not move the limit.
    minDate() {
      return nDaysBefore(this.now, LOOKBACK_DAYS, { utc: true });
    },
    // The picker allows starts up to the day before this, so a range can start today.
    maxDate() {
      return dayAfter(this.now);
    },
    isCustomDateRange() {
      return this.dateRange.value === CUSTOM_DATE_RANGE_OPTION;
    },
    hasCustomDates() {
      return isValidDate(this.dateRange.startDate) && isValidDate(this.dateRange.endDate);
    },
    // Checks the range the endpoint reads: aligned to whole minutes, and widened when short.
    // Until both dates are picked, there is no error.
    dateRangeError() {
      if (!this.isCustomDateRange || !this.hasCustomDates) return null;

      const [start, end] = [this.dateRange.startDate, this.dateRange.endDate].map(
        (date) => Math.floor(date.getTime() / MINUTE_MS) * MINUTE_MS,
      );

      if (start >= end) {
        // An end picked after the start, but in the same minute, aligns to an empty range.
        return this.dateRange.startDate < this.dateRange.endDate
          ? s__('DatabaseDiagnostics|Choose an end at least one minute after the start.')
          : s__('DatabaseDiagnostics|Choose an end after the start.');
      }
      if (start > this.now) return s__('DatabaseDiagnostics|Choose a start in the past.');
      if (end - start > MAX_RANGE_MS) {
        return s__('DatabaseDiagnostics|Choose a time range of up to 24 hours.');
      }
      if (start < this.minDate) {
        return s__('DatabaseDiagnostics|Choose a start within the last 30 days.');
      }
      if (end - MIN_RANGE_MS < this.minDate) {
        return s__(
          'DatabaseDiagnostics|A time range shorter than 61 minutes is read as the 61 minutes before its end, which would start over 30 days ago. Choose a later end.',
        );
      }

      return null;
    },
    isDateRangeValid() {
      return !this.isCustomDateRange || (this.hasCustomDates && !this.dateRangeError);
    },
    timeRange() {
      // On hourly rollups, pg_ash reads whole hours, so show the period it read.
      const { from, to } = this.summary.coverage ?? this.summary.window;

      return sprintf(s__('DatabaseDiagnostics|Time range: %{timeRange}'), {
        timeRange: localeDateFormat.asDateTimeWithTimezone.formatRange(
          new Date(from),
          new Date(to),
        ),
      });
    },
    isQueryTextMissing() {
      const queries = this.summary.top_queries.filter(({ query_id: queryId }) => queryId !== null);

      return queries.length > 0 && queries.every(({ query_text: queryText }) => !queryText);
    },
  },
  created() {
    this.loadSummary();
  },
  methods: {
    formatActiveSessions,
    formatShareOfLoad,
    onSelectDateRange(value) {
      this.now = new Date();
      this.dateRange = { ...this.dateRange, value };
      if (this.isDateRangeValid) this.loadSummary();
    },
    onCustomDateRange({ startDate, endDate }) {
      this.now = new Date();
      this.dateRange = { value: CUSTOM_DATE_RANGE_OPTION, startDate, endDate };
      if (this.isDateRangeValid) this.loadSummary();
    },
    // Presets count back from now, so they are worked out on every load.
    // The endpoint ends any window at the newest rolled-up minute.
    windowParams() {
      const { value, startDate, endDate } = this.dateRange;
      const { min, max } = this.isCustomDateRange
        ? { min: startDate, max: endDate }
        : periodToDate(value);

      return { from: min.toISOString(), to: max.toISOString() };
    },
    async loadSummary() {
      // Changing the time range while a load runs starts a new one, so only the
      // latest may update the page.
      this.loadId += 1;
      const { loadId } = this;

      this.isLoading = true;
      this.error = null;

      try {
        const { data } = await axios.get(
          activeSessionHistoryAdminDatabaseDiagnosticsPath({ format: 'json' }),
          { params: this.windowParams() },
        );
        if (loadId !== this.loadId) return;

        assertJson(data, 'installed');
        this.summary = data;
      } catch (error) {
        if (loadId !== this.loadId) return;

        this.summary = null;
        this.error = activeSessionHistoryErrorMessage(
          error,
          s__('DatabaseDiagnostics|Failed to load active session history. Try again.'),
        );
      } finally {
        if (loadId === this.loadId) this.isLoading = false;
      }
    },
  },
  helpPath: helpPagePath('administration/monitoring/performance/_index.md', {
    anchor: 'active-session-history',
  }),
  queryTextHelpPath: helpPagePath('administration/monitoring/performance/_index.md', {
    anchor: 'query-ids-and-text',
  }),
  waitEventTypeFields: [
    { key: 'wait_event_type', label: s__('DatabaseDiagnostics|Wait event type') },
    ...activeSessionHistoryNumberFields(),
  ],
  dateRangeItems: [
    ...TIME_RANGE_OPTIONS.filter(({ value }) =>
      [ONE_HOUR, FOUR_HOURS, TWELVE_HOURS, ONE_DAY].includes(value),
    ).map(({ value, title }) => ({ value, text: title })),
    { value: CUSTOM_DATE_RANGE_OPTION, text: s__('DatabaseDiagnostics|Custom') },
  ],
  MAX_RANGE_DAYS,
};
</script>

<template>
  <section>
    <p class="gl-mb-5">
      {{
        s__(
          'DatabaseDiagnostics|See what the main database waited on in a time range, and which queries caused the load.',
        )
      }}
      <gl-experiment-badge class="!gl-ml-2" />
    </p>

    <gl-form-group
      :label="s__('DatabaseDiagnostics|Time range')"
      :description="
        isCustomDateRange
          ? s__(
              'DatabaseDiagnostics|A time range can be up to 24 hours long, and start up to 30 days ago.',
            )
          : ''
      "
      :invalid-feedback="dateRangeError"
      :state="dateRangeError ? false : null"
      class="gl-mb-0"
    >
      <div class="gl-flex gl-flex-wrap gl-items-end gl-gap-5">
        <gl-collapsible-listbox
          :selected="dateRange.value"
          :items="$options.dateRangeItems"
          :header-text="s__('DatabaseDiagnostics|Time range')"
          @select="onSelectDateRange"
        />

        <!-- Without a positioned wrapper, the calendar opens away from its input. -->
        <div v-if="isCustomDateRange" class="gl-relative">
          <datetime-range-picker
            :start-opened="!hasCustomDates"
            :default-start-date="dateRange.startDate"
            :default-end-date="dateRange.endDate"
            :default-min-date="minDate"
            :default-max-date="maxDate"
            :max-date-range="$options.MAX_RANGE_DAYS"
            :state="dateRangeError ? false : null"
            @input="onCustomDateRange"
          />
        </div>
      </div>
    </gl-form-group>

    <div class="gl-mt-6">
      <gl-skeleton-loader v-if="isLoading">
        <rect style="width: 100%" height="20" y="0" />
        <rect style="width: 100%" height="15" y="25" />
        <rect style="width: 100%" height="5" y="50" />
        <rect style="width: 100%" height="5" y="60" />
      </gl-skeleton-loader>

      <gl-alert
        v-else-if="error"
        variant="danger"
        :dismissible="false"
        :primary-button-text="__('Retry')"
        data-testid="error-alert"
        @primary-action="loadSummary"
      >
        {{ error }}
      </gl-alert>

      <p v-else-if="summary && !isInstalled" data-testid="not-installed">
        <gl-sprintf
          :message="
            s__(
              'DatabaseDiagnostics|pg_ash is not installed. %{linkStart}How do I install it?%{linkEnd}',
            )
          "
        >
          <template #link="{ content }">
            <gl-link :href="$options.helpPath">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>

      <p v-else-if="summary && !isSupported" data-testid="unsupported-version">
        <gl-sprintf
          :message="
            s__(
              'DatabaseDiagnostics|pg_ash %{installedVersion} is installed, but this version of GitLab needs %{supportedVersion}. %{linkStart}How do I reinstall it?%{linkEnd}',
            )
          "
        >
          <template #installedVersion>{{ summary.installed_version }}</template>
          <template #supportedVersion>{{ summary.supported_version }}</template>
          <template #link="{ content }">
            <gl-link :href="$options.helpPath">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>

      <div v-else-if="summary" class="gl-flex gl-flex-col gl-gap-7">
        <gl-alert
          v-if="!summary.sampling_enabled"
          variant="warning"
          :dismissible="false"
          data-testid="sampling-off-alert"
        >
          <gl-sprintf
            :message="
              s__(
                'DatabaseDiagnostics|Session sampling is off, so new database activity is not recorded. %{linkStart}Turn on session sampling.%{linkEnd}',
              )
            "
          >
            <template #link="{ content }">
              <gl-link :href="settingsPath">{{ content }}</gl-link>
            </template>
          </gl-sprintf>
        </gl-alert>

        <div>
          <p class="gl-mb-3 gl-text-sm gl-text-subtle" data-testid="time-range">
            {{ timeRange }}
          </p>

          <p v-if="!hasSamples" class="gl-mb-0 gl-text-subtle" data-testid="no-samples">
            {{ s__('DatabaseDiagnostics|No samples in this time range.') }}
          </p>

          <gl-tabs v-else v-model="resultsTabIndex">
            <gl-tab :title="s__('DatabaseDiagnostics|Wait event types')">
              <gl-table-lite
                :items="summary.wait_event_types"
                :fields="$options.waitEventTypeFields"
                :aria-label="s__('DatabaseDiagnostics|Wait event types')"
                fixed
                stacked="md"
                data-testid="wait-event-types-table"
              >
                <template #table-colgroup="{ fields }">
                  <col v-for="field in fields" :key="field.key" :class="field.columnClass" />
                </template>

                <template #cell(pct)="{ item }">{{ formatShareOfLoad(item.pct) }}</template>
                <template #cell(avg_aas)="{ item }">{{
                  formatActiveSessions(item.avg_aas)
                }}</template>
                <template #cell(peak_aas)="{ item }">{{
                  formatActiveSessions(item.peak_aas)
                }}</template>
              </gl-table-lite>
            </gl-tab>

            <gl-tab :title="s__('DatabaseDiagnostics|Top queries')">
              <p
                v-if="isQueryTextMissing"
                class="gl-my-4 gl-text-sm gl-text-subtle"
                data-testid="query-text-help"
              >
                <gl-sprintf
                  :message="
                    s__(
                      'DatabaseDiagnostics|Query text comes from pg_stat_statements, and none was found for these queries. %{linkStart}How do I get query text?%{linkEnd}',
                    )
                  "
                >
                  <template #link="{ content }">
                    <gl-link :href="$options.queryTextHelpPath">{{ content }}</gl-link>
                  </template>
                </gl-sprintf>
              </p>
              <active-session-history-queries
                :queries="summary.top_queries"
                :aria-label="s__('DatabaseDiagnostics|Top queries')"
                data-testid="top-queries"
              />
            </gl-tab>
          </gl-tabs>
        </div>
      </div>
    </div>
  </section>
</template>
