import namespaceWorkItem from 'test_fixtures/graphql/work_items/integration/namespace_work_item.query.graphql.json';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  namespaceWorkItem as namespaceWorkItemVariants,
  namespaceWorkItemFeatures as namespaceWorkItemFeaturesVariants,
  workItemCrmContacts as workItemCrmContactsVariants,
  workItemCrmContactsFeatures as workItemCrmContactsFeaturesVariants,
  workItemTreeQuery as workItemTreeQueryVariants,
  workItemTreeQueryFeatures as workItemTreeQueryFeaturesVariants,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

const SEEDED_STATUS = namespaceWorkItem.data.namespace.workItem.widgets.find(
  ({ type }) => type === 'STATUS',
).status.name;

// A guest cannot set work item metadata, so every sidebar widget loses its edit button except
// Parent, which `WorkItemPolicy` still allows through `admin_work_item_link`. Asserting Parent
// stays editable is also what proves the sidebar settled before the negative checks run.
describe('Work item sidebar for a guest', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const findSidebar = () => workItemsHelpers.findInDrawer('work-item-overview-right-sidebar');
  const findStatusWidget = () => workItemsHelpers.findInDrawer('work-item-status');
  const findParentWidget = () => workItemsHelpers.findInDrawer('work-item-parent');
  const findEditButtonsIn = (element) =>
    testHelpers.within(element).queryAllByTestId('edit-button');

  describe.each([false, true])(
    'when the workItemFeaturesField flag is %s',
    (workItemFeaturesField) => {
      beforeEach(async () => {
        // Apollo normalises all of these onto the same work item, so they have to agree on its
        // permissions or whichever resolves last decides what the sidebar renders.
        setQueryVariant(namespaceWorkItemVariants).readOnly();
        setQueryVariant(namespaceWorkItemFeaturesVariants).readOnly();
        setQueryVariant(workItemCrmContactsVariants).readOnly();
        setQueryVariant(workItemCrmContactsFeaturesVariants).readOnly();
        setQueryVariant(workItemTreeQueryVariants).readOnly();
        setQueryVariant(workItemTreeQueryFeaturesVariants).readOnly();

        window.gon.features = { ...window.gon.features, workItemFeaturesField };
        mountWorkItemsListApp({ router, glFeatures: { workItemFeaturesField } });

        await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
        await workItemsHelpers.selectIssue();
        await testHelpers.waitForElement(findStatusWidget);
        await testHelpers.waitForElement(findParentWidget);
      });

      it('renders the attributes', () => {
        expect(testHelpers.getText(findStatusWidget())).toContain(SEEDED_STATUS);
        expect(workItemsHelpers.findAssigneesWidget()).not.toBe(null);
        expect(workItemsHelpers.findLabelsWidget()).not.toBe(null);
      });

      it.each(['work-item-status', 'work-item-assignees', 'work-item-labels'])(
        'does not offer to edit %s',
        (testId) => {
          expect(findEditButtonsIn(workItemsHelpers.findInDrawer(testId))).toHaveLength(0);
        },
      );

      it('still offers to edit the parent', () => {
        expect(findEditButtonsIn(findParentWidget())).toHaveLength(1);
      });

      it('offers no other way to edit the sidebar', () => {
        expect(findEditButtonsIn(findSidebar())).toHaveLength(1);
      });
    },
  );
});
