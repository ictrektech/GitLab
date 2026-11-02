import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import MRWidgetService from 'ee_else_ce/vue_merge_request_widget/services/mr_widget_service';
import ReportsTabCount from '~/merge_requests/reports/tab_count/reports_tab_count.vue';
import { observable } from '~/lib/utils/observable';
import { resetMergeRequestData } from '~/merge_requests/reports/merge_request_data';

jest.mock('ee_else_ce/vue_merge_request_widget/services/mr_widget_service', () => ({
  fetchInitialData: jest.fn(),
}));

jest.mock('~/smart_interval');

const tabData = observable('mr_page_tab_data', { tabs: [] });

const COMPLETE = { active: false, iid: 1, details: { status: {} } };

describe('ReportsTabCount', () => {
  let wrapper;

  const mockData = (data) =>
    MRWidgetService.fetchInitialData.mockResolvedValue({ data: { current_user: {}, ...data } });

  const createComponent = async () => {
    wrapper = shallowMount(ReportsTabCount);

    await waitForPromises();
  };

  beforeEach(() => {
    window.gl = {
      mrWidgetData: {
        merge_request_cached_widget_path: '/cached',
        merge_request_widget_path: '/widget',
      },
    };
    tabData.tabs = [['reports', 'Reports', '/reports', '-']];
  });

  afterEach(() => {
    resetMergeRequestData();
    delete window.gl;
  });

  it.each`
    description              | reports                                                                                                                                                                                                                                                                                                                                                        | expected
    ${'a security scan'}     | ${{ enabled_reports: { sast: true } }}                                                                                                                                                                                                                                                                                                                         | ${'1'}
    ${'license compliance'}  | ${{ enabled_reports: { license_scanning: true } }}                                                                                                                                                                                                                                                                                                             | ${'1'}
    ${'browser performance'} | ${{ browser_performance: { head_path: '/head', base_path: '/base' } }}                                                                                                                                                                                                                                                                                         | ${'1'}
    ${'load performance'}    | ${{ load_performance: { head_path: '/head.json' } }}                                                                                                                                                                                                                                                                                                           | ${'1'}
    ${'metrics'}             | ${{ metrics_reports_path: '/m' }}                                                                                                                                                                                                                                                                                                                              | ${'1'}
    ${'status checks'}       | ${{ api_status_checks_path: '/sc' }}                                                                                                                                                                                                                                                                                                                           | ${'1'}
    ${'every report'}        | ${{ enabled_reports: { dast: true, license_scanning: true }, codequality_reports_path: '/cq', browser_performance: { head_path: '/head', base_path: '/base' }, load_performance: { head_path: '/h' }, accessibility_report_path: '/a11y', metrics_reports_path: '/m', test_reports_path: '/t', terraform_reports_path: '/tf', api_status_checks_path: '/sc' }} | ${'10'}
  `('renders $expected for $description', async ({ reports, expected }) => {
    mockData({ pipeline: COMPLETE, ...reports });

    await createComponent();

    expect(wrapper.text()).toBe(expected);
    expect(tabData.tabs[0][3]).toBe(expected);
  });

  it('counts status checks before the pipeline completes', async () => {
    mockData({ pipeline: { ...COMPLETE, active: true }, api_status_checks_path: '/sc' });

    await createComponent();

    expect(wrapper.text()).toBe('1');
    expect(tabData.tabs[0][3]).toBe('1');
  });
});
