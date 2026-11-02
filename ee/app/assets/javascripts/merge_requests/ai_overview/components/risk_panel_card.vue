<script>
import { GlAnimatedChevronLgDownUpIcon, GlButton, GlSprintf, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { __ } from '~/locale';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import SeverityMeter from 'ee/vue_shared/components/severity_meter/severity_meter.vue';
import RiskConfidenceNotice from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_confidence_notice.vue';
import RiskFooter from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_footer.vue';
import RiskRationale from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_rationale.vue';
import RiskSignalBreakdown from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_signal_breakdown.vue';
import { getRiskAssessmentState } from 'ee/vue_merge_request_widget/widgets/risk_assessment/utils';

// The overview's take on the merge widget's risk assessment: the same state, details and
// footer as the widget, in a collapsible row atop the description card instead of a widget row.
export default {
  name: 'RiskPanelCard',
  components: {
    GlAnimatedChevronLgDownUpIcon,
    GlButton,
    GlSprintf,
    RiskConfidenceNotice,
    RiskFooter,
    RiskRationale,
    RiskSignalBreakdown,
    SeverityMeter,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    riskAssessment: {
      type: Object,
      required: false,
      default: null,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    hasError: {
      type: Boolean,
      required: false,
      default: false,
    },
    canRefresh: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSubmitting: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['refresh'],
  apollo: {
    duoChatAvailable: {
      query: duoChatAvailableQuery,
      skip() {
        return !this.state.duoWorkflowId;
      },
      update(data) {
        return data?.currentUser?.duoChatAvailable ?? false;
      },
      error() {
        this.duoChatAvailable = false;
      },
    },
  },
  data() {
    return {
      duoChatAvailable: false,
      isExpanded: false,
      detailsId: uniqueId('ai-overview-risk-details-'),
    };
  },
  computed: {
    state() {
      return getRiskAssessmentState(this.riskAssessment, {
        isLoading: this.isLoading,
        duoChatAvailable: this.duoChatAvailable,
      });
    },
    // The same condition the widget collapses on.
    isCollapsible() {
      return !this.hasError && (this.state.hasDetails || this.state.showsStaleWarning);
    },
    toggleLabel() {
      return this.isExpanded ? __('Hide details') : __('Show details');
    },
  },
};
</script>

<template>
  <!-- The first row of the description card, above its header. -->
  <section class="gl-border-b-1 gl-border-b-default gl-border-b-solid" data-testid="risk-panel">
    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3 gl-px-4 gl-py-3">
      <severity-meter
        :severity="state.meterSeverity"
        :label="state.meterLabel"
        :loading="isLoading"
      />
      <h3 class="gl-m-0 gl-text-base gl-font-normal" data-testid="risk-title">
        <gl-sprintf :message="state.summaryTitle">
          <template #bold="{ content }">
            <strong>{{ content }}</strong>
          </template>
        </gl-sprintf>
      </h3>
      <span v-if="state.isRefreshing" class="gl-text-subtle" data-testid="risk-updating">
        {{ s__('RiskAssessment|Updating…') }}
      </span>
      <gl-button
        v-if="isCollapsible"
        v-gl-tooltip
        :title="toggleLabel"
        :aria-label="toggleLabel"
        :aria-expanded="String(isExpanded)"
        :aria-controls="detailsId"
        category="tertiary"
        size="small"
        class="btn-icon gl-ml-auto"
        data-testid="risk-details-toggle"
        @click="isExpanded = !isExpanded"
      >
        <gl-animated-chevron-lg-down-up-icon :is-on="isExpanded" variant="default" />
      </gl-button>
    </div>
    <p
      v-if="hasError"
      class="gl-m-0 gl-border-t-1 gl-border-t-default gl-px-4 gl-py-3 gl-text-danger gl-border-t-solid"
    >
      {{ s__('RiskAssessment|Failed to load the risk assessment') }}
    </p>
    <div
      v-else-if="isCollapsible"
      v-show="isExpanded"
      :id="detailsId"
      class="gl-border-t-1 gl-border-t-default gl-px-4 gl-py-3 gl-border-t-solid"
      data-testid="risk-details"
    >
      <template v-if="state.hasDetails">
        <risk-rationale v-if="state.rationale" :rationale="state.rationale" />
        <risk-signal-breakdown
          v-if="state.contributions.length"
          :contributions="state.contributions"
        />
        <risk-confidence-notice
          v-if="state.isLowConfidence"
          :missing-labels="state.missingSignalLabels"
        />
      </template>

      <risk-footer
        v-if="state.showsFooter"
        :session-id="state.showsSessionLink ? state.duoWorkflowId : null"
        :is-stale="state.showsStaleWarning"
        :can-refresh="canRefresh"
        :is-submitting="isSubmitting"
        @refresh="$emit('refresh')"
      />
    </div>
  </section>
</template>
