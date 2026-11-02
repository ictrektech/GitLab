import base from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_jobs.query.graphql.json';
import afterUnschedule from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_jobs_after_unschedule.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getPipelineJobs',
  variants: {
    BASE: base,
    AFTER_UNSCHEDULE: afterUnschedule,
  },
});
