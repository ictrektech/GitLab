import job from 'test_fixtures/graphql/ci/job_details/integration/job.json';
import jobErased from 'test_fixtures/graphql/ci/job_details/integration/job_erased.json';
import jobNoTrace from 'test_fixtures/graphql/ci/job_details/integration/job_no_trace.json';
import jobParallel from 'test_fixtures/graphql/ci/job_details/integration/job_parallel.json';
import jobFailed from 'test_fixtures/graphql/ci/job_details/integration/job_failed.json';
import jobManual from 'test_fixtures/graphql/ci/job_details/integration/job_manual.json';
import jobManualWithInputs from 'test_fixtures/graphql/ci/job_details/integration/job_manual_with_inputs.json';
import { defineRestFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineRestFixtureVariants({
  query: 'restJob',
  variants: {
    BASE: job,
    ERASED: jobErased,
    NO_TRACE: jobNoTrace,
    PARALLEL: jobParallel,
    FAILED: jobFailed,
    MANUAL: jobManual,
    MANUAL_WITH_INPUTS: jobManualWithInputs,
  },
});
