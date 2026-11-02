import duoChatAvailableBase from 'test_fixtures/graphql/ai_duo_panel/integration/duo_chat_available.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'duoChatAvailable',
  variants: {
    BASE: setFixtureData(duoChatAvailableBase, 'duoChatAvailable', false),
    AVAILABLE: duoChatAvailableBase,
  },
});
