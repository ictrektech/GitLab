import base from 'test_fixtures/graphql/packages_and_registries/package_registry/integration/get_packages_created_desc.query.graphql.json';
import groupBase from 'test_fixtures/graphql/packages_and_registries/package_registry/integration/get_packages_group_created_desc.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getPackages',
  variants: {
    BASE: base,
    EMPTY: setFixtureItemsCount({ fixture: base, lookupKey: 'packages', itemCount: 0 }),
    GROUP_EMPTY: setFixtureItemsCount({ fixture: groupBase, lookupKey: 'packages', itemCount: 0 }),
  },
});
