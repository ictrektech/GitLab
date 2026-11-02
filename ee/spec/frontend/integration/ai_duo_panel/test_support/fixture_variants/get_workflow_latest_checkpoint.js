import base from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint.query.graphql.json';
import archived from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_archived.query.graphql.json';
import firstThread from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_first_thread.query.graphql.json';
import secondThread from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_second_thread.query.graphql.json';
import withContext from 'test_fixtures/graphql/ai_duo_panel/integration/get_workflow_latest_checkpoint_with_context.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData, setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

const NODE_PATH = 'duoWorkflowWorkflows.nodes[0]';

export default defineFixtureVariants({
  query: 'getWorkflowLatestCheckpoint',
  variants: {
    BASE: base,
    // Same capture as BASE. A spec selecting a conversation explicitly cannot ask for
    // BASE, because an active BASE means "no variant" and falls through.
    ACTIVE: base,
    ARCHIVED: archived,
    FIRST_THREAD: firstThread,
    SECOND_THREAD: secondThread,
    // Same thread, mid-turn: what the client sees when it opens a thread whose
    // reply is still running. Both statuses move together, since a RUNNING
    // checkpoint on an INPUT_REQUIRED workflow is not a shape the API produces.
    SECOND_THREAD_RUNNING: setFixtureData(
      setFixtureData(secondThread, { path: `${NODE_PATH}.status` }, 'RUNNING'),
      { path: `${NODE_PATH}.latestCheckpoint.workflowStatus` },
      'RUNNING',
    ),
    WITH_CONTEXT: withContext,
    // The query looks a workflow up by id, so an empty node list is how the API
    // says it does not exist. The chat reads that as a deleted thread.
    NOT_FOUND: setFixtureItemsCount({
      fixture: base,
      lookupKey: 'duoWorkflowWorkflows',
      itemCount: 0,
    }),
  },
});
