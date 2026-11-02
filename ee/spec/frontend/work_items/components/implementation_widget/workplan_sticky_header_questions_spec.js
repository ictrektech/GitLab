import { GlIcon } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkplanStickyHeaderQuestions from 'ee/work_items/components/implementation_widget/workplan_sticky_header_questions.vue';
import WorkplanQuestionNavigator from 'ee/work_items/components/implementation_widget/workplan_question_navigator.vue';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import { buildAgentPlanWidgetMock } from 'ee_jest/work_items/mock_data';

Vue.use(VueApollo);

describe('WorkplanStickyHeaderQuestions', () => {
  let wrapper;

  const workItemId = 'gid://gitlab/WorkItem/1';
  const questionNodes = [
    {
      __typename: 'WorkItemAgentPlanQuestion',
      noteId: 'gid://gitlab/DiscussionNote/1',
      answered: false,
    },
    {
      __typename: 'WorkItemAgentPlanQuestion',
      noteId: 'gid://gitlab/DiscussionNote/2',
      answered: false,
    },
  ];

  // Stands in for the Workplan widget, which is what fetches the plan this component reads.
  const cacheWorkplan = (apolloProvider, { useWorkItemFeatures = false, ...workplan } = {}) => {
    const agentPlan = buildAgentPlanWidgetMock({
      generationStatus: 'NEEDS_INPUT',
      openQuestionsCount: 2,
      questions: { __typename: 'WorkItemAgentPlanQuestionConnection', nodes: questionNodes },
      ...workplan,
    });

    apolloProvider.clients.defaultClient.cache.writeQuery({
      query: workItemAgentPlanQuery,
      variables: { id: workItemId, useWorkItemFeatures, includeReadinessScore: false },
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: workItemId,
          iid: '1',
          ...(useWorkItemFeatures
            ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
            : { widgets: [agentPlan] }),
        },
      },
    });
  };

  const createComponent = async ({ workplan, glFeatures = {} } = {}) => {
    const apolloProvider = createMockApollo();
    if (workplan) {
      cacheWorkplan(apolloProvider, {
        useWorkItemFeatures: Boolean(glFeatures.workItemFeaturesField),
        ...workplan,
      });
    }

    wrapper = shallowMountExtended(WorkplanStickyHeaderQuestions, {
      apolloProvider,
      propsData: { workItemId },
      provide: { glFeatures },
    });
    await waitForPromises();
  };

  const findQuestions = () => wrapper.findByTestId('sticky-header-workplan-questions');

  describe('when the cached run is awaiting input with open questions', () => {
    beforeEach(async () => {
      await createComponent({ workplan: {} });
    });

    it('renders the awaiting-input icon', () => {
      expect(findQuestions().findComponent(GlIcon).props()).toMatchObject({
        name: 'status',
        variant: 'warning',
      });
    });

    it('renders the count, described for screen readers', () => {
      expect(wrapper.findByTestId('sticky-header-open-questions-count').text()).toBe('2');
      expect(findQuestions().text()).toContain('Awaiting input (2 questions)');
    });

    it('renders the navigator with the questions', () => {
      expect(wrapper.findComponent(WorkplanQuestionNavigator).props('questions')).toEqual(
        questionNodes,
      );
    });
  });

  describe('when workItemFeaturesField is enabled', () => {
    beforeEach(async () => {
      await createComponent({ workplan: {}, glFeatures: { workItemFeaturesField: true } });
    });

    it('reads the plan cached under the features field', () => {
      expect(findQuestions().exists()).toBe(true);
    });
  });

  it.each`
    scenario                        | workplan
    ${'the run is generating'}      | ${{ generationStatus: 'GENERATING' }}
    ${'every question is answered'} | ${{ openQuestionsCount: 0 }}
    ${'no plan is cached'}          | ${undefined}
  `('renders nothing when $scenario', async ({ workplan }) => {
    await createComponent({ workplan });

    expect(findQuestions().exists()).toBe(false);
  });
});
