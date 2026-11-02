import base from 'test_fixtures/graphql/ci/catalog/integration/get_ci_catalog_resource_versions.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureErrors } from 'ee_jest/integration/core/fixture_utils';
import { RESOURCE_NOT_AVAILABLE_ERROR } from '../constants';

export default defineFixtureVariants({
  query: 'getCiCatalogResourceVersions',
  variants: {
    BASE: base,
    NOT_AVAILABLE: setFixtureErrors(base, [RESOURCE_NOT_AVAILABLE_ERROR]),
  },
});
