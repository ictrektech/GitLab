import {
  findToastMessages,
  getText,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import restJobVariants from './fixture_variants/rest_job';
import {
  PIPELINE_TEST_REPORT_URL,
  TEST_REPORT_SUMMARY_URL,
  findEmptyState,
  findErasedBlock,
  findEraseButton,
  findJobLog,
  findJobName,
  findJobSidebar,
  findLogLine,
  findStageJobLinks,
  findTestSummaryLink,
  mountJobDetails,
  searchJobLog,
  useErasedJob,
  useFailedJob,
  useFailedStage,
  useJobWithoutTrace,
  useNoTraceResponse,
  useParallelJob,
  useRetriedFailedStage,
} from './test_setup';

const stageJobTitles = () => findStageJobLinks().map((link) => link.getAttribute('title'));

describe('Job details page', () => {
  describe('when the job succeeded with a job log', () => {
    beforeEach(async () => {
      mountJobDetails();
      await waitForElement(findLogLine);
    });

    it('shows the job name and the job log', async () => {
      const jobName = await waitForElement(findJobName);

      expect(getText(jobName)).toBe(restJobVariants.BASE.name);
      expect(findJobLog()).not.toBe(null);
    });

    // This test only covers the frontend's contract with rails-ujs for the erase action.
    // The backend tests the POST action in the 'POST erase' block of spec/controllers/projects/jobs_controller_spec.rb
    it('offers to erase the job log after confirmation', async () => {
      const eraseButton = await waitForElement(findEraseButton);

      expect(eraseButton.getAttribute('href')).toBe(restJobVariants.BASE.erase_path);
      expect(eraseButton.dataset.method).toBe('post');
      expect(eraseButton.dataset.confirm).toBe(
        'Are you sure you want to erase this job log and artifacts?',
      );
      expect(eraseButton.getAttribute('aria-label')).toBe('Erase job log and artifacts');
    });

    describe('job log search', () => {
      describe('when the search term matches log lines', () => {
        beforeEach(async () => {
          await searchJobLog('GroupsHelper');
        });

        it('shows the number of matches in a toast', async () => {
          await waitForAssertion(() => {
            expect(findToastMessages()).toContain('26 results found for GroupsHelper');
          });
        });
      });

      describe('when the search term matches nothing', () => {
        beforeEach(async () => {
          await searchJobLog('YouWontFindMe');
        });

        it('shows a no-results toast', async () => {
          await waitForAssertion(() => {
            expect(findToastMessages()).toContain('No search results found');
          });
        });
      });
    });
  });

  describe('when the job log has been erased', () => {
    beforeEach(async () => {
      useErasedJob();
      useNoTraceResponse();
      mountJobDetails();
      await waitForElement(findErasedBlock);
      await waitForElement(findJobName);
    });

    it('shows who erased the job', () => {
      const { username } = restJobVariants.ERASED.erased_by;

      expect(getText(findErasedBlock())).toContain(`Job has been erased by ${username}`);
      expect(getText(findEmptyState())).toContain('Job has been erased');
      expect(getText(findJobSidebar())).toContain('Erased');
    });

    it('offers no erase action, job log, or artifacts', () => {
      expect(findEraseButton()).toBe(null);
      expect(findJobLog()).toBe(null);
      expect(getText(findJobSidebar())).not.toContain('Job artifacts');
    });
  });

  describe('when the job has no job log', () => {
    beforeEach(() => {
      useJobWithoutTrace();
      useNoTraceResponse();
      mountJobDetails();
    });

    it('shows the missing trace empty state', async () => {
      const emptyState = await waitForElement(findEmptyState);

      expect(getText(emptyState)).toContain('This job does not have a trace.');
      expect(findJobLog()).toBe(null);
    });
  });

  describe('when the job is a parallel job with a test report', () => {
    beforeEach(() => {
      useParallelJob();
      mountJobDetails({ testReportSummaryUrl: TEST_REPORT_SUMMARY_URL });
    });

    it('links the test summary to the pipeline test report for the job group', async () => {
      const link = await waitForElement(findTestSummaryLink);

      expect(link.getAttribute('href')).toBe(`${PIPELINE_TEST_REPORT_URL}?job_name=rspec`);
    });
  });

  describe('when the job failed', () => {
    beforeEach(() => {
      useFailedJob();
      useFailedStage();
      mountJobDetails();
    });

    it('shows the failure reason in the stage jobs list', async () => {
      await waitForAssertion(() => {
        expect(stageJobTitles()).toContain('test - Failed - (unknown failure)');
      });
    });
  });

  describe('when a failed job in the stage was retried', () => {
    beforeEach(() => {
      useRetriedFailedStage();
      mountJobDetails();
    });

    it('shows the failure reason and the retried label', async () => {
      await waitForAssertion(() => {
        expect(stageJobTitles()).toContain('test - Failed - (unknown failure) (retried)');
      });
    });
  });
});
