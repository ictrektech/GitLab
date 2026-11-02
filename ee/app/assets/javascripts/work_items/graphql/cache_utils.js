import { WIDGET_TYPE_WORKPLAN } from 'ee/work_items/constants';
import workItemAgentPlanQuery from './work_item_agent_plan.query.graphql';

export const buildAgentPlanWidget = ({
  content,
  contentHtml,
  aiPlanningEnabled = true,
  readinessScore = null,
  generationStatus = null,
  openQuestionsCount = null,
  questions = null,
}) => ({
  type: WIDGET_TYPE_WORKPLAN,
  content,
  contentHtml,
  aiPlanningEnabled,
  readinessScore,
  generationStatus,
  openQuestionsCount,
  questions,
  __typename: 'WorkItemWidgetAgentPlan',
});

export const writeAgentPlanToCache = ({
  cache,
  workItemId,
  workItemIid,
  content,
  contentHtml,
  aiPlanningEnabled,
  readinessScore,
  generationStatus,
  openQuestionsCount,
  questions,
  useWorkItemFeatures,
  includeReadinessScore = false,
}) => {
  const agentPlan = buildAgentPlanWidget({
    content,
    contentHtml,
    aiPlanningEnabled,
    readinessScore,
    generationStatus,
    openQuestionsCount,
    questions,
  });

  cache.writeQuery({
    query: workItemAgentPlanQuery,
    variables: { id: workItemId, useWorkItemFeatures, includeReadinessScore },
    data: {
      workItem: {
        __typename: 'WorkItem',
        id: workItemId,
        iid: workItemIid,
        ...(useWorkItemFeatures
          ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
          : { widgets: [agentPlan] }),
      },
    },
  });
};
