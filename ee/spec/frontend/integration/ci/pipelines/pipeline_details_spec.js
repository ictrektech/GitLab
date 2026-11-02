import { waitFor } from '@testing-library/vue';
import { apolloProvider } from '~/ci/pipeline_details/pipeline_shared_client';
import {
  expectGraphQLCalls,
  lastRequestVariables,
  snapshotRequests,
} from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  screen,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import pipelineDetailsVariants from './fixture_variants/get_pipeline_details';
import pipelineHeaderVariants from './fixture_variants/get_pipeline_header_data';
import pipelineJobsVariants from './fixture_variants/get_pipeline_jobs';
import pipelinePermissionsVariants from './fixture_variants/get_pipeline_permissions';
import {
  findCancelPipelineButton,
  findDeletePipelineButton,
  findGraph,
  findGraphJob,
  findGraphJobAction,
  findHeader,
  findHeaderBadge,
  findHeaderStatus,
  findJobsTableRow,
  findLinkedPipeline,
  findLinkedPipelineButton,
  findRetryPipelineButton,
  findTabLink,
  mountPipelineDetails,
} from './test_setup';

const { pipeline } = pipelineHeaderVariants.BASE.data.project;

const findStatusIcon = (container, status) =>
  container.querySelector(`[data-testid="status_${status}_borderless-icon"]`);

const hasJobAction = (jobName, icon) =>
  Boolean(findGraphJobAction(jobName)?.classList.contains(`js-icon-${icon}`));

const expectHeaderStatus = (text) =>
  waitForAssertion(() => {
    expect(getText(findHeaderStatus())).toBe(text);
  });

const waitForGraphJob = (jobName) => waitForElement(() => findGraphJob(jobName));

describe('Pipeline details page', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('when the pipeline has jobs in every status', () => {
    beforeEach(async () => {
      mountPipelineDetails();
      await waitForElement(findHeaderStatus);
      await waitForGraphJob('test-job');
    });

    it('shows the pipeline name, job count and status in the header', () => {
      const header = findHeader();

      expect(getText(within(header).queryByTestId('pipeline-name'))).toBe(pipeline.name);
      expect(getText(within(header).queryByTestId('total-jobs'))).toBe(
        `${pipeline.totalJobs} jobs`,
      );
      expect(getText(findHeaderStatus())).toBe('Pending');
    });

    it('marks the pipeline as the latest one', () => {
      expect(findHeaderBadge('latest')).not.toBe(null);
    });

    it('offers to retry and cancel the pipeline, but not to delete it', () => {
      expect(findRetryPipelineButton()).not.toBe(null);
      expect(findCancelPipelineButton()).not.toBe(null);
      expect(findDeletePipelineButton()).toBe(null);
    });

    it('shows the pipeline, jobs and failed jobs tabs with the job count', () => {
      expect(findTabLink('pipeline')).not.toBe(null);
      expect(findTabLink('failed-jobs')).not.toBe(null);
      expect(getText(within(findTabLink('jobs')).queryByTestId('builds-counter'))).toBe(
        String(pipeline.totalJobs),
      );
    });

    it('shows every stage of the pipeline in the graph', () => {
      const graph = findGraph();

      ['build', 'test', 'deploy', 'external'].forEach((stage) => {
        expect(getText(graph)).toContain(stage);
      });
    });

    it.each`
      jobName          | status         | action
      ${'build-job'}   | ${'success'}   | ${'retry'}
      ${'test-job'}    | ${'failed'}    | ${'retry'}
      ${'prepare-job'} | ${'preparing'} | ${'cancel'}
      ${'deploy-job'}  | ${'running'}   | ${'cancel'}
      ${'manual-job'}  | ${'manual'}    | ${'play'}
      ${'delayed-job'} | ${'scheduled'} | ${'time-out'}
    `('shows $jobName as $status with a $action action', ({ jobName, status, action }) => {
      const job = findGraphJob(jobName);

      expect(getText(job)).toContain(jobName);
      expect(findStatusIcon(job, status)).not.toBe(null);
      expect(hasJobAction(jobName, action)).toBe(true);
    });

    it('links the external job to its target URL', () => {
      const job = findGraphJob('jenkins-job');

      expect(findStatusIcon(job, 'success')).not.toBe(null);
      expect(job.querySelector('a').getAttribute('href')).toBe('http://gitlab.com/status');
    });

    describe('when the failed job is retried from the graph', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineDetailsVariants).afterFailedJobRetry();
        setQueryVariant(pipelineHeaderVariants).afterJobRetry();

        await waitAndClick(() => findGraphJobAction('test-job'));
        await waitForAssertion(() => {
          expect(hasJobAction('test-job', 'cancel')).toBe(true);
        });
      });

      it('sends the retry request', () => {
        expect(snapshotRequests().restJobRetry).toBe(1);
      });

      it('shows the job as pending with a cancel action', () => {
        expect(findStatusIcon(findGraphJob('test-job'), 'pending')).not.toBe(null);
      });

      it('shows the pipeline as running in the header', async () => {
        await expectHeaderStatus('Running');
      });
    });

    describe('when the running job is canceled from the graph', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineDetailsVariants).afterRunningJobCancel();

        await waitAndClick(() => findGraphJobAction('deploy-job'));
        await waitForAssertion(() => {
          expect(hasJobAction('deploy-job', 'retry')).toBe(true);
        });
      });

      it('sends the cancel request', () => {
        expect(snapshotRequests().restJobCancel).toBe(1);
      });

      it('shows the job as canceled with a retry action', () => {
        expect(findStatusIcon(findGraphJob('deploy-job'), 'canceled')).not.toBe(null);
      });
    });

    describe('when the manual job is played from the graph', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineDetailsVariants).afterManualJobPlay();
        setQueryVariant(pipelineHeaderVariants).afterJobPlay();

        await waitAndClick(() => findGraphJobAction('manual-job'));
        await waitForAssertion(() => {
          expect(hasJobAction('manual-job', 'cancel')).toBe(true);
        });
      });

      it('sends the play request', () => {
        expect(snapshotRequests().restJobPlay).toBe(1);
      });

      it('shows the pipeline as running in the header', async () => {
        await expectHeaderStatus('Running');
      });
    });

    describe('when the delayed job is unscheduled from the graph', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineDetailsVariants).afterDelayedJobUnschedule();

        await waitAndClick(() => findGraphJobAction('delayed-job'));
        await waitForAssertion(() => {
          expect(hasJobAction('delayed-job', 'play')).toBe(true);
        });
      });

      it('sends the unschedule request', () => {
        expect(snapshotRequests().restJobUnschedule).toBe(1);
      });

      it('shows the job as a manual job with a play action', () => {
        expect(findStatusIcon(findGraphJob('delayed-job'), 'manual')).not.toBe(null);
      });
    });

    describe('when the pipeline is retried from the header', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineHeaderVariants).afterPipelineRetry();

        await waitAndClick(findRetryPipelineButton);
        await expectHeaderStatus('Running');
      });

      it('sends the retry mutation for the pipeline', () => {
        expect(lastRequestVariables('retryPipeline')).toEqual({ id: pipeline.id });
      });

      it('no longer offers to retry the pipeline', () => {
        expect(findRetryPipelineButton()).toBe(null);
      });
    });

    describe('when the pipeline is canceled from the header', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineHeaderVariants).afterPipelineCancel();

        await waitAndClick(findCancelPipelineButton);
        await expectHeaderStatus('Failed');
      });

      it('sends the cancel mutation for the pipeline', () => {
        expect(lastRequestVariables('cancelPipeline')).toEqual({ id: pipeline.id });
      });

      it('no longer offers to cancel the pipeline', () => {
        expect(findCancelPipelineButton()).toBe(null);
      });
    });
  });

  describe('when the pipeline has a downstream pipeline', () => {
    const downstreamPipelineFixture = (variant) =>
      variant.data.project.pipeline.downstream.nodes[0];

    const mountWithDownstream = async (variantName) => {
      setQueryVariant(pipelineDetailsVariants)[variantName]();
      setQueryVariant(pipelinePermissionsVariants).downstream();
      mountPipelineDetails();
      await waitForElement(findLinkedPipeline);
    };

    describe('when the downstream pipeline succeeded', () => {
      beforeEach(async () => {
        await mountWithDownstream('downstreamSuccess');
      });

      it('shows it as successful without retry or cancel actions', () => {
        expect(findStatusIcon(findLinkedPipeline(), 'success')).not.toBe(null);
        expect(findLinkedPipelineButton('Retry downstream pipeline')).toBe(null);
        expect(findLinkedPipelineButton('Cancel downstream pipeline')).toBe(null);
      });
    });

    describe('when the downstream pipeline is running', () => {
      beforeEach(async () => {
        await mountWithDownstream('downstreamRunning');
      });

      describe('when it is canceled', () => {
        beforeEach(async () => {
          setQueryVariant(pipelineDetailsVariants).downstreamAfterCancel();

          await waitAndClick(() => findLinkedPipelineButton('Cancel downstream pipeline'));
          await waitForElement(() => findLinkedPipelineButton('Retry downstream pipeline'));
        });

        it('sends the cancel mutation for the downstream pipeline', () => {
          expect(lastRequestVariables('cancelPipeline')).toEqual({
            id: downstreamPipelineFixture(pipelineDetailsVariants.DOWNSTREAM_RUNNING).id,
          });
        });

        it('shows it as canceled with a retry action', () => {
          expect(findStatusIcon(findLinkedPipeline(), 'canceled')).not.toBe(null);
        });
      });
    });

    describe('when the downstream pipeline failed', () => {
      beforeEach(async () => {
        await mountWithDownstream('downstreamFailed');
      });

      describe('when it is retried', () => {
        beforeEach(async () => {
          setQueryVariant(pipelineDetailsVariants).downstreamAfterRetry();

          await waitAndClick(() => findLinkedPipelineButton('Retry downstream pipeline'));
          await waitForElement(() => findLinkedPipelineButton('Cancel downstream pipeline'));
        });

        it('sends the retry mutation for the downstream pipeline', () => {
          expect(lastRequestVariables('retryPipeline')).toEqual({
            id: downstreamPipelineFixture(pipelineDetailsVariants.DOWNSTREAM_FAILED).id,
          });
        });

        it('shows it as running with a cancel action', () => {
          expect(findStatusIcon(findLinkedPipeline(), 'running')).not.toBe(null);
        });
      });
    });
  });

  describe.each`
    description                                  | variant                   | badge              | text
    ${'is stuck'}                                | ${'stuck'}                | ${'stuck'}         | ${'stuck'}
    ${'uses Auto DevOps'}                        | ${'autoDevops'}           | ${'auto-devops'}   | ${'Auto DevOps'}
    ${'runs for a detached merge request event'} | ${'detachedMergeRequest'} | ${'merge-request'} | ${'merge request'}
  `('when the pipeline $description', ({ variant, badge, text }) => {
    beforeEach(async () => {
      setQueryVariant(pipelineHeaderVariants)[variant]();
      mountPipelineDetails();
      await waitForElement(findHeaderStatus);
    });

    it(`shows the "${text}" badge in the header`, async () => {
      const badgeElement = await waitForElement(() => findHeaderBadge(badge));

      expect(getText(badgeElement)).toBe(text);
    });
  });

  describe('when the pipeline has a configuration error', () => {
    const errorPipeline = pipelineHeaderVariants.CONFIG_ERROR.data.project.pipeline;

    beforeEach(async () => {
      setQueryVariant(pipelineHeaderVariants).configError();
      mountPipelineDetails();
      await waitForElement(() => findHeaderBadge('invalid'));
    });

    it('shows the "yaml invalid" badge with the error in its tooltip', () => {
      expect(getText(findHeaderBadge('invalid'))).toBe('yaml invalid');
      expect(findHeaderBadge('invalid').getAttribute('title')).toBe(
        errorPipeline.errorMessages.nodes[0].content,
      );
    });

    it('shows the failure reason in the failed badge tooltip', () => {
      expect(findHeaderBadge('failed').getAttribute('title')).toBe(errorPipeline.failureReason);
    });
  });

  describe('on the jobs tab', () => {
    beforeEach(async () => {
      mountPipelineDetails({ route: '/builds' });
      await waitForElement(() => findJobsTableRow('delayed-job'));
    });

    it('lists the jobs with the actions they allow', () => {
      const runningRow = findJobsTableRow('deploy-job');
      const delayedRow = findJobsTableRow('delayed-job');

      expect(within(runningRow).queryByTestId('cancel-button')).not.toBe(null);
      expect(within(delayedRow).queryByTestId('unschedule')).not.toBe(null);
      expect(within(findJobsTableRow('manual-job')).queryByTestId('play')).not.toBe(null);
      expect(within(findJobsTableRow('test-job')).queryByTestId('retry')).not.toBe(null);
    });

    describe('when a delayed job is unscheduled', () => {
      beforeEach(async () => {
        setQueryVariant(pipelineJobsVariants).afterUnschedule();

        const baseline = snapshotRequests();
        await waitAndClick(() =>
          within(findJobsTableRow('delayed-job')).queryByTestId('unschedule'),
        );
        await waitFor(() =>
          expectGraphQLCalls(baseline, {
            expect: ['unscheduleJob', 'getPipelineJobs'],
            forbid: [],
          }),
        );
        await waitForElement(() => within(findJobsTableRow('delayed-job')).queryByTestId('play'));
      });

      it('offers to run the job instead of unscheduling it', () => {
        expect(within(findJobsTableRow('delayed-job')).queryByTestId('unschedule')).toBe(null);
      });
    });
  });

  describe('when the tests tab is opened', () => {
    let baseline;

    beforeEach(async () => {
      mountPipelineDetails();
      await waitForElement(findHeaderStatus);

      baseline = snapshotRequests();
      await waitAndClick(() => findTabLink('tests'));
      await waitForElement(() => screen.queryByTestId('tests-detail'));
    });

    it('requests the test summary', () => {
      expectGraphQLCalls(baseline, { expect: ['restPipelineTestReportSummary'], forbid: [] });
    });
  });
});
