import restWorkItemsList from 'test_fixtures/graphql/work_items/integration/rest_work_items_list.json';
import restWorkItemsListStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_status_unlicensed.json';
import { defineRestFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineRestFixtureVariants({
  query: 'restWorkItemsList',
  variants: {
    BASE: restWorkItemsList,
    // The list rows carry a status of their own, so an unlicensed namespace needs its own capture.
    STATUS_UNLICENSED: restWorkItemsListStatusUnlicensed,
  },
});
