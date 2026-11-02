import getWorkItemsSlimBase from 'test_fixtures/graphql/work_items/integration/get_work_items_slim.query.graphql.json';
import getWorkItemsSlimClosed from 'test_fixtures/graphql/work_items/integration/get_work_items_slim_closed.query.graphql.json';
import getWorkItemsSlimAll from 'test_fixtures/graphql/work_items/integration/get_work_items_slim_all.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';
import { listFilterVariants } from './list_filter_variants';

const filterVariants = listFilterVariants('slim');

export default defineFixtureVariants({
  query: 'getWorkItemsSlimEE',
  variants: {
    BASE: getWorkItemsSlimBase,
    EMPTY: setFixtureItemsCount({
      fixture: getWorkItemsSlimBase,
      lookupKey: 'workItems',
      itemCount: 0,
    }),
    MANY_PAGES: setFixtureItemsCount({
      fixture: getWorkItemsSlimBase,
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
    CLOSED: getWorkItemsSlimClosed,
    ALL: getWorkItemsSlimAll,
    ...filterVariants,
  },
});
