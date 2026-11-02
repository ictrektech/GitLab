import base from 'test_fixtures/graphql/home_panel/integration/set_star_status.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureErrors } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'setStarStatus',
  variants: {
    BASE: base,
    ERROR: setFixtureErrors(base, ['Something went wrong']),
  },
});
