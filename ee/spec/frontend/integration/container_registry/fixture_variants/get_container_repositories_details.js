import base from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/project_repositories_details.query.graphql.json';
import nameless from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/project_repositories_details_nameless.query.graphql.json';
import many from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/project_repositories_details_many.query.graphql.json';
import groupBase from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/group_repositories_details.query.graphql.json';
import groupSameName from 'test_fixtures/graphql/packages_and_registries/container_registry/integration/group_repositories_details_same_name.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

const withNoRepositories = (fixture) =>
  setFixtureItemsCount({ fixture, lookupKey: 'containerRepositories', itemCount: 0 });

export default defineFixtureVariants({
  query: 'getContainerRepositoriesDetails',
  variants: {
    BASE: base,
    EMPTY: withNoRepositories(base),
    NAMELESS: nameless,
    MANY: many,
    GROUP_EMPTY: withNoRepositories(groupBase),
    GROUP_SAME_NAME: groupSameName,
  },
});
