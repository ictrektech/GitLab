import getWorkItemNotificationsByIdBase from 'test_fixtures/graphql/work_items/integration/get_work_item_notifications_by_id.query.graphql.json';
import getWorkItemNotificationsByIdNonMember from 'test_fixtures/graphql/work_items/integration/get_work_item_notifications_by_id_non_member.query.graphql.json';
import getWorkItemNotificationsByIdAnonymous from 'test_fixtures/graphql/work_items/integration/get_work_item_notifications_by_id_anonymous.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

// Readers who start unsubscribed. Activate with the matching namespaceWorkItem variant.
export default defineFixtureVariants({
  query: 'getWorkItemNotificationsById',
  variants: {
    BASE: getWorkItemNotificationsByIdBase,
    NON_MEMBER: getWorkItemNotificationsByIdNonMember,
    ANONYMOUS: getWorkItemNotificationsByIdAnonymous,
  },
});
