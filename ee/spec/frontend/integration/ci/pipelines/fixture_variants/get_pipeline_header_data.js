import base from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data.query.graphql.json';
import afterJobRetry from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_after_job_retry.query.graphql.json';
import afterJobPlay from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_after_job_play.query.graphql.json';
import afterPipelineRetry from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_after_pipeline_retry.query.graphql.json';
import afterPipelineCancel from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_after_pipeline_cancel.query.graphql.json';
import stuck from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_stuck.query.graphql.json';
import configError from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_config_error.query.graphql.json';
import autoDevops from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_auto_devops.query.graphql.json';
import detachedMergeRequest from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_header_data_detached_merge_request.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getPipelineHeaderData',
  variants: {
    BASE: base,
    AFTER_JOB_RETRY: afterJobRetry,
    AFTER_JOB_PLAY: afterJobPlay,
    AFTER_PIPELINE_RETRY: afterPipelineRetry,
    AFTER_PIPELINE_CANCEL: afterPipelineCancel,
    STUCK: stuck,
    CONFIG_ERROR: configError,
    AUTO_DEVOPS: autoDevops,
    DETACHED_MERGE_REQUEST: detachedMergeRequest,
  },
});
