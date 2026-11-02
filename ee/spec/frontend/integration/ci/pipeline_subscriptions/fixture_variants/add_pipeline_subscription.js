import base from 'test_fixtures/graphql/ci/pipeline_subscriptions/integration/add_pipeline_subscription.mutation.graphql.json';
import notFound from 'test_fixtures/graphql/ci/pipeline_subscriptions/integration/add_pipeline_subscription_not_found.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'addPipelineSubscription',
  variants: {
    BASE: base,
    NOT_FOUND: notFound,
  },
});
