import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StatusChecksContent from 'ee/merge_requests/reports/status_checks/status_checks_content.vue';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';

describe('StatusChecksContent', () => {
  let wrapper;

  const MOCK_SECTIONS = [{ children: [{ text: 'Foo: http://foo' }] }];
  const ERROR_MESSAGE = 'Failed to load status checks';

  const makeChecks = (approved = 0, pending = 0, failed = 0) => ({
    approved: Array(approved).fill({}),
    pending: Array(pending).fill({}),
    failed: Array(failed).fill({}),
  });

  const DEFAULT_PROVIDE = {
    isStatusChecksLoading: false,
    errorMessage: '',
    checks: makeChecks(2, 0, 0),
    statusIconName: 'success',
    sections: MOCK_SECTIONS,
    retryFetch: jest.fn(),
  };

  const findReportSection = () => wrapper.findComponent(ReportSection);

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMountExtended(StatusChecksContent, {
      provide: {
        ...DEFAULT_PROVIDE,
        ...provide,
      },
    });
  };

  describe('summary text', () => {
    it('shows "all passed" when there are approved checks and no pending or failed checks', () => {
      createComponent();

      expect(findReportSection().props('summary').title).toBe('Status checks all passed');
    });

    it('joins the failed and pending counts', () => {
      createComponent({ provide: { checks: makeChecks(0, 1, 1) } });

      const { subtitle } = findReportSection().props('summary');

      expect(subtitle).toContain('1 failed');
      expect(subtitle).toContain('1 pending');
    });

    it('shows a default title when there are no checks and no error', () => {
      createComponent({ provide: { checks: makeChecks(0, 0, 0) } });

      expect(findReportSection().props('summary').title).toBe('Status checks');
    });

    it('shows the error message when errorMessage is set', () => {
      createComponent({ provide: { errorMessage: ERROR_MESSAGE, statusIconName: 'error' } });

      expect(findReportSection().props('summary').title).toBe(ERROR_MESSAGE);
    });
  });

  describe('action buttons', () => {
    it('passes no action buttons by default and a retry action button when errorMessage is set', () => {
      createComponent();

      expect(findReportSection().props('actionButtons')).toEqual([]);

      createComponent({ provide: { errorMessage: ERROR_MESSAGE } });

      const [actionButton] = findReportSection().props('actionButtons');

      expect(actionButton.text).toBe('Retry');

      actionButton.onClick();

      expect(DEFAULT_PROVIDE.retryFetch).toHaveBeenCalled();
    });
  });
});
