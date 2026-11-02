import base from 'test_fixtures/graphql/ai_duo_panel/integration/create_ai_duo_workflow.mutation.graphql.json';
import agentDisabled from 'test_fixtures/graphql/ai_duo_panel/integration/create_ai_duo_workflow_agent_disabled.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'createAiDuoWorkflow',
  variants: {
    BASE: base,
    AGENT_DISABLED: agentDisabled,
  },
});
