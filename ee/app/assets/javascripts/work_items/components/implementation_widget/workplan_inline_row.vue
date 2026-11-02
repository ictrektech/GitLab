<script>
import {
  GlButton,
  GlButtonGroup,
  GlDisclosureDropdown,
  GlIcon,
  GlLink,
  GlSprintf,
} from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import ImplementationWidgetSegment from 'ee/vue_shared/components/work_items/implementation_widget_segment.vue';
import {
  WORKPLAN_GOAL_PREFIX,
  WORKPLAN_SOURCE,
  GENERATE_MR_BUTTON_OPTIONS,
  IMPLEMENTATION_UNAVAILABLE_MESSAGE,
  IMPLEMENTATION_HELP_PATH,
  GENERATION_STATUS_GENERATING,
  GENERATION_STATUS_NEEDS_INPUT,
  GENERATION_STATUS_CANCELED,
  GENERATION_STATUS_FAILED,
  GENERATION_STATUSES,
  WORKPLAN_ACTION,
} from './constants';
import { getAwaitingInputLabel, isValidReadinessScore, trackWorkplanImplement } from './utils';
import WorkplanQuestionNavigator from './workplan_question_navigator.vue';
import WorkplanStatusBar from './workplan_status_bar.vue';
import WorkplanAvailabilityPopover from './workplan_availability_popover.vue';

export default {
  name: 'WorkplanInlineRow',
  components: {
    ImplementationWidgetSegment,
    GlButton,
    GlButtonGroup,
    GlIcon,
    GlLink,
    GlSprintf,
    HelpPopover,
    GlDisclosureDropdown,
    DuoWorkItemToMrAction,
    WorkplanQuestionNavigator,
    WorkplanStatusBar,
    WorkplanAvailabilityPopover,
  },
  props: {
    generationDisabledReason: {
      type: String,
      required: false,
      default: '',
    },
    hasContent: {
      type: Boolean,
      required: false,
      default: false,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    isPanelOpen: {
      type: Boolean,
      required: false,
      default: false,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    workItemIid: {
      type: String,
      required: false,
      default: null,
    },
    workItemType: {
      type: String,
      required: false,
      default: null,
    },
    workItemWebUrl: {
      type: String,
      required: false,
      default: '',
    },
    readinessScore: {
      type: Number,
      required: false,
      default: null,

      validator: isValidReadinessScore,
    },
    projectPath: {
      type: String,
      required: false,
      default: '',
    },
    generation: {
      type: Object,
      required: false,
      default: () => ({}),
      validator: ({ status }) => status == null || GENERATION_STATUSES.includes(status),
    },
    isWorkItemClosed: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['open', 'create-manually', 'generate', 'retry', 'continue'],
  computed: {
    helpPopoverOptions() {
      return {
        title: s__('AgentPlan|What is a workplan?'),
      };
    },
    isAwaitingInput() {
      return this.generation.status === GENERATION_STATUS_NEEDS_INPUT;
    },
    hasFailedGeneration() {
      return this.generation.status === GENERATION_STATUS_FAILED;
    },
    isFlowActive() {
      return this.generation.isRunning;
    },
    showAwaitingInputIcon() {
      return this.isAwaitingInput;
    },
    showQuestionNavigator() {
      return this.isAwaitingInput && this.generation.openQuestionsCount > 0;
    },
    awaitingInputLabel() {
      const { openQuestionsCount, hasQuestions } = this.generation;

      if (!openQuestionsCount) {
        // A count of `0` also covers a run that paused without asking anything, such as on a
        // tool approval, so only claim every question is answered when some were asked.
        return hasQuestions
          ? s__('AgentPlan|All questions resolved')
          : s__('AgentPlan|Awaiting input');
      }

      return getAwaitingInputLabel(openQuestionsCount);
    },
    notStartedStatus() {
      return {
        label: this.canUpdate ? s__('AgentPlan|Not yet created') : s__('AgentPlan|No workplan'),
        variant: 'neutral',
      };
    },
    statusByGenerationStatus() {
      return {
        [GENERATION_STATUS_GENERATING]: {
          // A saved plan means the run is past its review pass, same as a resumed run,
          // so only a run with neither reports that it is still reviewing.
          label:
            this.generation.hasAwaitedInput || this.hasContent
              ? s__('AgentPlan|Generating workplan...')
              : s__('AgentPlan|Reviewing work item...'),
          variant: 'info',
        },
        [GENERATION_STATUS_NEEDS_INPUT]: {
          label: this.awaitingInputLabel,
          variant: 'warning',
        },
        // A user-initiated cancel matches the canceled session styling, but offers the
        // default actions rather than a retry.
        [GENERATION_STATUS_CANCELED]: {
          label: s__('AgentPlan|Generation canceled'),
          variant: 'error',
        },
        [GENERATION_STATUS_FAILED]: {
          label: s__('AgentPlan|Generation failed'),
          variant: 'error',
        },
      };
    },
    status() {
      // An active run wins over content: on a regenerate the previous plan is still
      // saved, so its presence must not mask the run in progress.
      if (this.generation.isStarting) {
        return { label: s__('AgentPlan|Preparing to generate...'), variant: 'info' };
      }
      if (this.isFlowActive) {
        return this.statusByGenerationStatus[this.generation.status];
      }
      if (this.hasContent) {
        return { label: s__('AgentPlan|Ready for review'), variant: 'success' };
      }
      return this.statusByGenerationStatus[this.generation.status] ?? this.notStartedStatus;
    },
    showWorkplanToggle() {
      return this.hasContent && !this.isFlowActive;
    },
    showCreateWorkplanAction() {
      return (
        !this.isLoading &&
        !this.hasContent &&
        this.canUpdate &&
        !this.isFlowActive &&
        !this.hasFailedGeneration
      );
    },
    showRetryAction() {
      return this.hasFailedGeneration && !this.hasContent && this.canUpdate;
    },
    showContinueAction() {
      return this.isAwaitingInput && this.canUpdate;
    },
    primaryAction() {
      if (this.showContinueAction) return WORKPLAN_ACTION.CONTINUE;
      if (this.showWorkplanToggle) return WORKPLAN_ACTION.VIEW;
      if (this.showRetryAction) return WORKPLAN_ACTION.RETRY;
      if (this.showCreateWorkplanAction) return WORKPLAN_ACTION.CREATE;
      return WORKPLAN_ACTION.NONE;
    },
    showAvailabilityPopover() {
      return (
        Boolean(this.generationDisabledReason) &&
        [WORKPLAN_ACTION.CREATE, WORKPLAN_ACTION.CONTINUE, WORKPLAN_ACTION.RETRY].includes(
          this.primaryAction,
        )
      );
    },
    showGenerateMrAction() {
      return this.hasContent && this.canUpdate && !this.isFlowActive && !this.isWorkItemClosed;
    },
  },
  methods: {
    trackImplement() {
      trackWorkplanImplement('inline_row', this.readinessScore);
    },
  },
  createWorkplanDropdownItems: [
    {
      text: s__('AgentPlan|Create manually'),
      extraAttrs: {
        'data-testid': 'create-workplan-dropdown-item',
      },
    },
  ],
  WORKPLAN_GOAL_PREFIX,
  WORKPLAN_SOURCE,
  generateMrButtonOptions: GENERATE_MR_BUTTON_OPTIONS,
  IMPLEMENTATION_UNAVAILABLE_MESSAGE,
  IMPLEMENTATION_HELP_PATH,
  workplanHelpPath: helpPagePath('user/work_items/workplan'),
  WORKPLAN_ACTION,
};
</script>

<template>
  <div
    data-testid="workplan-inline-row"
    class="gl-relative gl-flex gl-w-fit gl-flex-wrap gl-items-stretch gl-justify-between gl-gap-x-6 gl-gap-y-4 gl-rounded-2xl"
  >
    <div class="gl-flex gl-gap-4">
      <workplan-status-bar :variant="status.variant" :aria-label="status.label" />
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-4 gl-gap-y-3">
        <implementation-widget-segment :label="s__('AgentPlan|Workplan')">
          <template #label-append>
            <help-popover
              v-if="!hasContent && !isFlowActive"
              :options="helpPopoverOptions"
              class="gl-inline-flex"
            >
              <gl-sprintf
                :message="
                  s__(
                    'AgentPlan|A workplan breaks a work item into clear, ordered steps that guide implementation. Create one manually, or generate it with GitLab Duo. %{linkStart}Learn more%{linkEnd}.',
                  )
                "
              >
                <template #link="{ content }">
                  <gl-link :href="$options.workplanHelpPath" target="_blank">{{ content }}</gl-link>
                </template>
              </gl-sprintf>
            </help-popover>
          </template>
          <span class="gl-inline-flex gl-items-center gl-gap-2 gl-text-subtle">
            <gl-icon
              v-if="showAwaitingInputIcon"
              name="status"
              :size="14"
              variant="warning"
              data-testid="awaiting-input-icon"
            />
            {{ status.label }}
          </span>
        </implementation-widget-segment>
        <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
          <workplan-question-navigator
            v-if="showQuestionNavigator"
            :questions="generation.questions"
          />
          <gl-button
            v-if="primaryAction === $options.WORKPLAN_ACTION.VIEW"
            :aria-pressed="String(isPanelOpen)"
            category="secondary"
            data-testid="open-workplan-button"
            @click="$emit('open')"
          >
            {{ __('View') }}
          </gl-button>
          <gl-button
            v-else-if="primaryAction === $options.WORKPLAN_ACTION.CONTINUE"
            ref="generationButton"
            :disabled="Boolean(generationDisabledReason)"
            accessible-disabled
            icon="tanuki-ai"
            :loading="generation.actionInFlight"
            data-testid="continue-workplan-button"
            @click="$emit('continue')"
          >
            {{ s__('AgentPlan|Continue') }}
          </gl-button>
          <gl-button
            v-else-if="primaryAction === $options.WORKPLAN_ACTION.RETRY"
            ref="generationButton"
            :disabled="Boolean(generationDisabledReason)"
            accessible-disabled
            icon="tanuki-ai"
            :loading="generation.actionInFlight"
            data-testid="retry-workplan-button"
            @click="$emit('retry')"
          >
            {{ s__('AgentPlan|Try again') }}
          </gl-button>
          <gl-button-group v-else-if="primaryAction === $options.WORKPLAN_ACTION.CREATE">
            <gl-button
              ref="generationButton"
              :disabled="Boolean(generationDisabledReason)"
              accessible-disabled
              icon="tanuki-ai"
              :loading="generation.actionInFlight"
              data-testid="inline-generate-button"
              @click="$emit('generate')"
            >
              {{ s__('AgentPlan|Generate') }}
            </gl-button>
            <gl-disclosure-dropdown
              :items="$options.createWorkplanDropdownItems"
              :toggle-text="s__('AgentPlan|More options')"
              text-sr-only
              placement="bottom-end"
              data-testid="create-workplan-dropdown"
              @action="$emit('create-manually')"
            />
          </gl-button-group>
          <workplan-availability-popover
            v-if="showAvailabilityPopover"
            :target="() => $refs.generationButton?.$el"
            :reason="generationDisabledReason"
          />
          <duo-work-item-to-mr-action
            v-if="showGenerateMrAction"
            :project-path="projectPath"
            :work-item-iid="workItemIid"
            :work-item-type="workItemType"
            :work-item-web-url="workItemWebUrl"
            :additional-goal-context="$options.WORKPLAN_GOAL_PREFIX"
            :source="$options.WORKPLAN_SOURCE"
            :generate-mr-button-options="$options.generateMrButtonOptions"
            :disabled-flow-message="$options.IMPLEMENTATION_UNAVAILABLE_MESSAGE"
            :disabled-flow-help-path="$options.IMPLEMENTATION_HELP_PATH"
            data-testid="generate-mr-with-duo"
            @triggering="trackImplement"
          />
        </div>
      </div>
    </div>
  </div>
</template>
