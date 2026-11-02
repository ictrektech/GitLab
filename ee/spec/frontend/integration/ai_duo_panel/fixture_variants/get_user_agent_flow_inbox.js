import inboxWithCliSession from 'test_fixtures/graphql/ai_duo_panel/integration/get_user_agent_flow_inbox_with_cli_session.query.graphql.json';
import inboxBase from 'test_fixtures/graphql/ai_duo_panel/integration/get_user_agent_flow_inbox.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

// The inbox has two empty states with different triggers, so it needs two empty
// variants rather than one: the decision tab shows its own copy whenever
// `needsDecision` is empty, while the shared empty state waits until neither alias
// has returned a row.
const withEmptyDecision = setFixtureItemsCount({
  fixture: inboxBase,
  lookupKey: 'needsDecision',
  itemCount: 0,
});

export default defineFixtureVariants({
  query: 'getUserAgentFlowInbox',
  variants: {
    BASE: inboxBase,
    DECISION_EMPTY: withEmptyDecision,
    BOTH_EMPTY: setFixtureItemsCount({
      fixture: withEmptyDecision,
      lookupKey: 'all',
      itemCount: 0,
    }),
    WITH_CLI_SESSION: inboxWithCliSession,
  },
});
