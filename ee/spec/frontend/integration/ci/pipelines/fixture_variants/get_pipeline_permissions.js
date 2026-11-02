import base from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_permissions.query.graphql.json';
import downstream from 'test_fixtures/graphql/ci/pipelines/integration/get_pipeline_permissions_downstream.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getPipelinePermissions',
  variants: {
    BASE: base,
    DOWNSTREAM: downstream,
  },
});
