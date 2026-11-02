import base from 'test_fixtures/graphql/ci/admin_jobs/integration/get_cancelable_jobs_count.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

// The query aliases `jobs` as `cancelable`, so that is the connection key in the payload.
export default defineFixtureVariants({
  query: 'getCancelableJobsCount',
  variants: {
    BASE: base,
    EMPTY: setFixtureItemsCount({ fixture: base, lookupKey: 'cancelable', itemCount: 0 }),
  },
});
