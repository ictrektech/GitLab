<script>
import { GlIcon } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { findWorkplanWidget } from 'ee/work_items/utils';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import { GENERATION_STATUS_NEEDS_INPUT } from './constants';
import { getAwaitingInputLabel } from './utils';
import WorkplanQuestionNavigator from './workplan_question_navigator.vue';

export default {
  name: 'WorkplanStickyHeaderQuestions',
  components: {
    GlIcon,
    WorkplanQuestionNavigator,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    workItemId: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      workplan: null,
    };
  },
  apollo: {
    // Reads the plan the Workplan widget fetches and keeps fresh, so its variables have to
    // match the widget's, or this reads nothing.
    workplan: {
      query: workItemAgentPlanQuery,
      fetchPolicy: 'cache-only',
      variables() {
        return {
          id: this.workItemId,
          useWorkItemFeatures: Boolean(this.glFeatures?.workItemFeaturesField),
          includeReadinessScore: Boolean(this.glFeatures?.workplanScore),
        };
      },
      update(data) {
        return findWorkplanWidget(data?.workItem) || null;
      },
    },
  },
  computed: {
    openQuestionsCount() {
      return this.workplan?.openQuestionsCount ?? 0;
    },
    showQuestions() {
      return (
        this.workplan?.generationStatus === GENERATION_STATUS_NEEDS_INPUT &&
        this.openQuestionsCount > 0
      );
    },
    awaitingInputLabel() {
      return getAwaitingInputLabel(this.openQuestionsCount);
    },
  },
};
</script>

<template>
  <div
    v-if="showQuestions"
    class="gl-flex gl-shrink-0 gl-items-center gl-gap-2"
    data-testid="sticky-header-workplan-questions"
  >
    <gl-icon name="status" :size="14" variant="warning" />
    <span
      aria-hidden="true"
      class="gl-text-subtle"
      data-testid="sticky-header-open-questions-count"
    >
      {{ openQuestionsCount }}
    </span>
    <span class="gl-sr-only">{{ awaitingInputLabel }}</span>
    <workplan-question-navigator :questions="workplan.questions.nodes" />
  </div>
</template>
