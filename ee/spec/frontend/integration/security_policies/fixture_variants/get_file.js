import base from 'test_fixtures/graphql/security_policies/integration/get_file.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

// `doesFileExist` reads presence from the length of `blobs.nodes` alone.
export default defineFixtureVariants({
  query: 'getFile',
  variants: {
    BASE: base,
    MISSING: setFixtureData(base, { path: 'project.repository.blobs.nodes' }, []),
  },
});
