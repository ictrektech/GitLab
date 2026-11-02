import finishedJobsFixture from 'test_fixtures/graphql/ci/admin_jobs/integration/get_all_jobs_finished.query.graphql.json';
import failedJobsFixture from 'test_fixtures/graphql/ci/admin_jobs/integration/get_all_jobs_failed.query.graphql.json';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { FAILED_STATUS, FINISHED_STATUSES } from 'ee_jest/integration/ci/admin_jobs/handlers';
import {
  findButtonByText,
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import getAllJobsVariants from './fixture_variants/get_all_jobs';
import {
  expectJobRowsCount,
  filterByStatus,
  findAllTab,
  findCancelAllJobsButton,
  findCancelJobsModal,
  findEmptyState,
  findFinishedTab,
  findJobNames,
  findJobRows,
  findJobStatuses,
  mountAdminJobsApp,
  useEmptyJobs,
} from './test_setup';

const jobNamesOf = (fixture) => fixture.data.jobs.nodes.map((job) => job.name);

const ALL_JOB_NAMES = jobNamesOf(getAllJobsVariants.BASE);
const FINISHED_JOB_NAMES = jobNamesOf(finishedJobsFixture);
const FAILED_JOB_NAMES = jobNamesOf(failedJobsFixture);
const UNFINISHED_JOB_NAMES = ALL_JOB_NAMES.filter((name) => !FINISHED_JOB_NAMES.includes(name));

// The job cell renders "#<id>: <name>", so match on the name only.
const expectJobNamesToBe = (names) =>
  waitForAssertion(() => {
    expect(findJobNames()).toEqual(names.map((name) => expect.stringContaining(name)));
  });

describe('Admin jobs page', () => {
  describe('when the instance has jobs', () => {
    beforeEach(() => {
      mountAdminJobsApp();
    });

    it('lists every job the API returns on the All tab', async () => {
      await expectJobNamesToBe(ALL_JOB_NAMES);

      expect(findAllTab()).not.toBe(null);
    });

    it('shows the Cancel all jobs button', async () => {
      await waitForElement(findCancelAllJobsButton);
    });

    describe('when Cancel all jobs is clicked', () => {
      beforeEach(async () => {
        await waitAndClick(findCancelAllJobsButton);
      });

      it('asks for confirmation before cancelling', async () => {
        const modal = await waitForElement(findCancelJobsModal);

        expect(getText(modal)).toContain('Are you sure?');
        expect(findButtonByText('Yes, proceed', modal)).not.toBe(null);
      });
    });

    describe('when the Finished tab is selected', () => {
      beforeEach(async () => {
        await expectJobRowsCount(ALL_JOB_NAMES.length);
        await waitAndClick(findFinishedTab);
      });

      it('requests only the finished statuses', async () => {
        await waitForAssertion(() => {
          expect(lastRequestVariables('getAllJobs').statuses).toEqual(FINISHED_STATUSES);
        });
      });

      it('shows only the finished jobs', async () => {
        await expectJobNamesToBe(FINISHED_JOB_NAMES);

        UNFINISHED_JOB_NAMES.forEach((name) => {
          expect(findJobNames()).not.toContainEqual(expect.stringContaining(name));
        });
      });

      it('keeps the Cancel all jobs button', async () => {
        await expectJobNamesToBe(FINISHED_JOB_NAMES);

        expect(findCancelAllJobsButton()).not.toBe(null);
      });
    });

    describe('when filtering by the Failed status', () => {
      beforeEach(async () => {
        await expectJobRowsCount(ALL_JOB_NAMES.length);
        await filterByStatus('Failed');
      });

      it('requests only failed jobs', async () => {
        await waitForAssertion(() => {
          expect(lastRequestVariables('getAllJobs').statuses).toEqual(FAILED_STATUS);
        });
      });

      it('shows only the failed job with its status', async () => {
        await expectJobNamesToBe(FAILED_JOB_NAMES);

        expect(findJobStatuses()).toEqual(['Failed']);
      });
    });
  });

  describe('when the instance has no jobs', () => {
    beforeEach(() => {
      useEmptyJobs();
      mountAdminJobsApp();
    });

    it('shows the empty state', async () => {
      await waitForElement(findEmptyState);

      expect(findJobRows()).toHaveLength(0);
    });

    it('does not show the Cancel all jobs button', async () => {
      await waitForElement(findEmptyState);

      expect(findCancelAllJobsButton()).toBe(null);
    });

    describe('when the Finished tab is selected', () => {
      beforeEach(async () => {
        await waitForElement(findEmptyState);
        await waitAndClick(findFinishedTab);
      });

      it('shows "No results found" instead of the empty state', async () => {
        await waitForAssertion(() => {
          expect(getText(document.body)).toContain('No results found');
        });

        expect(findEmptyState()).toBe(null);
      });
    });
  });
});
