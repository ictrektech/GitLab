import base from 'test_fixtures/graphql/cd/integration/cd_environments.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'cdEnvironments',
  variants: {
    BASE: base,
    EMPTY: setFixtureItemsCount({ fixture: base, lookupKey: 'cdEnvironments', itemCount: 0 }),
  },
});
