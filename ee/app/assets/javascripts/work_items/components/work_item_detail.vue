<script>
import WorkItemDetail from '~/work_items/components/work_item_detail.vue';
import ImplementationWidget from 'ee/work_items/components/implementation_widget/implementation_widget.vue';
import WorkplanStickyHeaderQuestions from 'ee/work_items/components/implementation_widget/workplan_sticky_header_questions.vue';
import WorkItemDecisionLog from 'ee/work_items/components/decision_log/work_item_decision_log.vue';
import WorkItemAgentSessions from 'ee/work_items/components/agent_sessions/index.vue';
import WorkItemPlanCta from 'ee/work_items/components/work_item_plan_cta.vue';
import { WORKPLAN_PANEL, DECISION_LOG_PANEL } from '~/work_items/constants';
import { findDecisionLogWidget, isWorkplanEnabled } from 'ee/work_items/utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';

export default {
  name: 'WorkItemDetailEE',
  WORKPLAN_PANEL,
  DECISION_LOG_PANEL,
  components: {
    WorkItemDetail,
    ImplementationWidget,
    WorkItemAgentSessions,
    WorkItemDecisionLog,
    WorkItemPlanCta,
    WorkplanStickyHeaderQuestions,
  },
  mixins: [glFeatureFlagsMixin(), glListenersMixin],
  inheritAttrs: false,
  methods: {
    isWorkplanAvailable(workItem) {
      return isWorkplanEnabled(workItem);
    },
    showDecisionLog(workItem) {
      return Boolean(this.glFeatures?.decisionLog) && Boolean(findDecisionLogWidget(workItem));
    },
    // Nothing pushes the open questions count, so answering a question refetches it here,
    // where both the discussion and the Workplan widget are rendered.
    refetchWorkplan() {
      this.$refs.implementationWidget?.refetchWorkplan();
    },
    // Flows can only run in a project, so Plan isn't offered on group-level work items.
    showPlanCta({ workItem, editMode, canUpdate, agentPlanWidget }) {
      return (
        Boolean(workItem?.project) &&
        !editMode &&
        canUpdate &&
        Boolean(agentPlanWidget) &&
        !agentPlanWidget.aiPlanningEnabled
      );
    },
  },
};
</script>

<template>
  <work-item-detail v-bind="$attrs" v-on="glListeners()" @duo-question-answered="refetchWorkplan">
    <template #widgets-top="{ workItem, isDetailPanel, activePanel, editMode, requestPanel }">
      <!-- eslint-disable local-rules/vue-no-web-url -- Internal drawer-redirect URL; webUrl is what the work-item fragment already exposes. -->
      <implementation-widget
        v-if="workItem && isWorkplanAvailable(workItem) && !editMode"
        ref="implementationWidget"
        :work-item="workItem"
        :work-item-web-url="workItem.webUrl"
        :is-in-drawer="isDetailPanel"
        :is-panel-open="activePanel === $options.WORKPLAN_PANEL"
        :can-update="workItem.userPermissions?.updateWorkItem"
        class="gl-mb-5"
        @request-panel="requestPanel"
      />
      <!-- eslint-enable local-rules/vue-no-web-url -->
    </template>
    <template #sticky-header-append="{ workItem }">
      <workplan-sticky-header-questions
        v-if="workItem && isWorkplanAvailable(workItem)"
        :work-item-id="workItem.id"
      />
    </template>
    <template #header-actions="{ workItem, isDetailPanel, activePanel, requestPanel }">
      <!-- eslint-disable local-rules/vue-no-web-url -- Internal drawer-redirect URL; webUrl is what the work-item fragment already exposes. -->
      <work-item-decision-log
        v-if="showDecisionLog(workItem)"
        :work-item="workItem"
        :work-item-web-url="workItem.webUrl"
        :has-panel-portal="!isDetailPanel"
        :is-panel-open="activePanel === $options.DECISION_LOG_PANEL"
        @request-panel="requestPanel"
      />
      <!-- eslint-enable local-rules/vue-no-web-url -->
    </template>
    <template
      #plan-cta="{ workItem, canUpdate, editMode, agentPlanWidget, isDetailPanel, onError }"
    >
      <work-item-plan-cta
        v-if="showPlanCta({ workItem, editMode, canUpdate, agentPlanWidget })"
        :work-item="workItem"
        :is-in-drawer="isDetailPanel"
        @error="onError($event)"
      />
    </template>
    <template #widgets="{ workItem }">
      <work-item-agent-sessions v-if="workItem" :work-item-id="workItem.id" />
    </template>
  </work-item-detail>
</template>
