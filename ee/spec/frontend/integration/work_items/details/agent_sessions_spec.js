import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import {
  duoChatAvailable as duoChatAvailableVariants,
  workItemNotesByIid as workItemNotesByIidVariants,
  workItemNotesByIidFeatures as workItemNotesByIidFeaturesVariants,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  describeNoRefetchOnMutation,
  FORBIDDEN_LIST_REFETCHES,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

describe('Work item agent sessions', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const findViewSessionButton = () => workItemsHelpers.findInDrawer('view-session-button');

  describeNoRefetchOnMutation({
    router,
    description:
      'refetches only the sessions list after View session is clicked on an agent-posted comment',
    perform: async () => {
      setQueryVariant(duoChatAvailableVariants).available();
      setQueryVariant(workItemNotesByIidVariants).postedByAgentSession();
      setQueryVariant(workItemNotesByIidFeaturesVariants).postedByAgentSession();

      await workItemsHelpers.selectIssue();
      await testHelpers.waitForElement(findViewSessionButton);

      const baseline = snapshotRequests();
      await testHelpers.waitAndClick(findViewSessionButton);

      return baseline;
    },
    expectOps: ['getDuoAgentSessionsOnWorkItem'],
    forbidOps: ['namespaceWorkItem', 'workItemNotesByIid', ...FORBIDDEN_LIST_REFETCHES],
  });
});
