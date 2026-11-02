<script>
import { GlAlert, GlButton, GlCollapsibleListbox, GlFormGroup, GlLoadingIcon } from '@gitlab/ui';
import axios from '~/lib/utils/axios_utils';
import download from '~/lib/utils/downloader';
import { mergeUrlParams, visitUrlWithAlerts } from '~/lib/utils/url_utility';
import { createListFormat, formatNumber, n__, s__, sprintf } from '~/locale';
import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import { NO_DATA_RANGE_LIMIT, EXPORTED_ALERT_ID } from '../constants';
import { buildCapabilityPanels, summariseSeatLink, noDataDates, noDataRanges } from '../utils';
import CapabilityPanel from './capability_panel.vue';
import SeatLinkPanel from './seat_link_panel.vue';

export default {
  name: 'BillableUsageReportApp',
  components: {
    GlAlert,
    GlButton,
    GlCollapsibleListbox,
    GlFormGroup,
    GlLoadingIcon,
    CapabilityPanel,
    SeatLinkPanel,
  },
  props: {
    termsPath: {
      type: String,
      required: true,
    },
    reportPath: {
      type: String,
      required: true,
    },
    downloadPath: {
      type: String,
      required: true,
    },
    subscriptionPath: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      terms: [],
      selectedLicenseId: null,
      report: null,
      licensedSeats: null,
      lastExportedAt: null,
      isLoading: true,
      hasError: false,
      isExporting: false,
      hasExportError: false,
    };
  },
  listFormatter: createListFormat({ style: 'long', type: 'conjunction' }),
  computed: {
    termItems() {
      return this.terms.map((term) => ({ value: term.license_id, text: this.termLabel(term) }));
    },
    selectedTermText() {
      return this.termItems.find(({ value }) => value === this.selectedLicenseId)?.text ?? '';
    },
    currentTerm() {
      return this.terms.find((term) => term.current);
    },
    // Only after a renewal is there a previous term worth offering.
    hasPreviousTerm() {
      return this.terms.length > 1;
    },
    termRenewedMessage() {
      return sprintf(
        s__(
          'SuperSonics|Your subscription renewed on %{date}. If the last month of your previous term was never uploaded, export that term too.',
        ),
        { date: this.formatReportDate(this.currentTerm?.start_date) },
      );
    },
    lastExportedMessage() {
      if (!this.lastExportedAt) {
        return s__('SuperSonics|No report has been exported for this term yet.');
      }

      return sprintf(s__('SuperSonics|You last exported on %{date}.'), {
        date: localeDateFormat.asDateTimeWithTimezone.format(newDate(this.lastExportedAt)),
      });
    },
    termParams() {
      return this.selectedLicenseId === null ? {} : { license_id: this.selectedLicenseId };
    },
    downloadUrl() {
      return mergeUrlParams(this.termParams, this.downloadPath);
    },
    reportStart() {
      return this.formatReportDate(this.report?.period_start);
    },
    reportEnd() {
      return this.formatReportDate(this.report?.period_end);
    },
    capabilityPanels() {
      return buildCapabilityPanels(this.report?.records);
    },
    seatLinkSummary() {
      return summariseSeatLink(this.report?.seat_link?.records);
    },
    missingDates() {
      return noDataDates(this.report?.coverage);
    },
    missingRanges() {
      return noDataRanges(this.missingDates).map(({ start, end }) =>
        start === end
          ? this.formatReportDate(start)
          : localeDateFormat.asDate.formatRange(newDate(start), newDate(end)),
      );
    },
    noDataTitleText() {
      const count = this.missingDates.length;

      return sprintf(
        n__(
          'SuperSonics|%{count} day has no recorded data',
          'SuperSonics|%{count} days have no recorded data',
          count,
        ),
        { count: formatNumber(count) },
      );
    },
    // Enumerated while the runs stay readable, summarised once they do not. The summary
    // reads off the coverage block, which already counts the days it expected.
    noDataMessage() {
      if (this.missingRanges.length <= NO_DATA_RANGE_LIMIT) {
        return sprintf(
          s__(
            'SuperSonics|This instance recorded no data on %{dates}. The report marks these days as unknown rather than as zero usage. You can still export it.',
          ),
          { dates: this.$options.listFormatter.format(this.missingRanges) },
        );
      }

      return sprintf(
        s__(
          'SuperSonics|This instance recorded no data on %{missing} of the %{total} days in this period. The report marks these days as unknown rather than as zero usage. You can still export it.',
        ),
        {
          missing: formatNumber(this.missingDates.length),
          total: formatNumber(this.report?.coverage?.seat_link?.expected_days ?? 0),
        },
      );
    },
    // Mirrors the filename Admin::Licenses::BillableUsageExportsController#download sends.
    fileName() {
      return `billable_usage_export_${this.report.period_start}_${this.report.period_end}.json`;
    },
  },
  async mounted() {
    try {
      const { data } = await axios.get(this.termsPath);
      this.terms = data;
      this.selectedLicenseId = this.currentTerm?.license_id ?? null;
    } catch {
      this.hasError = true;
      this.isLoading = false;
      return;
    }

    await this.fetchReport();
  },
  methods: {
    async fetchReport() {
      this.isLoading = true;
      this.hasError = false;

      try {
        const { data } = await axios.get(this.reportPath, { params: this.termParams });
        this.report = data.document;
        this.licensedSeats = data.licensed_seats;
        this.lastExportedAt = data.last_exported_at;
      } catch {
        this.hasError = true;
      } finally {
        this.isLoading = false;
      }
    },
    selectTerm(licenseId) {
      this.selectedLicenseId = licenseId;
      this.fetchReport();
    },
    termLabel(term) {
      const label = term.current
        ? s__('SuperSonics|%{start} to %{end} (current)')
        : s__('SuperSonics|%{start} to %{end}');

      return sprintf(label, {
        start: this.formatReportDate(term.start_date),
        end: this.formatReportDate(term.end_date),
      });
    },
    async exportReport() {
      this.isExporting = true;
      this.hasExportError = false;

      let file;
      try {
        ({ data: file } = await axios.get(this.downloadUrl, { responseType: 'blob' }));
      } catch {
        this.hasExportError = true;
        this.isExporting = false;
        return;
      }

      const url = URL.createObjectURL(file);
      download({ fileName: this.fileName, url });
      setTimeout(() => URL.revokeObjectURL(url));

      visitUrlWithAlerts(this.subscriptionPath, [
        {
          id: EXPORTED_ALERT_ID,
          variant: 'success',
          title: s__('SuperSonics|Report downloaded'),
          message: sprintf(
            s__(
              'SuperSonics|Upload %{fileName} to the Customers Portal so this usage is billed. Every report carries your whole license term, so if this one does not arrive, the next one reports the same usage again.',
            ),
            { fileName: this.fileName },
          ),
        },
      ]);
    },
    formatReportDate(value) {
      // Guarded here rather than relying on newDate: it passes a missing value through,
      // and Intl would then format it as today.
      return value ? localeDateFormat.asDate.format(newDate(value)) : '';
    },
  },
};
</script>

<template>
  <div class="gl-mx-auto gl-flex gl-max-w-3xl gl-flex-col gl-gap-6">
    <div>
      <h1 class="gl-heading-1 !gl-m-0">{{ s__('SuperSonics|Export usage report') }}</h1>
      <p class="gl-mb-0 gl-mt-2 gl-text-subtle">
        {{
          s__(
            'SuperSonics|Each report covers one subscription term, from its start up to the last completed day. Upload it to the Customers Portal within three days of month end.',
          )
        }}
      </p>
    </div>

    <gl-form-group
      v-if="hasPreviousTerm"
      :label="s__('SuperSonics|Subscription term')"
      label-for="billable-usage-report-term"
      :description="termRenewedMessage"
      class="gl-mb-0"
      data-testid="term-select-group"
    >
      <gl-collapsible-listbox
        toggle-id="billable-usage-report-term"
        :items="termItems"
        :selected="selectedLicenseId"
        :toggle-text="selectedTermText"
        :disabled="isLoading"
        data-testid="term-select"
        @select="selectTerm"
      />
    </gl-form-group>

    <gl-loading-icon v-if="isLoading" size="lg" class="gl-my-6" />

    <gl-alert v-else-if="hasError" variant="danger" :dismissible="false" data-testid="report-error">
      {{ s__('SuperSonics|Could not load the usage report. Refresh the page to try again.') }}
    </gl-alert>

    <template v-else>
      <section data-testid="report-contents">
        <h2 class="gl-heading-scale-500 gl-mb-2 gl-mt-0">
          {{ s__('SuperSonics|Report contents') }}
        </h2>
        <dl class="gl-mb-4 gl-mt-0 gl-flex gl-flex-col gl-gap-2" data-testid="report-period">
          <div class="gl-flex gl-gap-3">
            <dt class="gl-font-bold gl-text-default">{{ s__('SuperSonics|Report start') }}</dt>
            <dd class="gl-m-0 gl-min-w-0">{{ reportStart }}</dd>
          </div>
          <div class="gl-flex gl-gap-3">
            <dt class="gl-font-bold gl-text-default">{{ s__('SuperSonics|Report end') }}</dt>
            <dd class="gl-m-0 gl-min-w-0">{{ reportEnd }}</dd>
          </div>
        </dl>
        <p class="gl-mb-0 gl-mt-0 gl-text-sm gl-text-subtle">
          {{
            s__(
              'SuperSonics|GitLab records each day once, so a day you have already sent is ignored rather than counted twice.',
            )
          }}
        </p>
        <p class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-subtle" data-testid="last-exported">
          {{ lastExportedMessage }}
        </p>
      </section>

      <gl-alert
        v-if="missingDates.length"
        variant="warning"
        :dismissible="false"
        :title="noDataTitleText"
        data-testid="no-data-alert"
      >
        {{ noDataMessage }}
      </gl-alert>

      <section>
        <h3 class="gl-heading-scale-400 gl-mb-1 gl-mt-0">
          {{ s__('SuperSonics|Capability consumption') }}
        </h3>
        <p class="gl-mb-4 gl-mt-0 gl-text-subtle">
          {{
            s__(
              'SuperSonics|Usage totals for each meter this instance records. GitLab converts them to credits after upload.',
            )
          }}
        </p>
        <div class="gl-flex gl-flex-col gl-gap-4">
          <capability-panel v-for="panel in capabilityPanels" :key="panel.product" :panel="panel" />
        </div>
      </section>

      <section>
        <h3 class="gl-heading-scale-400 gl-mb-1 gl-mt-0">{{ s__('SuperSonics|Seats') }}</h3>
        <p class="gl-mb-4 gl-mt-0 gl-text-subtle">
          {{
            s__(
              'SuperSonics|One record per day, the same series the license usage CSV has always carried.',
            )
          }}
        </p>
        <seat-link-panel :summary="seatLinkSummary" :licensed-seats="licensedSeats" />
      </section>

      <gl-alert
        variant="info"
        :dismissible="false"
        :title="s__('SuperSonics|No per user data')"
        data-testid="no-per-user-data-alert"
      >
        {{
          s__(
            'SuperSonics|The report contains daily totals only. It does not attribute usage to any user and contains no usernames, email addresses or user IDs.',
          )
        }}
      </gl-alert>

      <gl-alert
        v-if="hasExportError"
        variant="danger"
        data-testid="download-error"
        @dismiss="hasExportError = false"
      >
        {{ s__('SuperSonics|Could not download the usage report. Try again.') }}
      </gl-alert>

      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <gl-button
          variant="confirm"
          :loading="isExporting"
          data-testid="export-json-btn"
          @click="exportReport"
        >
          {{ s__('SuperSonics|Export JSON') }}
        </gl-button>
        <gl-button category="tertiary" :href="subscriptionPath" data-testid="cancel-btn">
          {{ __('Cancel') }}
        </gl-button>
      </div>
    </template>
  </div>
</template>
