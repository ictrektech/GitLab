import workItemCrmContactsBase from 'test_fixtures/graphql/work_items/integration/work_item_crm_contacts.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { withoutMetadataPermission } from './edit_permissions';

export default defineFixtureVariants({
  query: 'workItemCrmContacts',
  variants: {
    BASE: workItemCrmContactsBase,
    READ_ONLY: withoutMetadataPermission(workItemCrmContactsBase),
  },
});
