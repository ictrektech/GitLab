<script>
import WidgetRiskAssessmentApp from 'ee/vue_merge_request_widget/widgets/risk_assessment/app.vue';
import RiskPanelCard from './risk_panel_card.vue';

// The merge widget's risk assessment, data and refresh flow included, so the overview keeps up
// with the experience outside it. It also keeps the field's errors out of the rest of the overview.
export default {
  name: 'RiskPanel',
  components: {
    RiskPanelCard,
    WidgetRiskAssessmentApp,
  },
  inject: ['projectPath', 'iid'],
  computed: {
    // The shape the widget reads from its store.
    widgetMergeRequest() {
      return { iid: this.iid, targetProjectFullPath: this.projectPath };
    },
  },
};
</script>

<template>
  <widget-risk-assessment-app :merge-request="widgetMergeRequest">
    <template #default="{ refresh, ...cardProps }">
      <risk-panel-card v-bind="cardProps" @refresh="refresh" />
    </template>
  </widget-risk-assessment-app>
</template>
