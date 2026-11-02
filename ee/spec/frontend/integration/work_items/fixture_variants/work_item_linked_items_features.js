import { cloneDeep } from 'lodash-es';
import workItemLinkedItemsFeaturesBase from 'test_fixtures/graphql/work_items/integration/work_item_linked_items_features.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

const withoutLinkedItems = (fixture) => {
  const clone = cloneDeep(fixture);
  clone.data.namespace.workItem.features.linkedItems.linkedItems.nodes = [];
  return clone;
};

export default defineFixtureVariants({
  query: 'workItemLinkedItemsFeatures',
  variants: {
    BASE: workItemLinkedItemsFeaturesBase,
    EMPTY: withoutLinkedItems(workItemLinkedItemsFeaturesBase),
  },
});
