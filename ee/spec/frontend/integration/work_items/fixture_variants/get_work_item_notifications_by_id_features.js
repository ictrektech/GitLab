import getWorkItemNotificationsByIdFeaturesBase from 'test_fixtures/graphql/work_items/integration/get_work_item_notifications_by_id_features.query.graphql.json';
import getWorkItemNotificationsByIdFeaturesNonMember from 'test_fixtures/graphql/work_items/integration/get_work_item_notifications_by_id_non_member_features.query.graphql.json';
import getWorkItemNotificationsByIdFeaturesAnonymous from 'test_fixtures/graphql/work_items/integration/get_work_item_notifications_by_id_anonymous_features.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getWorkItemNotificationsByIdFeatures',
  variants: {
    BASE: getWorkItemNotificationsByIdFeaturesBase,
    NON_MEMBER: getWorkItemNotificationsByIdFeaturesNonMember,
    ANONYMOUS: getWorkItemNotificationsByIdFeaturesAnonymous,
  },
});
