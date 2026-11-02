import base from 'test_fixtures/graphql/ci/job_details/integration/get_job.query.graphql.json';
import manual from 'test_fixtures/graphql/ci/job_details/integration/get_job_manual.query.graphql.json';
import manualWithInputs from 'test_fixtures/graphql/ci/job_details/integration/get_job_manual_with_inputs.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getJob',
  variants: {
    BASE: base,
    MANUAL: manual,
    MANUAL_WITH_INPUTS: manualWithInputs,
  },
});
