import workItemCrmContactsFeaturesBase from 'test_fixtures/graphql/work_items/integration/work_item_crm_contacts_features.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { withoutMetadataPermission } from './edit_permissions';

export default defineFixtureVariants({
  query: 'workItemCrmContactsFeatures',
  variants: {
    BASE: workItemCrmContactsFeaturesBase,
    READ_ONLY: withoutMetadataPermission(workItemCrmContactsFeaturesBase),
  },
});
