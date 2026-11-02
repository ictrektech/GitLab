import {
  responseHasPendingChecks,
  statusChecksSummary,
} from 'ee/vue_merge_request_widget/widgets/status_checks/utils';
import { FAILED, PASSED, PENDING } from 'ee/ci/reports/status_checks_report/constants';

describe('status checks widget extension utils', () => {
  describe('responseHasPendingChecks', () => {
    it('returns true when there is a pending check', () => {
      const response = {
        data: [
          { id: 1, status: FAILED },
          { id: 2, status: PENDING },
          { id: 3, status: PASSED },
        ],
      };
      const result = responseHasPendingChecks(response);

      expect(result).toBe(true);
    });

    it('returns false when there are no pending checks', () => {
      const response = {
        data: [
          { id: 1, status: FAILED },
          { id: 2, status: FAILED },
          { id: 3, status: PASSED },
        ],
      };
      const result = responseHasPendingChecks(response);

      expect(result).toBe(false);
    });
  });

  describe('statusChecksSummary', () => {
    it('reports all passed when every check is approved', () => {
      expect(statusChecksSummary({ approved: [{ id: 1 }] })).toEqual({
        title: 'Status checks all passed',
      });
    });

    it.each`
      description             | checks                                           | subtitle
      ${'failed only'}        | ${{ failed: [{ id: 1 }] }}                       | ${'%{danger_start}1 failed%{danger_end}'}
      ${'pending only'}       | ${{ pending: [{ id: 1 }] }}                      | ${'%{same_start}1 pending%{same_end}'}
      ${'failed and pending'} | ${{ failed: [{ id: 1 }], pending: [{ id: 2 }] }} | ${'%{danger_start}1 failed%{danger_end}, %{same_start}1 pending%{same_end}'}
      ${'no checks at all'}   | ${{}}                                            | ${''}
    `('summarises $description', ({ checks, subtitle }) => {
      expect(statusChecksSummary(checks)).toEqual({ title: 'Status checks', subtitle });
    });
  });
});
