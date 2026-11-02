import { PENDING } from 'ee/ci/reports/status_checks_report/constants';
import { __, s__, sprintf } from '~/locale';

export function responseHasPendingChecks(response) {
  return response.data.some((statusCheck) => statusCheck.status === PENDING);
}

export function statusChecksSummary({ approved = [], pending = [], failed = [] }) {
  if (approved.length > 0 && failed.length === 0 && pending.length === 0) {
    return { title: s__('StatusCheck|Status checks all passed') };
  }

  const reports = [];

  if (failed.length > 0) {
    reports.push(
      `%{danger_start}${sprintf(s__('StatusCheck|%{failed} failed'), {
        failed: failed.length,
      })}%{danger_end}`,
    );
  }
  if (pending.length > 0) {
    reports.push(
      `%{same_start}${sprintf(s__('StatusCheck|%{pending} pending'), {
        pending: pending.length,
      })}%{same_end}`,
    );
  }

  return { title: s__('StatusCheck|Status checks'), subtitle: reports.join(__(', ')) };
}
