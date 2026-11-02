import stage from 'test_fixtures/graphql/ci/job_details/integration/stage.json';
import stageFailed from 'test_fixtures/graphql/ci/job_details/integration/stage_failed.json';
import stageFailedRetried from 'test_fixtures/graphql/ci/job_details/integration/stage_failed_retried.json';
import { defineRestFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineRestFixtureVariants({
  query: 'restStage',
  variants: {
    BASE: stage,
    FAILED: stageFailed,
    FAILED_RETRIED: stageFailedRetried,
  },
});
