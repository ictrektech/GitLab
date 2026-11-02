import workItemNotesByIidFeaturesBase from 'test_fixtures/graphql/work_items/integration/work_item_notes_by_iid_features.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';
import { AGENT_CREATED_SESSION } from '../fixtures_helper';

const FIRST_NOTE_SESSION_PATH =
  'namespace.workItem.features.notes.discussions.nodes[0].notes.nodes[0].duoCreatedSession';

export default defineFixtureVariants({
  query: 'workItemNotesByIidFeatures',
  variants: {
    BASE: workItemNotesByIidFeaturesBase,
    POSTED_BY_AGENT_SESSION: setFixtureData(
      workItemNotesByIidFeaturesBase,
      { path: FIRST_NOTE_SESSION_PATH },
      AGENT_CREATED_SESSION,
    ),
  },
});
