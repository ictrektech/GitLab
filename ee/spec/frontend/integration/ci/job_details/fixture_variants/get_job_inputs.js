import base from 'test_fixtures/graphql/ci/job_details/integration/get_job_inputs.query.graphql.json';
import withInputs from 'test_fixtures/graphql/ci/job_details/integration/get_job_inputs_with_inputs.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getJobInputs',
  variants: {
    BASE: base,
    WITH_INPUTS: withInputs,
  },
});
