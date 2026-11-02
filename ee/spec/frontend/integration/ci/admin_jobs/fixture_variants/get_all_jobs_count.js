import base from 'test_fixtures/graphql/ci/admin_jobs/integration/get_all_jobs_count.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getAllJobsCount',
  variants: {
    BASE: base,
    EMPTY: setFixtureItemsCount({ fixture: base, lookupKey: 'jobs', itemCount: 0 }),
  },
});
