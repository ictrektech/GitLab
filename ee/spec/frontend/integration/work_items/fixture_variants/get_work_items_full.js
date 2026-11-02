import getWorkItemsFullBase from 'test_fixtures/graphql/work_items/integration/get_work_items_full.query.graphql.json';
import getWorkItemsFullClosed from 'test_fixtures/graphql/work_items/integration/get_work_items_full_closed.query.graphql.json';
import getWorkItemsFullAll from 'test_fixtures/graphql/work_items/integration/get_work_items_full_all.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';
import { listFilterVariants } from './list_filter_variants';

const filterVariants = listFilterVariants('full');

export default defineFixtureVariants({
  query: 'getWorkItemsFullEE',
  variants: {
    BASE: getWorkItemsFullBase,
    EMPTY: setFixtureItemsCount({
      fixture: getWorkItemsFullBase,
      lookupKey: 'workItems',
      itemCount: 0,
    }),
    MANY_PAGES: setFixtureItemsCount({
      fixture: getWorkItemsFullBase,
      lookupKey: 'workItems',
      itemCount: 51,
    }),
    MANY_PAGES_GROUP: setFixtureItemsCount({
      fixture: filterVariants.GROUP,
      lookupKey: 'workItems',
      itemCount: 51,
    }),
    MANY_PAGES_EPICS: setFixtureItemsCount({
      fixture: filterVariants.GROUP_EPICS,
      lookupKey: 'workItems',
      itemCount: 51,
    }),
    CLOSED: getWorkItemsFullClosed,
    ALL: getWorkItemsFullAll,
    ...filterVariants,
  },
});
