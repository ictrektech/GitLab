<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { sprintf, s__ } from '~/locale';
import { InternalEvents } from '~/tracking';
import ImplementationWidgetSegment from 'ee/vue_shared/components/work_items/implementation_widget_segment.vue';
import ReadinessBar from './readiness_bar.vue';
import ReadinessDrawer from './readiness_drawer.vue';
import {
  PLAN_READINESS_LEVELS,
  READINESS_SCORE_MEDIUM_THRESHOLD,
  READINESS_SCORE_HIGH_THRESHOLD,
} from './constants';

export default {
  name: 'WorkItemReadiness',
  components: {
    ImplementationWidgetSegment,
    ReadinessBar,
    GlButton,
    ReadinessDrawer,
  },
  directives: { GlTooltip: GlTooltipDirective },
  mixins: [InternalEvents.mixin()],
  props: {
    workItemId: {
      type: String,
      required: true,
    },
    score: {
      type: Number,
      required: true,
    },
    isDrawerOpen: {
      type: Boolean,
      required: true,
    },
    feedbackHtml: {
      type: String,
      required: false,
      default: null,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    hasError: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['toggle', 'close', 'retry'],
  data() {
    return { hasTrackedScoreView: false };
  },
  computed: {
    readinessLevel() {
      if (this.score < READINESS_SCORE_MEDIUM_THRESHOLD) {
        return PLAN_READINESS_LEVELS.LOW;
      }
      if (this.score < READINESS_SCORE_HIGH_THRESHOLD) {
        return PLAN_READINESS_LEVELS.MEDIUM;
      }
      return PLAN_READINESS_LEVELS.HIGH;
    },
    readinessLevelText() {
      return this.$options.readinessLevelText[this.readinessLevel.value];
    },
    ariaLabel() {
      return sprintf(s__('AgentPlan|Readiness: %{level}'), {
        level: this.readinessLevelText,
      });
    },
  },
  methods: {
    trackScoreViewed() {
      if (this.hasTrackedScoreView) {
        return;
      }

      this.hasTrackedScoreView = true;
      this.trackEvent('view_work_item_agent_plan_readiness_score', {
        value: this.score,
        work_item_id: getIdFromGraphQLId(this.workItemId),
      });
    },
    closeDrawer() {
      this.$emit('close');
      this.$refs.toggle.$el.focus();
    },
  },
  readinessLevelText: {
    [PLAN_READINESS_LEVELS.LOW.value]: s__('AgentPlan|Low'),
    [PLAN_READINESS_LEVELS.MEDIUM.value]: s__('AgentPlan|Medium'),
    [PLAN_READINESS_LEVELS.HIGH.value]: s__('AgentPlan|High'),
  },
};
</script>
<template>
  <implementation-widget-segment :label="s__('AgentPlan|Readiness')">
    <div class="gl-flex gl-items-center gl-gap-3">
      <div class="gl-flex gl-items-center gl-gap-3" role="img" :aria-label="ariaLabel">
        <span>{{ readinessLevelText }}</span>
        <readiness-bar :readiness-level="readinessLevel" :score="score" />
      </div>
      <gl-button
        ref="toggle"
        v-gl-tooltip
        category="tertiary"
        size="small"
        icon="information-o"
        :title="s__('AgentPlan|Readiness details')"
        :aria-label="s__('AgentPlan|Readiness details')"
        :aria-expanded="String(isDrawerOpen)"
        data-testid="readiness-details-button"
        @click="$emit('toggle')"
      />
    </div>
    <readiness-drawer
      :is-open="isDrawerOpen"
      :feedback-html="feedbackHtml"
      :is-loading="isLoading"
      :has-error="hasError"
      @retry="$emit('retry')"
      @close="closeDrawer"
      @opened="trackScoreViewed"
    />
  </implementation-widget-segment>
</template>
