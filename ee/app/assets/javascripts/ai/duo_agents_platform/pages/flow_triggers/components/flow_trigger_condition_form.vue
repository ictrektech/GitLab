<script>
import { GlButton, GlCollapsibleListbox, GlFormGroup, GlFormTextarea, GlSprintf } from '@gitlab/ui';
import { cloneDeep, uniqueId } from 'lodash-es';
import { __, s__, sprintf } from '~/locale';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import {
  FLOW_TRIGGER_GOAL_MAX_LENGTH,
  FLOW_TRIGGER_MODE_SCHEDULE,
} from 'ee/ai/duo_agents_platform/constants';
import {
  eventConfigurationInvalidFeedback,
  getEventConfiguration,
  isEventConfigurationValid,
} from './event_configurations/configurations';

export default {
  name: 'FlowTriggerConditionForm',
  components: {
    GlButton,
    GlCollapsibleListbox,
    GlFormGroup,
    GlFormTextarea,
    GlSprintf,
    HelpPageLink,
  },
  props: {
    // Whether this condition runs on a schedule or on an event, which decides whether the
    // event picker is shown. Distinct from `typeValue`, the specific event type.
    mode: {
      type: String,
      required: true,
    },
    typeValue: {
      type: String,
      required: false,
      default: null,
    },
    filter: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    // Event types still selectable here: every enabled type minus the ones already added,
    // plus the one being edited. A type maps to a single filter scope, so it can appear once.
    typeOptions: {
      type: Array,
      required: true,
    },
    isNew: {
      type: Boolean,
      required: false,
      default: false,
    },
    serviceAccountRole: {
      type: String,
      required: false,
      default: null,
    },
    goal: {
      type: String,
      required: false,
      default: '',
    },
    goalSupported: {
      type: Boolean,
      required: false,
      default: false,
    },
    goalHelpVisible: {
      type: Boolean,
      required: false,
      default: false,
    },
    compact: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['cancel', 'save'],
  data() {
    return {
      draftType: this.typeValue,
      draftFilter: cloneDeep(this.filter),
      draftGoal: this.goal,
      goalId: uniqueId('condition-goal-'),
      showErrors: false,
      headingId: uniqueId('condition-form-heading-'),
    };
  },
  computed: {
    isSchedule() {
      return this.mode === FLOW_TRIGGER_MODE_SCHEDULE;
    },
    heading() {
      if (this.isSchedule) {
        return this.isNew
          ? s__('DuoAgentsPlatform|New schedule')
          : s__('DuoAgentsPlatform|Edit schedule');
      }

      return this.isNew ? s__('DuoAgentsPlatform|New event') : s__('DuoAgentsPlatform|Edit event');
    },
    submitText() {
      if (!this.isNew) {
        return __('Save');
      }

      return this.isSchedule
        ? s__('DuoAgentsPlatform|Add schedule')
        : s__('DuoAgentsPlatform|Add event');
    },
    selectedType() {
      return this.typeOptions.find((option) => option.value === this.draftType);
    },
    typeToggleText() {
      return this.selectedType?.text ?? s__('DuoAgentsPlatform|Select an event');
    },
    configuration() {
      return this.draftType ? getEventConfiguration(this.draftType) : null;
    },
    // Only the schedule config surfaces the service account role, since scheduled runs
    // execute solely as the service account with no triggering user.
    configurationProps() {
      const props = { ...this.configuration?.props };
      if (this.isSchedule) {
        props.serviceAccountRole = this.serviceAccountRole;
        props.compact = this.compact;
      }
      return props;
    },
    isMissingType() {
      return !this.isSchedule && !this.draftType;
    },
    // An incomplete configuration is reported by the field that owns it, so the message is
    // tied to that control and marks it invalid. Only "no event picked yet" has no field of
    // its own to speak for it.
    configurationInvalidFeedback() {
      return this.showErrors && this.draftType
        ? eventConfigurationInvalidFeedback(this.draftType, this.draftFilter)
        : null;
    },
    missingTypeFeedback() {
      return this.showErrors && this.isMissingType
        ? s__('DuoAgentsPlatform|Select an event.')
        : null;
    },
    isGoalTooLong() {
      return this.goalSupported && this.draftGoal.trim().length > FLOW_TRIGGER_GOAL_MAX_LENGTH;
    },
    // No maxlength on the control: that truncates a long paste without telling anyone.
    goalInvalidFeedback() {
      return this.showErrors && this.isGoalTooLong
        ? sprintf(s__('DuoAgentsPlatform|Instructions cannot exceed %{maxLength} characters.'), {
            maxLength: FLOW_TRIGGER_GOAL_MAX_LENGTH,
          })
        : null;
    },
  },
  methods: {
    onSelectType(typeValue) {
      // The configuration belongs to the event type. The goal is free text, so it stays.
      this.draftType = typeValue;
      this.draftFilter = {};
    },
    onUpdateFilter(nextFilter) {
      this.draftFilter = nextFilter;
    },
    onSubmit() {
      this.showErrors = true;

      if (
        this.isMissingType ||
        this.isGoalTooLong ||
        !isEventConfigurationValid(this.draftType, this.draftFilter)
      ) {
        return;
      }

      this.$emit('save', {
        typeValue: this.draftType,
        filter: this.draftFilter,
        // draftGoal can still hold text typed before the field was hidden.
        goal: this.goalSupported ? this.draftGoal.trim() : '',
      });
    },
  },
};
</script>

<template>
  <!-- The heading is hidden rather than dropped: the panel above, the field labels and the
       submit button already say which kind of condition this is, but assistive technology
       still gets a real heading to navigate to, and it names the group. -->
  <!-- tabindex="-1" so the panel can take focus when it opens. It names itself through
       aria-labelledby, so landing here announces which condition is being worked on. -->
  <div
    role="group"
    :aria-labelledby="headingId"
    tabindex="-1"
    class="gl-flex gl-flex-col gl-gap-4"
    data-testid="condition-form"
  >
    <h3 :id="headingId" class="gl-sr-only">{{ heading }}</h3>

    <gl-form-group
      v-if="!isSchedule"
      :label="s__('DuoAgentsPlatform|Event')"
      :label-sr-only="compact"
      class="!gl-mb-0"
    >
      <gl-collapsible-listbox
        :items="typeOptions"
        :selected="draftType"
        :toggle-text="typeToggleText"
        fluid-width
        block
        data-testid="event-type-listbox"
        @select="onSelectType"
      >
        <template #list-item="{ item }">
          <div class="gl-flex gl-flex-col">
            <strong>{{ item.text }}</strong>
            <span v-if="item.description" class="gl-text-sm gl-text-subtle">{{
              item.description
            }}</span>
          </div>
        </template>
      </gl-collapsible-listbox>
    </gl-form-group>

    <component
      :is="configuration.component"
      v-if="configuration"
      v-bind="configurationProps"
      :value="draftFilter"
      :invalid-feedback="configurationInvalidFeedback"
      @input="onUpdateFilter"
    />

    <gl-form-group
      v-if="goalSupported"
      :label="s__('DuoAgentsPlatform|Instructions')"
      :label-for="goalId"
      :label-description="
        s__(
          'DuoAgentsPlatform|Optional. Tell the agent or flow what to do when this condition is met.',
        )
      "
      :invalid-feedback="goalInvalidFeedback"
      :state="!goalInvalidFeedback"
      class="!gl-mb-0"
      data-testid="condition-goal-group"
    >
      <gl-form-textarea
        :id="goalId"
        v-model="draftGoal"
        :rows="3"
        :placeholder="s__('DuoAgentsPlatform|Summarize the failing jobs.')"
        data-testid="condition-goal"
      />
      <template v-if="goalHelpVisible" #description>
        <gl-sprintf
          :message="
            s__(
              `DuoAgentsPlatform|This flow might not use these instructions, depending on how it's configured. %{linkStart}How flows use instructions%{linkEnd}`,
            )
          "
        >
          <template #link="{ content }">
            <help-page-link
              href="user/duo_agent_platform/flows/custom_flows_schema"
              anchor="goal-values-by-trigger-type"
              >{{ content }}</help-page-link
            >
          </template>
        </gl-sprintf>
      </template>
    </gl-form-group>

    <p
      v-if="missingTypeFeedback"
      role="alert"
      class="gl-mb-0 gl-text-sm gl-text-danger"
      data-testid="condition-error"
    >
      {{ missingTypeFeedback }}
    </p>

    <div class="gl-flex gl-gap-3">
      <gl-button variant="confirm" size="small" data-testid="save-condition" @click="onSubmit">
        {{ submitText }}
      </gl-button>
      <gl-button size="small" data-testid="cancel-condition" @click="$emit('cancel')">
        {{ __('Cancel') }}
      </gl-button>
    </div>
  </div>
</template>
