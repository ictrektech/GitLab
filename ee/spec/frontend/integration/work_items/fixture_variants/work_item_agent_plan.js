import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

// The standalone workItemAgentPlan query has no Rails-generated fixture; the handler
// builds its response from the active variant's `content`. BASE resolves an empty plan;
// WITH_CONTENT carries the saved workplan content asserted by the details spec.
const BASE_DATA = { content: '', contentHtml: '', aiPlanningEnabled: true, readinessScore: null };
const buildQuestions = ({ answered }) => ({
  __typename: 'WorkItemAgentPlanQuestionConnection',
  nodes: [{ __typename: 'WorkItemAgentPlanQuestion', noteId: 'gid://gitlab/Note/2', answered }],
});

export default defineFixtureVariants({
  query: 'workItemAgentPlan',
  variants: {
    BASE: { data: BASE_DATA },
    WITH_CONTENT: {
      data: {
        content: 'Existing workplan content',
        contentHtml: '<p>Existing workplan content</p>',
        aiPlanningEnabled: true,
        readinessScore: null,
      },
    },
    AWAITING_ONE_OPEN_QUESTION: {
      data: {
        ...BASE_DATA,
        generationStatus: 'NEEDS_INPUT',
        openQuestionsCount: 1,
        questions: buildQuestions({ answered: false }),
      },
    },
    AWAITING_ALL_QUESTIONS_ANSWERED: {
      data: {
        ...BASE_DATA,
        generationStatus: 'NEEDS_INPUT',
        openQuestionsCount: 0,
        questions: buildQuestions({ answered: true }),
      },
    },
    WITH_CONTENT_AND_SCORE: {
      data: {
        content: 'Existing workplan content',
        contentHtml: '<p>Existing workplan content</p>',
        aiPlanningEnabled: true,
        readinessScore: 72,
        readinessScoreFeedbackHtml:
          '<ol><li><strong>Add acceptance criteria.</strong></li></ol><p>Describe the expected behavior.</p>',
      },
    },
    WITH_SCORE_WITHOUT_FEEDBACK: {
      data: { ...BASE_DATA, readinessScore: 72, readinessScoreFeedbackHtml: null },
    },
  },
});
