import workItemLinkedItemsBase from 'test_fixtures/graphql/work_items/integration/work_item_linked_items.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'workItemLinkedItems',
  variants: {
    BASE: workItemLinkedItemsBase,
    EMPTY: setFixtureItemsCount({
      fixture: workItemLinkedItemsBase,
      lookupKey: 'linkedItems',
      itemCount: 0,
    }),
  },
});
