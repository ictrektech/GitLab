import workItemTreeQueryBase from 'test_fixtures/graphql/work_items/integration/work_item_tree_query.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { withoutEditPermissions } from './edit_permissions';

export default defineFixtureVariants({
  query: 'workItemTreeQuery',
  variants: {
    BASE: workItemTreeQueryBase,
    READ_ONLY: withoutEditPermissions(workItemTreeQueryBase),
  },
});
