import base from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details.query.graphql.json';
import afterFailedJobRetry from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_after_failed_job_retry.query.graphql.json';
import afterRunningJobCancel from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_after_running_job_cancel.query.graphql.json';
import afterManualJobPlay from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_after_manual_job_play.query.graphql.json';
import afterDelayedJobUnschedule from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_after_delayed_job_unschedule.query.graphql.json';
import downstreamSuccess from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_downstream_success.query.graphql.json';
import downstreamRunning from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_downstream_running.query.graphql.json';
import downstreamAfterCancel from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_downstream_after_cancel.query.graphql.json';
import downstreamFailed from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_downstream_failed.query.graphql.json';
import downstreamAfterRetry from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_details_downstream_after_retry.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getPipelineDetails',
  variants: {
    BASE: base,
    AFTER_FAILED_JOB_RETRY: afterFailedJobRetry,
    AFTER_RUNNING_JOB_CANCEL: afterRunningJobCancel,
    AFTER_MANUAL_JOB_PLAY: afterManualJobPlay,
    AFTER_DELAYED_JOB_UNSCHEDULE: afterDelayedJobUnschedule,
    DOWNSTREAM_SUCCESS: downstreamSuccess,
    DOWNSTREAM_RUNNING: downstreamRunning,
    DOWNSTREAM_AFTER_CANCEL: downstreamAfterCancel,
    DOWNSTREAM_FAILED: downstreamFailed,
    DOWNSTREAM_AFTER_RETRY: downstreamAfterRetry,
  },
});
