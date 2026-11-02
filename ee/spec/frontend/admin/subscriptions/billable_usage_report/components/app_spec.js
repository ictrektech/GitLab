import { nextTick } from 'vue';
import MockAdapter from 'axios-mock-adapter';
import { GlAlert, GlCollapsibleListbox, GlFormGroup, GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import download from '~/lib/utils/downloader';
import { visitUrlWithAlerts } from '~/lib/utils/url_utility';
import {
  HTTP_STATUS_OK,
  HTTP_STATUS_NOT_FOUND,
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
} from '~/lib/utils/http_status';
import BillableUsageReportApp from 'ee/admin/subscriptions/billable_usage_report/components/app.vue';
import CapabilityPanel from 'ee/admin/subscriptions/billable_usage_report/components/capability_panel.vue';
import SeatLinkPanel from 'ee/admin/subscriptions/billable_usage_report/components/seat_link_panel.vue';

jest.mock('~/lib/utils/downloader');
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrlWithAlerts: jest.fn(),
}));

const TERMS_PATH = '/admin/license/billable_usage_export/terms.json';
const REPORT_PATH = '/admin/license/billable_usage_export.json';
const DOWNLOAD_PATH = '/admin/license/billable_usage_export/download';
const SUBSCRIPTION_PATH = '/admin/subscription';

const report = {
  period_start: '2026-02-01',
  period_end: '2026-08-31',
  seat_link: {
    records: [
      { date: '2026-08-30', billable_user_count: 438 },
      { date: '2026-08-31', billable_user_count: 412 },
    ],
  },
  records: [
    {
      event_type: 'secrets_read',
      unit_of_measure: 'request',
      quantity: 1023694,
      metadata: { feature_qualified_name: 'secrets_read', quantity_kind: 'counter' },
    },
    {
      event_type: 'code_suggestions',
      unit_of_measure: 'request',
      quantity: 226621,
      metadata: { feature_qualified_name: 'code_suggestions', quantity_kind: 'counter' },
    },
  ],
};

const currentTerm = {
  license_id: 2,
  start_date: '2026-02-01',
  end_date: '2027-01-31',
  current: true,
};
const previousTerm = {
  license_id: 1,
  start_date: '2025-02-01',
  end_date: '2026-01-31',
  current: false,
};

const reportResponse = (document = report, extra = {}) => ({
  document,
  licensed_seats: 450,
  last_exported_at: null,
  ...extra,
});

describe('BillableUsageReportApp', () => {
  let wrapper;
  let mockAxios;

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findErrorAlert = () => wrapper.findByTestId('report-error');
  const findReportContents = () => wrapper.findByTestId('report-contents');
  const findCapabilityPanels = () => wrapper.findAllComponents(CapabilityPanel);
  const findSeatLinkPanel = () => wrapper.findComponent(SeatLinkPanel);
  const findNoPerUserDataAlert = () => wrapper.findByTestId('no-per-user-data-alert');
  const findNoDataAlert = () => wrapper.findComponentByTestId('no-data-alert');
  // Intl.formatRange separates a range with thin spaces around an en dash, so the text
  // is normalised rather than asserted against hand-typed whitespace.
  const noDataAlertText = () => findNoDataAlert().text().replace(/\s+/g, ' ');
  const findExportJsonButton = () => wrapper.findComponentByTestId('export-json-btn');
  const findCancelButton = () => wrapper.findByTestId('cancel-btn');
  const findTermGroup = () => wrapper.findComponent(GlFormGroup);
  const findTermSelect = () => wrapper.findComponent(GlCollapsibleListbox);
  const findLastExported = () => wrapper.findByTestId('last-exported');
  const reportRequests = () => mockAxios.history.get.filter(({ url }) => url === REPORT_PATH);
  const findDownloadError = () => wrapper.findByTestId('download-error');
  const clickExport = async () => {
    findExportJsonButton().vm.$emit('click');
    await waitForPromises();
  };

  const createComponent = () => {
    wrapper = shallowMountExtended(BillableUsageReportApp, {
      propsData: {
        termsPath: TERMS_PATH,
        reportPath: REPORT_PATH,
        downloadPath: DOWNLOAD_PATH,
        subscriptionPath: SUBSCRIPTION_PATH,
      },
      stubs: { GlAlert },
    });
  };

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
    mockAxios.onGet(TERMS_PATH).reply(HTTP_STATUS_OK, [currentTerm]);
    mockAxios.onGet(new RegExp(`^${DOWNLOAD_PATH}`)).reply(HTTP_STATUS_OK, '{}');
    jest.spyOn(URL, 'createObjectURL').mockReturnValue('blob:report');
    URL.revokeObjectURL = jest.fn();
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('while the report is loading', () => {
    beforeEach(() => {
      mockAxios.onGet(TERMS_PATH).reply(() => new Promise(() => {}));
      createComponent();
    });

    it('shows a loading icon and no report', () => {
      expect(findLoadingIcon().exists()).toBe(true);
      expect(findReportContents().exists()).toBe(false);
      expect(findExportJsonButton().exists()).toBe(false);
    });
  });

  describe('when the report loads', () => {
    beforeEach(async () => {
      mockAxios.onGet(REPORT_PATH).reply(HTTP_STATUS_OK, reportResponse());
      createComponent();
      await waitForPromises();
    });

    it('requests the report once, for the current term', () => {
      expect(reportRequests()).toHaveLength(1);
      expect(reportRequests()[0].params).toEqual({ license_id: 2 });
    });

    it('does not offer a term choice when there is only the current term', () => {
      expect(findTermGroup().exists()).toBe(false);
    });

    it('says when there has been no export of this term yet', () => {
      expect(findLastExported().text()).toBe('No report has been exported for this term yet.');
    });

    it('states the period the report covers', () => {
      expect(findReportContents().text()).toContain('Feb 1, 2026');
      expect(findReportContents().text()).toContain('Aug 31, 2026');
    });

    it('explains that a resent day is not double counted', () => {
      expect(findReportContents().text()).toContain(
        'GitLab records each day once, so a day you have already sent is ignored rather than counted twice.',
      );
    });

    it('renders one capability panel per product', () => {
      expect(findCapabilityPanels()).toHaveLength(2);
      expect(findCapabilityPanels().at(0).props('panel')).toMatchObject({
        product: 'Secrets Manager',
        totalBillableEvents: 1023694,
      });
    });

    it('passes the seat link summary and the licensed seat count to the seats panel', () => {
      expect(findSeatLinkPanel().props()).toEqual({
        summary: { recordCount: 2, highestBillableUsers: 438, billableUsersOnLastDay: 412 },
        licensedSeats: 450,
      });
    });

    it('says the report holds no per user data', () => {
      expect(findNoPerUserDataAlert().text()).toContain('No per user data');
      expect(findNoPerUserDataAlert().text()).toContain(
        'The report contains daily totals only. It does not attribute usage to any user and contains no usernames, email addresses or user IDs.',
      );
    });

    it('links cancel back to the subscription page', () => {
      expect(findCancelButton().attributes('href')).toBe(SUBSCRIPTION_PATH);
    });

    it('fetches the file from the download route, not the one it read from', async () => {
      await clickExport();

      const downloads = mockAxios.history.get.filter(({ url }) => url.startsWith(DOWNLOAD_PATH));
      expect(downloads).toHaveLength(1);
      expect(downloads[0].url).toBe(`${DOWNLOAD_PATH}?license_id=2`);
      expect(downloads[0].responseType).toBe('blob');
    });

    it('saves the fetched file under the export filename', async () => {
      await clickExport();

      expect(download).toHaveBeenCalledWith({
        fileName: 'billable_usage_export_2026-02-01_2026-08-31.json',
        url: 'blob:report',
      });
    });

    it('revokes the object URL only after the download has started', async () => {
      await clickExport();

      expect(download).toHaveBeenCalled();
      expect(URL.revokeObjectURL).not.toHaveBeenCalled();

      jest.runOnlyPendingTimers();

      expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:report');
    });

    it('shows the export button as loading while the file is fetched', async () => {
      findExportJsonButton().vm.$emit('click');
      await nextTick();

      expect(findExportJsonButton().props('loading')).toBe(true);
    });

    it('hands back to the subscription page naming the file', async () => {
      await clickExport();

      expect(visitUrlWithAlerts).toHaveBeenCalledWith(SUBSCRIPTION_PATH, [
        {
          id: 'billable-usage-report-exported',
          variant: 'success',
          title: 'Report downloaded',
          message:
            'Upload billable_usage_export_2026-02-01_2026-08-31.json to the Customers Portal so this usage is billed. Every report carries your whole license term, so if this one does not arrive, the next one reports the same usage again.',
        },
      ]);
    });

    it('shows no missing-days warning when every day was recorded', () => {
      expect(findNoDataAlert().exists()).toBe(false);
    });

    it('does not show an error', () => {
      expect(findErrorAlert().exists()).toBe(false);
    });
  });

  describe('when the term was exported before', () => {
    beforeEach(async () => {
      mockAxios
        .onGet(REPORT_PATH)
        .reply(
          HTTP_STATUS_OK,
          reportResponse(report, { last_exported_at: '2026-08-01T09:12:00Z' }),
        );
      createComponent();
      await waitForPromises();
    });

    it('says when it was last exported', () => {
      expect(findLastExported().text()).toBe('You last exported on Aug 1, 2026, 9:12 AM GMT.');
    });
  });

  describe('when the subscription has a previous term', () => {
    const previousReport = { ...report, period_start: '2025-02-01', period_end: '2026-01-31' };

    beforeEach(async () => {
      mockAxios.onGet(TERMS_PATH).reply(HTTP_STATUS_OK, [currentTerm, previousTerm]);
      mockAxios
        .onGet(REPORT_PATH)
        .reply(({ params }) =>
          params.license_id === previousTerm.license_id
            ? [HTTP_STATUS_OK, reportResponse(previousReport, { licensed_seats: 400 })]
            : [HTTP_STATUS_OK, reportResponse()],
        );
      createComponent();
      await waitForPromises();
    });

    it('offers both terms, with the current one selected', () => {
      expect(findTermGroup().attributes('label')).toBe('Subscription term');
      expect(findTermSelect().props('items')).toEqual([
        { value: 2, text: 'Feb 1, 2026 to Jan 31, 2027 (current)' },
        { value: 1, text: 'Feb 1, 2025 to Jan 31, 2026' },
      ]);
      expect(findTermSelect().props('selected')).toBe(2);
      expect(findTermSelect().props('toggleText')).toBe('Feb 1, 2026 to Jan 31, 2027 (current)');
    });

    it('says when the subscription renewed', () => {
      expect(findTermGroup().attributes('description')).toBe(
        'Your subscription renewed on Feb 1, 2026. If the last month of your previous term was never uploaded, export that term too.',
      );
    });

    describe('when the previous term is selected', () => {
      beforeEach(async () => {
        findTermSelect().vm.$emit('select', previousTerm.license_id);
        await waitForPromises();
      });

      it('loads the report for that term', () => {
        expect(reportRequests()).toHaveLength(2);
        expect(reportRequests()[1].params).toEqual({ license_id: 1 });
        expect(findReportContents().text()).toContain('Feb 1, 2025');
        expect(findReportContents().text()).toContain('Jan 31, 2026');
      });

      it('shows that term licensed seats', () => {
        expect(findSeatLinkPanel().props('licensedSeats')).toBe(400);
      });

      it('downloads that term', async () => {
        await clickExport();

        expect(mockAxios.history.get.at(-1).url).toBe(`${DOWNLOAD_PATH}?license_id=1`);
        expect(download).toHaveBeenCalledWith({
          fileName: 'billable_usage_export_2025-02-01_2026-01-31.json',
          url: 'blob:report',
        });
      });
    });
  });

  describe('when the terms cannot be loaded', () => {
    beforeEach(async () => {
      mockAxios.onGet(TERMS_PATH).reply(HTTP_STATUS_NOT_FOUND);
      createComponent();
      await waitForPromises();
    });

    it('shows an error without requesting the report', () => {
      expect(findErrorAlert().exists()).toBe(true);
      expect(reportRequests()).toHaveLength(0);
    });
  });

  describe('when the download fails', () => {
    beforeEach(async () => {
      mockAxios.onGet(REPORT_PATH).reply(HTTP_STATUS_OK, reportResponse());
      mockAxios.onGet(new RegExp(`^${DOWNLOAD_PATH}`)).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      createComponent();
      await waitForPromises();
      await clickExport();
    });

    it('stays on the page and says the download failed', () => {
      expect(visitUrlWithAlerts).not.toHaveBeenCalled();
      expect(download).not.toHaveBeenCalled();
      expect(findDownloadError().text()).toBe('Could not download the usage report. Try again.');
    });

    it('lets the admin try again', () => {
      expect(findExportJsonButton().props('loading')).toBe(false);
    });

    it('clears the error on the next attempt', async () => {
      mockAxios.onGet(new RegExp(`^${DOWNLOAD_PATH}`)).reply(HTTP_STATUS_OK, '{}');
      await clickExport();

      expect(findDownloadError().exists()).toBe(false);
      expect(visitUrlWithAlerts).toHaveBeenCalled();
    });
  });

  describe('when some days have no recorded data', () => {
    const withNoDataDates = async (noDataDates, expectedDays = 212) => {
      mockAxios.onGet(REPORT_PATH).reply(
        HTTP_STATUS_OK,
        reportResponse({
          ...report,
          coverage: {
            seat_link: {
              expected_days: expectedDays,
              days_with_data: expectedDays - noDataDates.length,
              no_data_dates: noDataDates,
            },
            billable_events: { included: true, days_with_data: 20 },
          },
        }),
      );
      createComponent();
      await waitForPromises();
    };

    it('collapses consecutive days into one range and counts the days', async () => {
      await withNoDataDates(['2026-08-02', '2026-08-01', '2026-08-03']);

      expect(findNoDataAlert().props('title')).toBe('3 days have no recorded data');
      expect(noDataAlertText()).toContain('recorded no data on Aug 1 – 3, 2026.');
      expect(findExportJsonButton().exists()).toBe(true);
    });

    it('uses the singular title for a single missing day', async () => {
      await withNoDataDates(['2026-08-01']);

      expect(findNoDataAlert().props('title')).toBe('1 day has no recorded data');
      expect(noDataAlertText()).toContain('recorded no data on Aug 1, 2026.');
    });

    it('names each run when the gaps are not consecutive', async () => {
      await withNoDataDates(['2026-08-01', '2026-08-02', '2026-08-20']);

      expect(noDataAlertText()).toContain('Aug 1 – 2, 2026 and Aug 20, 2026');
    });

    // The period is a whole licence term, so an instance provisioned partway into a
    // backdated term can be missing hundreds of scattered days. Listing them all would
    // bury the alert.
    it('summarises instead of listing once there are too many runs', async () => {
      const everyOtherDay = Array.from({ length: 40 }, (_, index) =>
        new Date(Date.UTC(2026, 2, 1 + index * 2)).toISOString().slice(0, 10),
      );

      await withNoDataDates(everyOtherDay);

      expect(findNoDataAlert().props('title')).toBe('40 days have no recorded data');
      expect(noDataAlertText()).toContain('recorded no data on 40 of the 212 days');
      expect(noDataAlertText()).not.toContain('Mar 1, 2026');
      expect(findExportJsonButton().exists()).toBe(true);
    });
  });

  describe('when the report has no usage yet', () => {
    beforeEach(async () => {
      mockAxios
        .onGet(REPORT_PATH)
        .reply(
          HTTP_STATUS_OK,
          reportResponse({ ...report, records: [], seat_link: { records: [] } }),
        );
      createComponent();
      await waitForPromises();
    });

    it('renders the seats panel with zeroed figures and no capability panels', () => {
      expect(findCapabilityPanels()).toHaveLength(0);
      expect(findSeatLinkPanel().props('summary')).toEqual({
        recordCount: 0,
        highestBillableUsers: 0,
        billableUsersOnLastDay: 0,
      });
    });

    it('still offers the export', () => {
      expect(findExportJsonButton().exists()).toBe(true);
    });
  });

  describe('when the report cannot be loaded', () => {
    beforeEach(async () => {
      mockAxios.onGet(REPORT_PATH).reply(HTTP_STATUS_NOT_FOUND);
      createComponent();
      await waitForPromises();
    });

    it('shows an error instead of the report', () => {
      expect(findErrorAlert().text()).toBe(
        'Could not load the usage report. Refresh the page to try again.',
      );
      expect(findReportContents().exists()).toBe(false);
      expect(findExportJsonButton().exists()).toBe(false);
    });
  });
});
