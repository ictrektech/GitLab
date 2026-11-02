import workItemNotesByIidBase from 'test_fixtures/graphql/work_items/integration/work_item_notes_by_iid.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';
import { AGENT_CREATED_SESSION } from '../fixtures_helper';

const NOTE_AWARD_PERMISSION_PATH =
  'namespace.workItem.widgets[0].discussions.nodes[0].notes.nodes[0].userPermissions.awardEmoji';
const DISCUSSION_PATH = 'namespace.workItem.widgets[0].discussions.nodes[0]';

const DUO_QUESTION_BODY = `Should over-limit requests be rejected or throttled?

\`\`\`json:duo-question
${JSON.stringify({
  type: 'closed',
  question: 'Reject or throttle over-limit requests?',
  options: [
    { id: 'reject', label: 'Reject immediately', recommended: true },
    { id: 'throttle', label: 'Throttle' },
  ],
})}
\`\`\``;

// The fixture's only thread, turned into an open Duo question the viewer can resolve.
const withDuoQuestion = (fixture) =>
  [
    [`${DISCUSSION_PATH}.notes.nodes[0].body`, DUO_QUESTION_BODY],
    [`${DISCUSSION_PATH}.resolvable`, true],
    [`${DISCUSSION_PATH}.userPermissions.resolveNote`, true],
  ].reduce((variant, [path, value]) => setFixtureData(variant, { path }, value), fixture);

export default defineFixtureVariants({
  query: 'workItemNotesByIid',
  variants: {
    BASE: workItemNotesByIidBase,
    LOCKED: setFixtureData(workItemNotesByIidBase, 'discussionLocked', true),
    // Path selector, not a key walk: awardEmoji also names the reaction connection
    // on the same note, so a first-match walk would blank the reactions instead.
    NO_AWARD_PERMISSION: setFixtureData(
      workItemNotesByIidBase,
      { path: NOTE_AWARD_PERMISSION_PATH },
      false,
    ),
    DUO_QUESTION: withDuoQuestion(workItemNotesByIidBase),
    POSTED_BY_AGENT_SESSION: setFixtureData(
      workItemNotesByIidBase,
      { path: `${DISCUSSION_PATH}.notes.nodes[0].duoCreatedSession` },
      AGENT_CREATED_SESSION,
    ),
  },
});
