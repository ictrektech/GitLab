import { buildAgentPlanWidget, writeAgentPlanToCache } from 'ee/work_items/graphql/cache_utils';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import workItemAgentPlanReadinessFeedbackQuery from 'ee/work_items/graphql/work_item_agent_plan_readiness_feedback.query.graphql';
import { WIDGET_TYPE_WORKPLAN } from 'ee/work_items/constants';
import { createIssuableCache, expectCacheHit } from 'helpers/apollo_cache_helper';
import { findWorkplanWidget } from 'ee/work_items/utils';

const QUESTIONS = {
  __typename: 'WorkItemAgentPlanQuestionConnection',
  nodes: [
    { __typename: 'WorkItemAgentPlanQuestion', noteId: 'gid://gitlab/Note/1', answered: false },
  ],
};

describe('agent plan cache utils', () => {
  const workItemId = 'gid://gitlab/WorkItem/1';
  const workItemIid = '1';

  describe.each([false, true])('with useWorkItemFeatures %s', (useWorkItemFeatures) => {
    describe('after feedback has been loaded', () => {
      let cache;
      const feedbackVariables = { id: workItemId, useWorkItemFeatures };
      const readFeedback = () =>
        findWorkplanWidget(
          cache.readQuery({
            query: workItemAgentPlanReadinessFeedbackQuery,
            variables: feedbackVariables,
          }).workItem,
        ).readinessScoreFeedbackHtml;

      beforeEach(() => {
        cache = createIssuableCache();
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
          readinessScore: 72,
          useWorkItemFeatures,
          includeReadinessScore: true,
        });
        const agentPlan = {
          __typename: 'WorkItemWidgetAgentPlan',
          type: WIDGET_TYPE_WORKPLAN,
          readinessScoreFeedbackHtml: '<p>Add acceptance criteria</p>',
        };
        cache.writeQuery({
          query: workItemAgentPlanReadinessFeedbackQuery,
          variables: feedbackVariables,
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              ...(useWorkItemFeatures
                ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
                : { widgets: [agentPlan] }),
            },
          },
        });
      });

      it('preserves feedback through a save', () => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'edited plan',
          contentHtml: '<p>edited plan</p>',
          readinessScore: 72,
          useWorkItemFeatures,
          includeReadinessScore: true,
        });

        expectCacheHit(cache, {
          query: workItemAgentPlanReadinessFeedbackQuery,
          variables: feedbackVariables,
        });
        expect(readFeedback()).toBe('<p>Add acceptance criteria</p>');
        expect(
          findWorkplanWidget(
            cache.readQuery({
              query: workItemAgentPlanQuery,
              variables: { ...feedbackVariables, includeReadinessScore: true },
            }).workItem,
          ),
        ).toMatchObject({ content: 'edited plan' });
      });
    });

    describe.each([false, true])('with score gate %s', (includeReadinessScore) => {
      let cache;
      const variables = { id: workItemId, useWorkItemFeatures, includeReadinessScore };

      beforeEach(() => {
        cache = createIssuableCache();
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
          readinessScore: 72,
          useWorkItemFeatures,
          includeReadinessScore,
        });
      });

      it('satisfies the query without refetching', () => {
        expectCacheHit(cache, { query: workItemAgentPlanQuery, variables });
      });

      it('never writes feedback, which has its own query', () => {
        const { workItem } = cache.readQuery({ query: workItemAgentPlanQuery, variables });
        expect(findWorkplanWidget(workItem)).not.toHaveProperty('readinessScoreFeedbackHtml');
      });
    });
  });

  describe('buildAgentPlanWidget', () => {
    it('builds the agent plan widget shape', () => {
      expect(
        buildAgentPlanWidget({
          content: 'some plan',
          contentHtml: '<p>some plan</p>',
          aiPlanningEnabled: true,
          readinessScore: 72,
          generationStatus: 'NEEDS_INPUT',
          openQuestionsCount: 2,
          questions: QUESTIONS,
        }),
      ).toEqual({
        type: WIDGET_TYPE_WORKPLAN,
        content: 'some plan',
        contentHtml: '<p>some plan</p>',
        aiPlanningEnabled: true,
        readinessScore: 72,
        generationStatus: 'NEEDS_INPUT',
        openQuestionsCount: 2,
        questions: QUESTIONS,
        __typename: 'WorkItemWidgetAgentPlan',
      });
    });

    it('defaults the readiness score to null', () => {
      expect(buildAgentPlanWidget({ content: 'some plan' }).readinessScore).toBe(null);
    });

    it('defaults the generation status to null', () => {
      expect(buildAgentPlanWidget({ content: 'some plan' }).generationStatus).toBe(null);
    });

    it('defaults the open questions count to null', () => {
      expect(buildAgentPlanWidget({ content: 'some plan' }).openQuestionsCount).toBe(null);
    });

    it('defaults the questions to null', () => {
      expect(buildAgentPlanWidget({ content: 'some plan' }).questions).toBe(null);
    });
  });

  describe('writeAgentPlanToCache', () => {
    let cache;

    beforeEach(() => {
      cache = { writeQuery: jest.fn() };
    });

    describe('when useWorkItemFeatures is false', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'widgets plan',
          contentHtml: '<p>widgets plan</p>',
          aiPlanningEnabled: true,
          useWorkItemFeatures: false,
        });
      });

      it('writes the widgets shape', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith({
          query: workItemAgentPlanQuery,
          variables: {
            id: workItemId,
            useWorkItemFeatures: false,
            includeReadinessScore: false,
          },
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              iid: workItemIid,
              widgets: [
                buildAgentPlanWidget({
                  content: 'widgets plan',
                  contentHtml: '<p>widgets plan</p>',
                  aiPlanningEnabled: true,
                }),
              ],
            },
          },
        });
      });
    });

    describe('when useWorkItemFeatures is true', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'features plan',
          contentHtml: '<p>features plan</p>',
          aiPlanningEnabled: true,
          useWorkItemFeatures: true,
        });
      });

      it('writes the features shape', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith({
          query: workItemAgentPlanQuery,
          variables: {
            id: workItemId,
            useWorkItemFeatures: true,
            includeReadinessScore: false,
          },
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              iid: workItemIid,
              features: {
                __typename: 'WorkItemFeatures',
                agentPlan: buildAgentPlanWidget({
                  content: 'features plan',
                  contentHtml: '<p>features plan</p>',
                  aiPlanningEnabled: true,
                }),
              },
            },
          },
        });
      });
    });

    describe('when includeReadinessScore is true', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'scored plan',
          contentHtml: '<p>scored plan</p>',
          aiPlanningEnabled: true,
          readinessScore: 85,
          useWorkItemFeatures: false,
          includeReadinessScore: true,
        });
      });

      it('requests the readiness score in the written selection set', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: {
              id: workItemId,
              useWorkItemFeatures: false,
              includeReadinessScore: true,
            },
          }),
        );
      });

      it('preserves the readiness score alongside the new content', () => {
        const { data } = cache.writeQuery.mock.calls[0][0];

        expect(data.workItem.widgets[0]).toMatchObject({
          content: 'scored plan',
          contentHtml: '<p>scored plan</p>',
          readinessScore: 85,
        });
      });
    });

    describe('when the plan carries an open questions count', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'paused plan',
          contentHtml: '<p>paused plan</p>',
          generationStatus: 'NEEDS_INPUT',
          openQuestionsCount: 2,
          questions: QUESTIONS,
          useWorkItemFeatures: false,
        });
      });

      it('preserves the count and questions alongside the new content', () => {
        const { data } = cache.writeQuery.mock.calls[0][0];

        expect(data.workItem.widgets[0]).toMatchObject({
          content: 'paused plan',
          openQuestionsCount: 2,
          questions: QUESTIONS,
        });
      });
    });
  });
});
