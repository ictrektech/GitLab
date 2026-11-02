import base from 'test_fixtures/graphql/ci/catalog/integration/get_ci_catalog_resource_shared_data.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureErrors } from 'ee_jest/integration/core/fixture_utils';
import { RESOURCE_NOT_AVAILABLE_ERROR } from '../constants';

export default defineFixtureVariants({
  query: 'getCiCatalogResourceSharedData',
  variants: {
    BASE: base,
    NOT_AVAILABLE: setFixtureErrors(base, [RESOURCE_NOT_AVAILABLE_ERROR]),
  },
});
