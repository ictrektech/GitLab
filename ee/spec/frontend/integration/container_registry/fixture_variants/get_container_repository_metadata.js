import base from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/repository_metadata_project.query.graphql.json';
import many from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/repository_metadata_project_many.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getContainerRepositoryMetadata',
  variants: {
    BASE: base,
    MANY: many,
  },
});
