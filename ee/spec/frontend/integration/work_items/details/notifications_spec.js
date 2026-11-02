import namespaceWorkItemNonMember from 'test_fixtures/graphql/work_items/integration/namespace_work_item_non_member.query.graphql.json';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant, setUserSession } from 'ee_jest/integration/helpers/setup_utils';
import {
  expectGraphQLCalls,
  lastRequestVariables,
  snapshotRequests,
} from 'ee_jest/integration/core/operation_helpers';
import {
  getWorkItemNotificationsById as getWorkItemNotificationsByIdVariants,
  getWorkItemNotificationsByIdFeatures as getWorkItemNotificationsByIdFeaturesVariants,
  namespaceWorkItem as namespaceWorkItemVariants,
  namespaceWorkItemFeatures as namespaceWorkItemFeaturesVariants,
  workItemMetadata as workItemMetadataVariants,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

const { id: WORK_ITEM_ID, title: WORK_ITEM_TITLE } =
  namespaceWorkItemNonMember.data.namespace.workItem;

// The member round trip (off, then on again) lives in describeDrawerInteractions. This spec
// covers the other two readers: an anonymous visitor gets no button, a non-member starts
// unsubscribed and can subscribe.
describe('Work item notifications toggle', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const { findSubscribeButton } = workItemsHelpers;

  // Activate all four together so every response describes the same work item with the
  // same permissions.
  const activateVariantsFor = (reader) => {
    setQueryVariant(namespaceWorkItemVariants)[reader]();
    setQueryVariant(namespaceWorkItemFeaturesVariants)[reader]();
    setQueryVariant(getWorkItemNotificationsByIdVariants)[reader]();
    setQueryVariant(getWorkItemNotificationsByIdFeaturesVariants)[reader]();
  };

  const openDrawer = async () => {
    await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForAssertion(() => {
      expect(testHelpers.getText(workItemsHelpers.findWorkItemTitle())).toContain(WORK_ITEM_TITLE);
    });
  };

  describe.each([false, true])(
    'when the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      describe('when the visitor is not signed in', () => {
        beforeEach(async () => {
          setUserSession(false);
          setQueryVariant(workItemMetadataVariants).anonymous();
          activateVariantsFor('anonymous');

          mountWorkItemsListApp({
            router,
            glFeatures: { workItemFeaturesField },
            isSignedIn: false,
          });
          await openDrawer();
        });

        it('does not render the notifications button', () => {
          expect(findSubscribeButton()).toBe(null);
        });
      });

      describe('when the visitor is not a project member', () => {
        beforeEach(async () => {
          activateVariantsFor('nonMember');

          mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });
          const beforeOpen = snapshotRequests();
          await openDrawer();
          await testHelpers.waitForElement(findSubscribeButton);
          // The button renders "off" before its query is even sent. Wait for that query, or
          // the baseline below counts it as a refetch.
          await testHelpers.waitForAssertion(() =>
            expectGraphQLCalls(beforeOpen, {
              expect: ['getWorkItemNotificationsById'],
              forbid: [],
            }),
          );
        });

        it('subscribes without refetching the work item', async () => {
          expect(findSubscribeButton().dataset.subscribed).toBe('false');

          const baseline = snapshotRequests();

          await testHelpers.waitAndClick(findSubscribeButton);

          await testHelpers.waitForAssertion(() => {
            expect(findSubscribeButton().dataset.subscribed).toBe('true');
            expect(document.body.textContent).toContain('Notifications turned on.');
          });
          await testHelpers.waitForAssertion(() =>
            expectGraphQLCalls(baseline, {
              expect: ['workItemSubscribe'],
              forbid: ['namespaceWorkItem', 'getWorkItemNotificationsById'],
            }),
          );
          expect(lastRequestVariables('workItemSubscribe')).toMatchObject({
            input: { id: WORK_ITEM_ID, subscribed: true },
          });
        });
      });
    },
  );
});
