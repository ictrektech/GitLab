import { GlTableLite } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SeatLinkPanel from 'ee/admin/subscriptions/billable_usage_report/components/seat_link_panel.vue';

const summary = { recordCount: 212, highestBillableUsers: 1438, billableUsersOnLastDay: 1412 };

describe('SeatLinkPanel', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = mountExtended(SeatLinkPanel, { propsData: { summary, ...props } });
  };

  const findRecordCount = () => wrapper.findByTestId('seat-link-records');
  const cellTexts = () =>
    wrapper
      .findComponent(GlTableLite)
      .findAll('tbody td')
      .wrappers.map((cell) => cell.text());

  it('reports the record count, formatted', () => {
    createComponent();

    expect(findRecordCount().text()).toBe('212 daily records');
  });

  it('uses the singular for a one-day report', () => {
    createComponent({
      summary: { recordCount: 1, highestBillableUsers: 12, billableUsersOnLastDay: 12 },
    });

    expect(findRecordCount().text()).toBe('1 daily record');
  });

  it('renders one row of formatted figures', () => {
    createComponent({ licensedSeats: 1500 });

    expect(cellTexts()).toEqual(['1,438', '1,412', '1,500']);
  });

  // licensedSeats comes from a data attribute rather than the report, so it is absent on an
  // instance whose licence could not be read. A dash is clearer than a zero, which would
  // read as a real seat count.
  it('renders a dash when the licensed seat count is unknown', () => {
    createComponent();

    expect(cellTexts()).toEqual(['1,438', '1,412', '-']);
  });

  it('renders zeroes rather than blanks for a report with no seat link data', () => {
    createComponent({
      summary: { recordCount: 0, highestBillableUsers: 0, billableUsersOnLastDay: 0 },
      licensedSeats: 0,
    });

    expect(findRecordCount().text()).toBe('0 daily records');
    expect(cellTexts()).toEqual(['0', '0', '0']);
  });
});
