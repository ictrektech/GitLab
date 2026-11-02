import base from 'test_fixtures/graphql/packages_and_registries/package_registry/integration/get_packages_count.query.graphql.json';
import groupBase from 'test_fixtures/graphql/packages_and_registries/package_registry/integration/get_packages_count_group.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getPackagesCount',
  variants: {
    BASE: base,
    EMPTY: setFixtureData(base, 'count', 0),
    GROUP_EMPTY: setFixtureData(groupBase, 'count', 0),
  },
});
