import base from 'test_fixtures/graphql/ci/job_details/integration/play_job_with_inputs.mutation.graphql.json';
import withError from 'test_fixtures/graphql/ci/job_details/integration/play_job_with_inputs_error.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export const [PLAY_ERROR] = withError.data.jobPlay.errors;

export default defineFixtureVariants({
  query: 'playJobWithInputs',
  variants: {
    BASE: base,
    WITH_ERROR: withError,
  },
});
