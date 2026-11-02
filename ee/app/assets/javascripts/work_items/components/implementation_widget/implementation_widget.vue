<script>
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { STATE_CLOSED } from '~/work_items/constants';
import { findWorkplanWidget } from 'ee/work_items/utils';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import workItemAgentPlanReadinessFeedbackQuery from 'ee/work_items/graphql/work_item_agent_plan_readiness_feedback.query.graphql';
import workItemAgentPlanUpdatedSubscription from 'ee/work_items/graphql/work_item_agent_plan.subscription.graphql';
import WorkItemReadiness from './work_item_readiness.vue';
import WorkItemWorkplan from './work_item_workplan.vue';
import { ACTIVE_RUN_POLL_INTERVAL_MS, GENERATION_STATUSES_ACTIVE } from './constants';

export default {
  name: 'ImplementationWidget',
  components: {
    WorkItemReadiness,
    WorkItemWorkplan,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    workItem: {
      type: Object,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
    isInDrawer: {
      type: Boolean,
      required: false,
      default: false,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['request-panel'],
  data() {
    return {
      workplan: null,
      isRunActive: false,
      isReadinessDrawerOpen: false,
      readinessScoreFeedbackHtml: null,
      hasFeedbackError: false,
      isFeedbackStale: false,
    };
  },
  apollo: {
    workplan: {
      query: workItemAgentPlanQuery,
      variables() {
        return this.workplanVariables;
      },
      skip() {
        return !this.workItemId;
      },
      update(data) {
        return findWorkplanWidget(data?.workItem) || null;
      },
      error(error) {
        createAlert({
          message: s__(
            'WorkItem|Something went wrong when fetching the workplan. Please refresh this page.',
          ),
          captureError: true,
          error,
        });
      },
      subscribeToMore: {
        document: workItemAgentPlanUpdatedSubscription,
        variables() {
          return this.workplanVariables;
        },
        skip() {
          return !this.workItemId;
        },
      },
      pollInterval() {
        return this.shouldPollPlan ? ACTIVE_RUN_POLL_INTERVAL_MS : 0;
      },
      // A refetch overwrites by default, which drops every other widget the work item has
      // cached and refetches the whole work item. Merging keeps them, as polling already does.
      refetchWritePolicy: 'merge',
    },
    // Fetched by its own query so opening the drawer never changes the variables of the
    // polled `workplan` query above. vue-apollo rebuilds a query whose variables change,
    // and the rebuilt query loses its `pollInterval`.
    readinessScoreFeedbackHtml: {
      query: workItemAgentPlanReadinessFeedbackQuery,
      variables() {
        return {
          id: this.workItemId,
          useWorkItemFeatures: this.useWorkItemFeatures,
        };
      },
      skip() {
        return !this.workItemId || !this.useScore || !this.isReadinessDrawerOpen;
      },
      update(data) {
        return findWorkplanWidget(data?.workItem)?.readinessScoreFeedbackHtml ?? null;
      },
      watchLoading(isLoading) {
        if (isLoading) {
          this.hasFeedbackError = false;
          this.isFeedbackStale = false;
        }
      },
      result({ loading, error, errors }) {
        if (!loading && !error && !errors?.length) {
          this.hasFeedbackError = false;
          this.refreshStaleFeedback();
        }
      },
      error(error) {
        this.hasFeedbackError = true;
        Sentry.captureException(error);
      },
      refetchWritePolicy: 'merge',
    },
  },
  computed: {
    workItemId() {
      return this.workItem.id;
    },
    isWorkItemClosed() {
      return this.workItem.state === STATE_CLOSED;
    },
    useWorkItemFeatures() {
      return Boolean(this.glFeatures?.workItemFeaturesField);
    },
    workplanVariables() {
      return {
        id: this.workItemId,
        useWorkItemFeatures: this.useWorkItemFeatures,
        // Skip resolving readinessScore while workplan_score is disabled.
        includeReadinessScore: this.useScore,
      };
    },
    isGenerationActive() {
      return GENERATION_STATUSES_ACTIVE.includes(this.workplan?.generationStatus);
    },
    shouldPollPlan() {
      return this.isRunActive || this.isGenerationActive;
    },
    isLoadingPlan() {
      return this.$apollo.queries.workplan.loading && !this.workplan;
    },
    isLoadingFeedback() {
      return this.isReadinessDrawerOpen && this.$apollo.queries.readinessScoreFeedbackHtml.loading;
    },
    useScore() {
      return Boolean(this.glFeatures?.workplanScore);
    },
    readinessScore() {
      return this.workplan?.readinessScore ?? null;
    },
    // The score is only produced after a workplan is generated, so there is nothing to
    // show until then. `useScore` stays flag-only because it also gates the query field.
    showScore() {
      return this.useScore && Number.isFinite(this.readinessScore);
    },
    feedbackSource() {
      return { score: this.readinessScore, isGenerationActive: this.isGenerationActive };
    },
  },
  watch: {
    feedbackSource(current, previous) {
      const hasScoreChanged = previous.score !== null && current.score !== previous.score;
      const hasRunFinished = previous.isGenerationActive && !current.isGenerationActive;

      if (hasScoreChanged || hasRunFinished) {
        this.markFeedbackStale();
      }
    },
  },
  methods: {
    refetchWorkplan() {
      this.$apollo.queries.workplan.refetch().catch(() => {});
    },
    refetchFeedback() {
      this.hasFeedbackError = false;
      this.isFeedbackStale = false;
      this.$apollo.queries.readinessScoreFeedbackHtml.refetch().catch(() => {});
    },
    markFeedbackStale() {
      this.isFeedbackStale = true;
      if (!this.$apollo.queries.readinessScoreFeedbackHtml.skip) {
        this.refreshStaleFeedback();
      }
    },
    refreshStaleFeedback() {
      if (this.isFeedbackStale && !this.$apollo.queries.readinessScoreFeedbackHtml.loading) {
        this.refetchFeedback();
      }
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-flex-col gl-gap-6 gl-py-6 md:gl-flex-row md:gl-flex-wrap md:gl-items-center md:gl-gap-8"
  >
    <work-item-workplan
      class="gl-shrink-0"
      :work-item="workItem"
      :workplan="workplan"
      :is-loading="isLoadingPlan"
      :can-update="canUpdate"
      :work-item-web-url="workItemWebUrl"
      :is-in-drawer="isInDrawer"
      :is-panel-open="isPanelOpen"
      :is-work-item-closed="isWorkItemClosed"
      @request-panel="$emit('request-panel', $event)"
      @refetch-plan="refetchWorkplan"
      @run-active="isRunActive = $event"
    />
    <work-item-readiness
      v-if="showScore && !isLoadingPlan"
      :work-item-id="workItemId"
      :score="readinessScore"
      :is-drawer-open="isReadinessDrawerOpen"
      :feedback-html="readinessScoreFeedbackHtml"
      :is-loading="isLoadingFeedback"
      :has-error="hasFeedbackError"
      @retry="refetchFeedback"
      @toggle="isReadinessDrawerOpen = !isReadinessDrawerOpen"
      @close="isReadinessDrawerOpen = false"
    />
  </div>
</template>
