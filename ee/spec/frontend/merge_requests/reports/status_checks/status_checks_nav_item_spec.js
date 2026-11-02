import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StatusChecksNavItem from 'ee/merge_requests/reports/status_checks/status_checks_nav_item.vue';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

describe('StatusChecksNavItem', () => {
  let wrapper;

  const findReportListItem = () => wrapper.findComponent(ReportListItem);

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMountExtended(StatusChecksNavItem, {
      provide: {
        isStatusChecksLoading: false,
        statusIconName: 'success',
        ...provide,
      },
    });
  };

  it('passes the route, label text, status icon, and loading state to ReportListItem', () => {
    createComponent({ provide: { isStatusChecksLoading: true, statusIconName: 'warning' } });

    expect(findReportListItem().props('to')).toBe('status-checks');
    expect(findReportListItem().text()).toBe('Status checks');
    expect(findReportListItem().props('statusIcon')).toBe('warning');
    expect(findReportListItem().props('isLoading')).toBe(true);
  });
});
