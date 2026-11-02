import { nextTick } from 'vue';
import { GlCollapsibleListbox, GlDatepicker, GlFormGroup, GlSkeletonLoader } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import timezoneMock from 'timezone-mock';
import { useFakeDate } from 'helpers/fake_date';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import {
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_OK,
  HTTP_STATUS_UNAUTHORIZED,
} from '~/lib/utils/http_status';
import ActiveSessionHistoryApp from '~/admin/database_diagnostics/components/active_session_history_app.vue';
import DatetimeRangePicker from '~/observability/components/datetime_range_picker.vue';
import { activeSessionHistoryQueries, activeSessionHistorySummary } from '../mock_data';
// Intl puts thin spaces around the dash of a range.
const normalized = (text) => text.replace(/\s+/g, ' ');

describe('ActiveSessionHistoryApp component', () => {
  let wrapper;
  let mockAxios;

  useFakeDate(2026, 9, 15, 10, 0);

  const summaryUrl = '/admin/database_diagnostics/active_session_history.json';

  const summaryRequests = () => mockAxios.history.get.filter(({ url }) => url === summaryUrl);
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findErrorAlert = () => wrapper.findByTestId('error-alert');
  const findWaitEventTypeRows = () =>
    wrapper.findAll('[data-testid="wait-event-types-table"] tbody tr');
  const findTimeRange = () => normalized(wrapper.findByTestId('time-range').text());
  const findTopQueries = () => wrapper.findComponentByTestId('top-queries');
  const findDateRangeListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findDatetimeRangePicker = () => wrapper.findComponent(DatetimeRangePicker);
  const findTimeRangeGroup = () => wrapper.findComponent(GlFormGroup);
  const dateRangeLimits = 'A time range can be up to 24 hours long, and start up to 30 days ago.';

  const selectDateRange = async (value) => {
    findDateRangeListbox().vm.$emit('select', value);
    await waitForPromises();
  };
  const pickCustomDateRange = async (startDate, endDate) => {
    await selectDateRange('custom');
    findDatetimeRangePicker().vm.$emit('input', {
      startDate: new Date(startDate),
      endDate: new Date(endDate),
    });
    await waitForPromises();
  };

  const createComponent = async ({ summary = activeSessionHistorySummary } = {}) => {
    mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, summary);
    wrapper = mountExtended(ActiveSessionHistoryApp);
    await waitForPromises();
  };

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('when opened', () => {
    it('shows a skeleton loader until the summary loads', async () => {
      mockAxios.onGet(summaryUrl).reply(() => new Promise(() => {}));
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await nextTick();

      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('reads the last hour', async () => {
      await createComponent();

      expect(summaryRequests().map(({ params }) => params)).toEqual([
        { from: '2026-10-15T09:00:00.000Z', to: '2026-10-15T10:00:00.000Z' },
      ]);
    });
  });

  describe('when pg_ash is not installed', () => {
    beforeEach(async () => {
      await createComponent({ summary: { installed: false } });
    });

    it('links to the install instructions', () => {
      const message = wrapper.findByTestId('not-installed');

      expect(message.text()).toBe('pg_ash is not installed. How do I install it?');
      expect(message.find('a').attributes('href')).toBe(
        '/help/administration/monitoring/performance/_index.md#active-session-history',
      );
    });
  });

  describe('when another pg_ash version is installed', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          installed: true,
          supported: false,
          installed_version: '1.5',
          supported_version: '2.0-beta1',
        },
      });
    });

    it('names both versions and links to the install instructions instead of reading', () => {
      const message = wrapper.findByTestId('unsupported-version');

      expect(message.text()).toBe(
        'pg_ash 1.5 is installed, but this version of GitLab needs 2.0-beta1. How do I reinstall it?',
      );
      expect(message.find('a').attributes('href')).toBe(
        '/help/administration/monitoring/performance/_index.md#active-session-history',
      );
      expect(wrapper.findByTestId('time-range').exists()).toBe(false);
    });
  });

  describe.each`
    description                              | reply
    ${'fails to load'}                       | ${[HTTP_STATUS_INTERNAL_SERVER_ERROR]}
    ${'is not JSON, such as a sign-in page'} | ${[HTTP_STATUS_OK, '<!DOCTYPE html><html></html>']}
  `('when the summary $description', ({ reply }) => {
    beforeEach(async () => {
      mockAxios.onGet(summaryUrl).replyOnce(...reply);
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await waitForPromises();
    });

    it('shows an error alert instead of a pg_ash state', () => {
      expect(findErrorAlert().text()).toContain(
        'Failed to load active session history. Try again.',
      );
      expect(wrapper.findByTestId('not-installed').exists()).toBe(false);
    });

    it('reads again from the alert', async () => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, activeSessionHistorySummary);
      findErrorAlert().find('button').trigger('click');
      await waitForPromises();

      expect(findErrorAlert().exists()).toBe(false);
      expect(findWaitEventTypeRows()).toHaveLength(2);
    });
  });

  describe('when admin mode is inactive', () => {
    beforeEach(async () => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_UNAUTHORIZED, {
        message: 'Admin mode is inactive. Please re-authenticate.',
      });
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await waitForPromises();
    });

    it('says so, instead of suggesting that trying again helps', () => {
      expect(findErrorAlert().text()).toContain('Admin mode is inactive. Please re-authenticate.');
      expect(findErrorAlert().text()).not.toContain('Failed to load');
    });
  });

  describe('when the summary loads', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('shows the time range', () => {
      expect(findTimeRange()).toBe('Time range: Oct 15, 2026, 8:58 – 9:59 AM GMT');
    });

    it('shows the wait event types and the top queries in tabs', () => {
      expect(wrapper.findAll('[role="tab"]').wrappers.map((tab) => tab.text())).toEqual([
        'Wait event types',
        'Top queries',
      ]);
      expect(
        findWaitEventTypeRows().wrappers.map((row) =>
          row.findAll('td').wrappers.map((cell) => cell.text()),
        ),
      ).toEqual([
        ['Lock', '62.5%', '3.95', '4.00'],
        ['CPU*', '37.5%', '0.00', 'Not available'],
      ]);
      expect(findTopQueries().props('queries')).toEqual(activeSessionHistoryQueries);
    });

    it('names both tables', async () => {
      expect(wrapper.findByRole('table', { name: 'Wait event types' }).exists()).toBe(true);

      await wrapper.findByRole('tab', { name: 'Top queries' }).trigger('click');

      expect(wrapper.findByRole('table', { name: 'Top queries' }).exists()).toBe(true);
    });

    it('does not warn about sampling or missing query text', () => {
      expect(wrapper.findByTestId('sampling-off-alert').exists()).toBe(false);
      expect(wrapper.findByTestId('query-text-help').exists()).toBe(false);
    });
  });

  describe('when sampling is off', () => {
    beforeEach(async () => {
      await createComponent({
        summary: { ...activeSessionHistorySummary, sampling_enabled: false },
      });
    });

    it('links to the sampling setting', () => {
      const alert = wrapper.findByTestId('sampling-off-alert');

      expect(alert.text()).toBe(
        'Session sampling is off, so new database activity is not recorded. Turn on session sampling.',
      );
      expect(alert.find('a').attributes('href')).toBe(
        '/admin/application_settings/metrics_and_profiling#js-pg-ash-settings',
      );
    });
  });

  describe('when there are no samples in the time range', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          ...activeSessionHistorySummary,
          coverage: null,
          wait_event_types: [],
          top_queries: [],
        },
      });
    });

    it('says so for the time range it read, instead of showing the tables', () => {
      expect(findTimeRange()).toBe('Time range: Oct 15, 2026, 8:58 – 9:59 AM GMT');
      expect(wrapper.findByTestId('no-samples').text()).toBe('No samples in this time range.');
      expect(findWaitEventTypeRows()).toHaveLength(0);
      expect(findTopQueries().exists()).toBe(false);
    });
  });

  describe('when only the unattributed load is in the top queries', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          ...activeSessionHistorySummary,
          top_queries: activeSessionHistoryQueries.filter(
            ({ query_id: queryId }) => queryId === null,
          ),
        },
      });
    });

    it('does not mention query text', () => {
      expect(wrapper.findByTestId('query-text-help').exists()).toBe(false);
    });
  });

  describe('when no top query has text', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          ...activeSessionHistorySummary,
          top_queries: activeSessionHistoryQueries.map((query) => ({ ...query, query_text: null })),
        },
      });
    });

    it('explains where query text comes from', () => {
      const help = wrapper.findByTestId('query-text-help');

      expect(help.text()).toBe(
        'Query text comes from pg_stat_statements, and none was found for these queries. How do I get query text?',
      );
      expect(help.find('a').attributes('href')).toBe(
        '/help/administration/monitoring/performance/_index.md#query-ids-and-text',
      );
    });
  });

  describe('time range', () => {
    beforeEach(async () => {
      await createComponent();
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, activeSessionHistorySummary);
    });

    it('offers the last 1, 4, 12 and 24 hours, and a custom range, under a label', () => {
      expect(
        findDateRangeListbox()
          .props('items')
          .map(({ value }) => value),
      ).toEqual(['1h', '4h', '12h', '24h', 'custom']);
      expect(findDateRangeListbox().props('selected')).toBe('1h');
      expect(findTimeRangeGroup().find('legend, label').text()).toBe('Time range');
      expect(findDatetimeRangePicker().exists()).toBe(false);
      expect(wrapper.findByText(dateRangeLimits).exists()).toBe(false);
    });

    it('reads a chosen preset right away, counting back from now', async () => {
      await selectDateRange('12h');

      expect(summaryRequests().at(-1).params).toEqual({
        from: '2026-10-14T22:00:00.000Z',
        to: '2026-10-15T10:00:00.000Z',
      });
    });

    describe('when a custom range is chosen', () => {
      beforeEach(async () => {
        await selectDateRange('custom');
      });

      it('opens the picker for starts from 30 days back to today, across midnight', () => {
        expect(findDatetimeRangePicker().props()).toMatchObject({
          startOpened: true,
          defaultMinDate: new Date('2026-09-15T10:00:00Z'),
          maxDateRange: 2,
        });
        expect(wrapper.findAllComponents(GlDatepicker).at(0).props('maxDate')).toEqual(
          new Date('2026-10-15T10:00:00Z'),
        );
      });

      it('states the limits', () => {
        expect(wrapper.findByText(dateRangeLimits).exists()).toBe(true);
      });

      it('waits for both dates without an error or a read', () => {
        expect(findTimeRangeGroup().attributes('aria-invalid')).toBeUndefined();
        expect(findErrorAlert().exists()).toBe(false);
        expect(findWaitEventTypeRows()).toHaveLength(2);
        expect(summaryRequests()).toHaveLength(1);
      });

      it('hides the picker when a preset is chosen again', async () => {
        await selectDateRange('4h');

        expect(findDatetimeRangePicker().exists()).toBe(false);
      });
    });

    it('reads the custom time range again when Custom is chosen after a preset', async () => {
      await pickCustomDateRange('2026-10-14T13:00:00Z', '2026-10-14T15:30:00Z');
      await selectDateRange('4h');
      await selectDateRange('custom');

      expect(summaryRequests().at(-1).params).toEqual({
        from: '2026-10-14T13:00:00.000Z',
        to: '2026-10-14T15:30:00.000Z',
      });
    });

    it('stays on the chosen table when another time range loads', async () => {
      await wrapper.findAll('[role="tab"]').at(1).trigger('click');
      await selectDateRange('4h');

      expect(wrapper.find('[role="tab"][aria-selected="true"]').text()).toBe('Top queries');
    });

    it.each`
      description                                        | startDate                 | endDate
      ${'a custom time range'}                           | ${'2026-10-14T13:00:00Z'} | ${'2026-10-14T15:30:00Z'}
      ${'a 61-minute range just after the 30-day limit'} | ${'2026-09-15T10:01:00Z'} | ${'2026-09-15T11:02:00Z'}
    `('reads $description once both dates are picked', async ({ startDate, endDate }) => {
      await pickCustomDateRange(startDate, endDate);

      expect(findTimeRangeGroup().attributes('aria-invalid')).toBeUndefined();
      expect(summaryRequests().at(-1).params).toEqual({
        from: new Date(startDate).toISOString(),
        to: new Date(endDate).toISOString(),
      });
    });

    describe.each`
      description                                         | startDate                 | endDate                   | message
      ${'over 24 hours'}                                  | ${'2026-10-13T09:00:00Z'} | ${'2026-10-14T09:01:00Z'} | ${'Choose a time range of up to 24 hours.'}
      ${'starting in the future'}                         | ${'2026-10-15T11:00:00Z'} | ${'2026-10-15T13:00:00Z'} | ${'Choose a start in the past.'}
      ${'ending before it starts'}                        | ${'2026-10-14T15:00:00Z'} | ${'2026-10-14T13:00:00Z'} | ${'Choose an end after the start.'}
      ${'ending when it starts'}                          | ${'2026-10-14T13:00:10Z'} | ${'2026-10-14T13:00:10Z'} | ${'Choose an end after the start.'}
      ${'within one minute'}                              | ${'2026-10-14T13:00:10Z'} | ${'2026-10-14T13:00:50Z'} | ${'Choose an end at least one minute after the start.'}
      ${'starting over 30 days back'}                     | ${'2026-09-15T09:00:00Z'} | ${'2026-09-15T11:00:00Z'} | ${'Choose a start within the last 30 days.'}
      ${'shorter than 61 minutes, near the 30-day limit'} | ${'2026-09-15T10:20:00Z'} | ${'2026-09-15T10:40:00Z'} | ${'A time range shorter than 61 minutes is read as the 61 minutes before its end, which would start over 30 days ago. Choose a later end.'}
    `('with a custom time range $description', ({ startDate, endDate, message }) => {
      beforeEach(async () => {
        await pickCustomDateRange(startDate, endDate);
      });

      it('says what to change instead of reading it', () => {
        expect(wrapper.findByText(message).exists()).toBe(true);
        expect(findTimeRangeGroup().attributes('aria-invalid')).toBe('true');
        expect(findDatetimeRangePicker().props('state')).toBe(false);
        expect(summaryRequests()).toHaveLength(1);
      });
    });

    it('shows the period pg_ash read when it differs from the window', async () => {
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, {
        ...activeSessionHistorySummary,
        window: { from: '2026-10-14T09:59:00Z', to: '2026-10-15T09:59:00Z' },
        coverage: { from: '2026-10-14T09:00:00Z', to: '2026-10-15T10:00:00Z', source: 'rollup_1h' },
      });
      await selectDateRange('24h');

      expect(findTimeRange()).toBe(
        'Time range: Oct 14, 2026, 9:00 AM GMT – Oct 15, 2026, 10:00 AM GMT',
      );
    });
  });

  describe('in a time zone whose clocks changed in the last 30 days', () => {
    useFakeDate(2026, 10, 10, 10, 0);

    beforeEach(async () => {
      timezoneMock.register('US/Eastern');
      await createComponent();
    });

    afterEach(() => {
      timezoneMock.unregister();
    });

    it('rejects starts over 30 days back in UTC, as the server does', async () => {
      await pickCustomDateRange('2026-10-11T09:30:00Z', '2026-10-11T11:00:00Z');

      expect(wrapper.findByText('Choose a start within the last 30 days.').exists()).toBe(true);
      expect(summaryRequests()).toHaveLength(1);
    });
  });

  describe('as time passes while the tab is open', () => {
    beforeEach(() => {
      jest.useFakeTimers({ legacyFakeTimers: false });
      jest.setSystemTime(new Date('2026-10-15T10:00:00Z'));
    });

    afterEach(() => {
      jest.useFakeTimers({ legacyFakeTimers: true });
    });

    it('counts the 30 days back from when Custom is chosen', async () => {
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, activeSessionHistorySummary);
      wrapper = mountExtended(ActiveSessionHistoryApp);

      jest.setSystemTime(new Date('2026-10-16T09:00:00Z'));
      findDateRangeListbox().vm.$emit('select', 'custom');
      await nextTick();

      expect(findDatetimeRangePicker().props('defaultMinDate')).toEqual(
        new Date('2026-09-16T09:00:00Z'),
      );
    });

    it('checks a picked range against the time it is picked', async () => {
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, activeSessionHistorySummary);
      wrapper = mountExtended(ActiveSessionHistoryApp);
      findDateRangeListbox().vm.$emit('select', 'custom');
      await nextTick();

      jest.setSystemTime(new Date('2026-10-15T10:05:00Z'));
      findDatetimeRangePicker().vm.$emit('input', {
        startDate: new Date('2026-10-15T10:02:00Z'),
        endDate: new Date('2026-10-15T10:04:00Z'),
      });
      await waitForPromises();

      expect(summaryRequests().at(-1).params).toEqual({
        from: '2026-10-15T10:02:00.000Z',
        to: '2026-10-15T10:04:00.000Z',
      });
    });
  });

  describe('when the time range changes while a read runs', () => {
    let settleFirst;

    beforeEach(async () => {
      mockAxios.onGet(summaryUrl).replyOnce(
        () =>
          new Promise((resolve) => {
            settleFirst = resolve;
          }),
      );
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await nextTick();
    });

    it.each`
      description           | firstReply
      ${'an older result'}  | ${[HTTP_STATUS_OK, { installed: false }]}
      ${'an older failure'} | ${[HTTP_STATUS_INTERNAL_SERVER_ERROR]}
    `('keeps the latest result over $description that arrives later', async ({ firstReply }) => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, activeSessionHistorySummary);
      await selectDateRange('4h');

      settleFirst(firstReply);
      await waitForPromises();

      expect(wrapper.findByTestId('not-installed').exists()).toBe(false);
      expect(findErrorAlert().exists()).toBe(false);
      expect(findWaitEventTypeRows()).toHaveLength(2);
    });

    it('keeps loading until the latest read settles, even when an older one settles first', async () => {
      mockAxios.onGet(summaryUrl).replyOnce(() => new Promise(() => {}));
      await selectDateRange('4h');

      settleFirst([HTTP_STATUS_OK, activeSessionHistorySummary]);
      await waitForPromises();

      expect(findSkeletonLoader().exists()).toBe(true);
      expect(findWaitEventTypeRows()).toHaveLength(0);
    });
  });
});
