<script>
import { GlBadge, GlDisclosureDropdown, GlIcon } from '@gitlab/ui';
import { omit } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  FLOW_TRIGGER_MODE_EVENT,
  FLOW_TRIGGER_MODE_SCHEDULE,
  SCHEDULE_FREQUENCY_WEEKLY,
} from 'ee/ai/duo_agents_platform/constants';
import {
  defaultScheduleTimezone,
  flowTriggerModeFor,
  getEnabledFlowTriggerTypes,
  randomizeScheduleDefaults,
  toFlowTriggerTypeOption,
} from 'ee/ai/duo_agents_platform/utils';
import {
  eventConfigurationInvalidFeedback,
  isEventConfigurationValid,
} from './event_configurations/configurations';
import FlowTriggerConditionForm from './flow_trigger_condition_form.vue';
import FlowTriggerConditionRow from './flow_trigger_condition_row.vue';

export default {
  name: 'FlowTriggerConditions',
  components: {
    CrudComponent,
    FlowTriggerConditionForm,
    FlowTriggerConditionRow,
    GlBadge,
    GlDisclosureDropdown,
    GlIcon,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    isGroupNamespace: {},
    timezoneData: {
      default: () => [],
    },
    userTimezone: {
      default: '',
    },
  },
  props: {
    eventTypes: {
      type: Array,
      required: false,
      default: () => [],
    },
    filter: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    showErrors: {
      type: Boolean,
      required: false,
      default: false,
    },
    itemTypeLabel: {
      type: String,
      required: true,
    },
    serviceAccountRole: {
      type: String,
      required: false,
      default: null,
    },
    goals: {
      type: Object,
      required: false,
      default: () => ({}),
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
    // False for external agents and configuration file flows, which Ai::FlowTrigger rejects
    // with the scheduled event type. Hiding the option is presentation; the model enforces it.
    scheduleSupported: {
      type: Boolean,
      required: false,
      default: false,
    },
    compact: {
      type: Boolean,
      required: false,
      default: false,
    },
    startWithSchedule: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['update:event-types', 'update:filter', 'update:filter-valid', 'update:goals'],
  data() {
    return {
      // The condition currently open in the panel form, and where it belongs on save.
      // A null index means it is not in the list yet.
      draft: null,
      draftIndex: null,
    };
  },
  computed: {
    enabledTypes() {
      return getEnabledFlowTriggerTypes(this.glFeatures);
    },
    // An event type maps to a single filter scope, so it can only be configured once. The type
    // being edited stays selectable so reopening its form does not empty the picker.
    selectableEventTypes() {
      const editingType = this.draftIndex === null ? null : this.eventTypes[this.draftIndex];

      return this.enabledTypes
        .filter((type) => type.value !== FLOW_TRIGGER_MODE_SCHEDULE)
        .filter((type) => !this.eventTypes.includes(type.value) || type.value === editingType)
        .map((type) => toFlowTriggerTypeOption(type, this.itemTypeLabel, this.glFeatures));
    },
    // One schedule per trigger, because the whole schedule lives on a single filter scope.
    canAddSchedule() {
      return (
        this.scheduleSupported &&
        !this.isGroupNamespace &&
        this.enabledTypes.some((type) => type.value === FLOW_TRIGGER_MODE_SCHEDULE) &&
        !this.eventTypes.includes(FLOW_TRIGGER_MODE_SCHEDULE)
      );
    },
    canAddEvent() {
      return this.selectableEventTypes.length > 0;
    },
    conditionsDescription() {
      if (this.compact) {
        return this.canAddSchedule
          ? s__('DuoAgentsPlatform|No triggers yet. Add a schedule or an event.')
          : s__('DuoAgentsPlatform|No triggers yet. Add an event.');
      }

      return this.canAddSchedule
        ? s__('DuoAgentsPlatform|No conditions yet. Add a schedule or an event.')
        : s__('DuoAgentsPlatform|No conditions yet. Add an event.');
    },
    panelDescription() {
      return this.canAddSchedule
        ? s__(
            'DuoAgentsPlatform|Run at set times, or when something happens in the project. You can have multiple conditions.',
          )
        : s__(
            'DuoAgentsPlatform|Run when something happens in the project. You can have multiple conditions.',
          );
    },
    addConditionItems() {
      const items = [];

      if (this.canAddSchedule) {
        items.push({
          text: s__('DuoAgentsPlatform|On a schedule'),
          description: s__('DuoAgentsPlatform|Run at a recurring time.'),
          icon: 'clock',
          beta: true,
          action: () => this.startAdding(FLOW_TRIGGER_MODE_SCHEDULE),
        });
      }

      if (this.canAddEvent) {
        items.push({
          text: s__('DuoAgentsPlatform|On an event'),
          description: s__('DuoAgentsPlatform|Run when something happens in the project.'),
          icon: 'trigger-source',
          action: () => this.startAdding(FLOW_TRIGGER_MODE_EVENT),
        });
      }

      return items;
    },
    hasConditions() {
      return this.eventTypes.length > 0;
    },
    isEditing() {
      return this.draft !== null;
    },
    isAdding() {
      return this.isEditing && this.draftIndex === null;
    },
    isValid() {
      // An open form is work in progress. Committing it on the user's behalf could save a
      // half-configured condition, and ignoring it would drop something they believe they
      // added, so the trigger is not saveable until they finish or cancel it.
      return (
        !this.isEditing &&
        this.hasConditions &&
        this.eventTypes.every((typeValue) => isEventConfigurationValid(typeValue, this.filter))
      );
    },
    feedback() {
      if (!this.showErrors) {
        return null;
      }

      if (this.isEditing) {
        return s__('DuoAgentsPlatform|Finish or cancel the open condition before saving.');
      }

      if (!this.hasConditions) {
        return sprintf(
          s__('DuoAgentsPlatform|Add a condition so this %{itemType} knows when to run.'),
          { itemType: this.itemTypeLabel },
        );
      }

      return null;
    },
    // Rows draw their own dividers edge to edge, so they need a padding-free body. The empty
    // state is plain text and wants the panel's default padding back.
    bodyClass() {
      return this.hasConditions ? '!gl-p-0' : null;
    },
  },
  watch: {
    // Picking a target that cannot run on a schedule leaves no way to add the open draft.
    canAddSchedule(canAdd) {
      if (!canAdd && this.isAdding && this.draft.mode === FLOW_TRIGGER_MODE_SCHEDULE) {
        this.closeForm();
      }
    },
    isValid: {
      immediate: true,
      handler(value) {
        this.$emit('update:filter-valid', value);
      },
    },
  },
  mounted() {
    if (this.startWithSchedule && this.canAddSchedule) {
      this.startAdding(FLOW_TRIGGER_MODE_SCHEDULE, { focus: false });
    }
  },
  methods: {
    rowInvalidFeedback(typeValue) {
      return this.showErrors ? eventConfigurationInvalidFeedback(typeValue, this.filter) : null;
    },
    closeForm() {
      this.draft = null;
      this.draftIndex = null;
      this.$refs.crud.hideForm();
    },
    async openForm({ focus = true } = {}) {
      this.$refs.crud.showForm();
      if (!focus) return;

      // The row that opened the form is now disabled, so leaving focus on it would strand
      // keyboard users. Wait for the panel to render, then move focus into it.
      await this.$nextTick();
      this.$refs.form?.$el?.focus();
    },
    startAdding(mode, { focus = true } = {}) {
      const isSchedule = mode === FLOW_TRIGGER_MODE_SCHEDULE;

      this.draft = {
        mode,
        typeValue: isSchedule ? FLOW_TRIGGER_MODE_SCHEDULE : null,
        filter: isSchedule && this.compact ? this.defaultScheduleFilter() : {},
        goal: '',
      };
      this.draftIndex = null;
      this.openForm({ focus });
    },
    defaultScheduleFilter() {
      const timezone = defaultScheduleTimezone(this.timezoneData, this.userTimezone);

      return {
        [FLOW_TRIGGER_MODE_SCHEDULE]: randomizeScheduleDefaults(SCHEDULE_FREQUENCY_WEEKLY, {
          timezone,
        }),
      };
    },
    startEditing(index) {
      const typeValue = this.eventTypes[index];
      const scopedFilter = this.filter[typeValue];

      this.draft = {
        mode: flowTriggerModeFor(typeValue),
        typeValue,
        filter: scopedFilter === undefined ? {} : { [typeValue]: scopedFilter },
        goal: this.goals[typeValue] ?? '',
      };
      this.draftIndex = index;
      this.openForm();
    },
    saveDraft({ typeValue, filter, goal }) {
      const previousType = this.isAdding ? null : this.eventTypes[this.draftIndex];

      const nextEventTypes = this.isAdding
        ? [...this.eventTypes, typeValue]
        : this.eventTypes.map((existing, index) =>
            index === this.draftIndex ? typeValue : existing,
          );

      // Dropping the previous scope first keeps a stale configuration from surviving an
      // edit that switched the condition to a different event type.
      this.$emit('update:event-types', nextEventTypes);
      this.$emit('update:filter', {
        ...omit(this.filter, previousType ? [previousType] : []),
        ...filter,
      });
      // A hidden goal stays where it is stored. Moving it would be a new key, which is refused.
      const nextGoal =
        this.goalSupported || typeValue !== previousType ? goal : this.goals[previousType];

      // An empty goal drops the key rather than storing '', which the model rejects anyway.
      this.$emit('update:goals', {
        ...omit(this.goals, previousType ? [previousType] : []),
        ...(nextGoal ? { [typeValue]: nextGoal } : {}),
      });
      this.closeForm();
    },
    removeCondition(index) {
      // Removing the condition being edited would leave the form pointed at a stale index.
      if (this.draftIndex === index) {
        this.closeForm();
      } else if (this.draftIndex !== null && index < this.draftIndex) {
        this.draftIndex -= 1;
      }

      this.$emit(
        'update:event-types',
        this.eventTypes.filter((_, position) => position !== index),
      );
      this.$emit('update:filter', omit(this.filter, [this.eventTypes[index]]));
      this.$emit('update:goals', omit(this.goals, [this.eventTypes[index]]));
    },
  },
};
</script>

<template>
  <div>
    <crud-component
      ref="crud"
      :title="compact ? s__('DuoAgentsPlatform|Runs when') : s__('DuoAgentsPlatform|Conditions')"
      :description="compact ? null : panelDescription"
      :count="compact ? null : eventTypes.length"
      :show-zero-count="!compact"
      :body-class="bodyClass"
    >
      <template v-if="addConditionItems.length" #actions>
        <gl-disclosure-dropdown
          :items="addConditionItems"
          :toggle-text="
            compact ? s__('DuoAgentsPlatform|Add trigger') : s__('DuoAgentsPlatform|Add condition')
          "
          size="small"
          placement="bottom-end"
        >
          <template #list-item="{ item }">
            <div class="gl-flex gl-items-start gl-gap-3">
              <gl-icon :name="item.icon" class="gl-mt-1 gl-shrink-0 gl-text-subtle" />
              <div class="gl-flex gl-flex-col">
                <span class="gl-flex gl-items-center gl-gap-2">
                  <strong>{{ item.text }}</strong>
                  <gl-badge v-if="item.beta">
                    {{ s__('DuoAgentsPlatform|Beta') }}
                  </gl-badge>
                </span>
                <span class="gl-text-sm gl-text-subtle">{{ item.description }}</span>
              </div>
            </div>
          </template>
        </gl-disclosure-dropdown>
      </template>

      <template #form>
        <flow-trigger-condition-form
          v-if="isEditing"
          ref="form"
          :key="draft.typeValue || draft.mode"
          :mode="draft.mode"
          :type-value="draft.typeValue"
          :filter="draft.filter"
          :type-options="selectableEventTypes"
          :is-new="isAdding"
          :service-account-role="serviceAccountRole"
          :goal="draft.goal || ''"
          :goal-supported="goalSupported"
          :goal-help-visible="goalHelpVisible"
          :compact="compact"
          @save="saveDraft"
          @cancel="closeForm"
        />
      </template>

      <template v-if="!hasConditions" #empty>
        <span>{{ conditionsDescription }}</span>
      </template>

      <ul class="gl-mb-0 gl-list-none gl-p-0">
        <flow-trigger-condition-row
          v-for="(typeValue, index) in eventTypes"
          :key="typeValue"
          :type-value="typeValue"
          :filter="filter"
          :goal="goalSupported ? goals[typeValue] || '' : ''"
          :invalid-feedback="rowInvalidFeedback(typeValue)"
          :is-editing="draftIndex === index"
          @edit="startEditing(index)"
          @remove="removeCondition(index)"
        />
      </ul>
    </crud-component>

    <p
      v-if="feedback"
      role="alert"
      class="gl-mb-0 gl-mt-2 gl-text-sm gl-text-danger"
      data-testid="conditions-error"
    >
      {{ feedback }}
    </p>
  </div>
</template>
