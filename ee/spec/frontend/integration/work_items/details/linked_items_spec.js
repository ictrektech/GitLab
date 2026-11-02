import {
  waitAndClick,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findIssueToEdit,
  findLinkItemAddButton,
  findLinkItemForm,
  findLinkItemsCancelButton,
  findLinkWorkItemSubmitButton,
  findLinkedItemsBody,
  findLinkedItemsCollapseToggle,
  findLinkedItemBlockedByIcon,
  findLinkedItemsEmptyState,
  findLinkedItemRow,
  findRelationshipsWidget,
  findRemoveLinkedItemButton,
  findTokenSelectorInput,
  findTokenSelectorResult,
  selectIssue,
} from 'ee_jest/integration/work_items/test_helpers';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  describeNoRefetchOnMutation,
  mountWorkItemsListApp,
  FORBIDDEN_LIST_REFETCHES,
} from '../drawer_shared_test_helpers';
import { setUserSession, setQueryVariant } from '../../helpers/setup_utils';
import workItemLinkedItems from '../fixture_variants/work_item_linked_items';
import workItemLinkedItemsFeatures from '../fixture_variants/work_item_linked_items_features';

setupWorkItemsListApollo();

describe('Work item linked items integration test', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const openWorkItemWithLinkedItem = async () => {
    // Same as below: render the non-draggable list so the row shows on Vue 3.
    setUserSession(false);
    const baseline = snapshotRequests();

    await selectIssue();
    await waitForElement(findLinkedItemRow);
    // The blocked counts only come from `widgets(onlyTypes: [LINKED_ITEMS])`.
    await waitForElement(findLinkedItemBlockedByIcon);

    return baseline;
  };

  const addLinkedItemFromDrawer = async () => {
    await selectIssue();

    await waitForElement(findRelationshipsWidget);
    await waitAndClick(findLinkItemAddButton);
    await waitForElement(findLinkItemForm);

    const input = await waitForElement(findTokenSelectorInput);
    input.dispatchEvent(new Event('focus', { bubbles: true }));

    await waitAndClick(findTokenSelectorResult);

    // Snapshot once the linked item is selected, just before the add mutation fires.
    const baseline = snapshotRequests();

    await waitAndClick(findLinkWorkItemSubmitButton);

    return baseline;
  };

  const removeLinkedItemFromDrawer = async () => {
    // `vuedraggable` does not render rows in jsdom on Vue 3, so force the
    // non-draggable list (`canReorder` is `isLoggedIn() && canUpdate`) to get a
    // clickable remove button. Cache/network behaviour is the same either way.
    setUserSession(false);
    await selectIssue();
    await waitForElement(findRelationshipsWidget);

    // The linked items query seeds one item, so a row renders on mount.
    // Snapshot once it is rendered, just before the remove mutation fires.
    await waitForElement(findRemoveLinkedItemButton);
    const baseline = snapshotRequests();

    await waitAndClick(findRemoveLinkedItemButton);

    return baseline;
  };

  describe('when the work item has no linked items', () => {
    beforeEach(async () => {
      setQueryVariant(workItemLinkedItems).empty();
      setQueryVariant(workItemLinkedItemsFeatures).empty();
      mountWorkItemsListApp({ router });
      await waitForElement(findIssueToEdit);
      await selectIssue();
      await waitForElement(findRelationshipsWidget);

      await waitForAssertion(() => {
        expect(findLinkedItemsCollapseToggle()?.getAttribute('aria-label')).toBe('Expand');
      });
    });

    it('reveals the empty state when expanded', async () => {
      expect(findLinkedItemsEmptyState()).not.toBeVisible();

      await waitAndClick(findLinkedItemsCollapseToggle);
      await waitForAssertion(() => {
        expect(findLinkedItemsEmptyState()).toBeVisible();
      });

      await waitAndClick(findLinkedItemsCollapseToggle);
      await waitForAssertion(() => {
        expect(findLinkedItemsEmptyState()).not.toBeVisible();
      });
    });
  });

  describe('when the work item has a linked item', () => {
    beforeEach(async () => {
      mountWorkItemsListApp({ router });
      await waitForElement(findIssueToEdit);
      await selectIssue();
      await waitForElement(findRelationshipsWidget);
    });

    it('toggles the body and the add form', async () => {
      expect(findLinkItemAddButton()).not.toBe(null);
      expect(findLinkItemForm()).toBe(null);
      expect(findLinkedItemsBody()).toBeVisible();

      await waitAndClick(findLinkedItemsCollapseToggle);
      await waitForAssertion(() => {
        expect(findLinkedItemsBody()).not.toBeVisible();
      });

      await waitAndClick(findLinkedItemsCollapseToggle);
      await waitForAssertion(() => {
        expect(findLinkedItemsBody()).toBeVisible();
      });

      await waitAndClick(findLinkItemAddButton);
      await waitForElement(findLinkItemForm);

      await waitAndClick(findLinkItemsCancelButton);
      await waitForElementToBeNull(findLinkItemForm);
    });
  });

  // The linked item is also a row in the list, so a linked items query that leaves its cached
  // work item incomplete makes the list refetch.
  describeNoRefetchOnMutation({
    router,
    description: 'opens a work item with a linked item without refetching the work item list',
    perform: openWorkItemWithLinkedItem,
    expectOps: ['workItemLinkedItems'],
    forbidOps: FORBIDDEN_LIST_REFETCHES,
  });

  // Adding a linked item must update the Apollo cache in place via the
  // addLinkedItems mutation and must NOT trigger a refetch of the
  // workItemLinkedItems query.
  describeNoRefetchOnMutation({
    router,
    description: 'adds a linked item without refetching the linked items list',
    perform: addLinkedItemFromDrawer,
    expectOps: ['addLinkedItems'],
    forbidOps: ['workItemLinkedItems', 'namespaceWorkItem', ...FORBIDDEN_LIST_REFETCHES],
  });

  // Removing a linked item must update the Apollo cache in place via the
  // removeLinkedItems mutation and must NOT trigger a refetch of the
  // workItemLinkedItems query.
  describeNoRefetchOnMutation({
    router,
    description: 'removes a linked item without refetching the linked items list',
    perform: removeLinkedItemFromDrawer,
    expectOps: ['removeLinkedItems'],
    forbidOps: ['workItemLinkedItems', 'namespaceWorkItem', ...FORBIDDEN_LIST_REFETCHES],
  });
});
