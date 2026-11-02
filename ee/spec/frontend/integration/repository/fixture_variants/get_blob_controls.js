import base from 'test_fixtures/graphql/repository/integration/get_blob_controls.query.graphql.json';
import nonWritable from 'test_fixtures/graphql/repository/integration/get_blob_controls_non_writable.query.graphql.json';
import archived from 'test_fixtures/graphql/repository/integration/get_blob_controls_archived.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getBlobControls',
  variants: {
    BASE: base,
    // Recorded as a reporter: cannot modify the blob but can fork, the state
    // that routes Edit, Web IDE, Replace and Delete to the fork suggestion.
    NON_WRITABLE: nonWritable,
    ARCHIVED: archived,
  },
});
