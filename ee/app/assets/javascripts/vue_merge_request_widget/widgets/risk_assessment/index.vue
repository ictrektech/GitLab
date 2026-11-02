<script>
import { GlSprintf } from '@gitlab/ui';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import MrWidget from '~/vue_merge_request_widget/components/widget/widget.vue';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import SeverityMeter from 'ee/vue_shared/components/severity_meter/severity_meter.vue';
import RiskConfidenceNotice from './components/risk_confidence_notice.vue';
import RiskFooter from './components/risk_footer.vue';
import RiskRationale from './components/risk_rationale.vue';
import RiskSignalBreakdown from './components/risk_signal_breakdown.vue';
import { STATUS_ICONS } from './constants';
import { getRiskAssessmentState } from './utils';

export default {
  name: 'WidgetRiskAssessment',
  components: {
    GlSprintf,
    MrWidget,
    RiskConfidenceNotice,
    RiskFooter,
    RiskRationale,
    RiskSignalBreakdown,
    SeverityMeter,
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
        return !this.duoWorkflowId;
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
    };
  },
  computed: {
    state() {
      return getRiskAssessmentState(this.riskAssessment, {
        isLoading: this.isLoading,
        duoChatAvailable: this.duoChatAvailable,
      });
    },
    // Not rendered (the meter overrides the status-icon slot); passed to mr-widget
    // only so its expand telemetry reports the risk lifecycle rather than neutral.
    statusIconName() {
      return STATUS_ICONS[this.state.status] ?? EXTENSION_ICONS.neutral;
    },
    isAssessed() {
      return this.state.isAssessed;
    },
    isRefreshing() {
      return this.state.isRefreshing;
    },
    showsStaleWarning() {
      return this.state.showsStaleWarning;
    },
    showsSessionLink() {
      return this.state.showsSessionLink;
    },
    showsFooter() {
      return this.state.showsFooter;
    },
    hasDetails() {
      return this.state.hasDetails;
    },
    tier() {
      return this.state.tier;
    },
    meterLabel() {
      return this.state.meterLabel;
    },
    isLowConfidence() {
      return this.state.isLowConfidence;
    },
    summaryTitle() {
      return this.state.summaryTitle;
    },
    contributions() {
      return this.state.contributions;
    },
    missingSignalLabels() {
      return this.state.missingSignalLabels;
    },
    rationale() {
      return this.state.rationale;
    },
    duoWorkflowId() {
      return this.state.duoWorkflowId;
    },
  },
};
</script>

<template>
  <div class="mr-section-container">
    <mr-widget
      :error-text="s__('RiskAssessment|Failed to load the risk assessment')"
      :status-icon-name="statusIconName"
      :has-error="hasError"
      :is-collapsible="hasDetails || showsStaleWarning"
      widget-name="WidgetRiskAssessment"
      data-testid="mr-risk-assessment-widget"
      class="mr-widget-section"
    >
      <template #status-icon>
        <severity-meter
          :severity="isAssessed ? tier : null"
          :label="meterLabel"
          :loading="isLoading"
          class="gl-mr-3 gl-self-center"
        />
      </template>

      <template #summary>
        <div class="gl-flex gl-h-full gl-flex-wrap gl-items-center gl-gap-3">
          <span data-testid="risk-summary">
            <gl-sprintf :message="summaryTitle">
              <template #bold="{ content }">
                <strong>{{ content }}</strong>
              </template>
            </gl-sprintf>
          </span>

          <span v-if="isRefreshing" class="gl-text-subtle" data-testid="risk-updating">
            {{ s__('RiskAssessment|Updating…') }}
          </span>
        </div>
      </template>

      <template #content>
        <div v-if="hasDetails || showsStaleWarning" class="gl-px-4 gl-py-3">
          <template v-if="hasDetails">
            <risk-rationale v-if="rationale" :rationale="rationale" />
            <risk-signal-breakdown v-if="contributions.length" :contributions="contributions" />
            <risk-confidence-notice v-if="isLowConfidence" :missing-labels="missingSignalLabels" />
          </template>

          <risk-footer
            v-if="showsFooter"
            :session-id="showsSessionLink ? duoWorkflowId : null"
            :is-stale="showsStaleWarning"
            :can-refresh="canRefresh"
            :is-submitting="isSubmitting"
            @refresh="$emit('refresh')"
          />
        </div>
      </template>
    </mr-widget>
  </div>
</template>
