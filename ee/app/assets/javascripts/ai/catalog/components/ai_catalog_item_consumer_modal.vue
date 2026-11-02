<script>
import { uniqueId } from 'lodash-es';
import { GlAlert, GlForm, GlFormGroup, GlFormTextarea, GlModal, GlSprintf } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { __, s__, sprintf } from '~/locale';
import { TYPENAME_PROJECT, TYPENAME_GROUP } from '~/graphql_shared/constants';
import { convertToGraphQLId, getIdFromGraphQLId } from '~/graphql_shared/utils';
import { joinPaths } from '~/lib/utils/url_utility';
import {
  FLOW_TRIGGER_TYPE_MENTION,
  FLOW_TRIGGER_TYPE_ASSIGN,
  FLOW_TRIGGER_TYPE_ASSIGN_REVIEWER,
  FLOW_TRIGGER_GOAL_MAX_LENGTH,
} from 'ee/ai/duo_agents_platform/constants';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import FlowTriggerConditions from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_conditions.vue';
import {
  denormalizeMergeRequestEventTypes,
  eventTypeIntsToValues,
  eventTypeValuesToInts,
} from 'ee/ai/duo_agents_platform/utils';
import {
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  AI_CATALOG_PROJECT_CONSUMER_LABEL_DESCRIPTION,
  AI_CATALOG_PROJECT_MULTI_CONSUMER_LABEL_DESCRIPTION,
  AI_CATALOG_ITEM_CONSUMER_DISCLAIMER_TEXTS,
  MAX_PROJECTS_BULK_ENABLE,
  VISIBILITY_LEVEL_PUBLIC,
  VISIBILITY_LEVEL_PRIVATE,
  VISIBILITY_LEVEL_RESTRICTED,
} from '../constants';
import { getRegistryItem } from '../item_type_registry';
import { getAiCatalogItemOwningProjectName } from '../capabilities';
import FormProjectMultiSelect from './form_project_multi_select.vue';
import FormProjectDropdown from './form_project_dropdown.vue';
import AiCatalogItemConsumerDisclaimer from './ai_catalog_item_consumer_disclaimer.vue';

const DEFAULT_TRIGGER_TYPES = [
  FLOW_TRIGGER_TYPE_MENTION.value,
  FLOW_TRIGGER_TYPE_ASSIGN.value,
  FLOW_TRIGGER_TYPE_ASSIGN_REVIEWER.value,
];

export default {
  name: 'AiCatalogItemConsumerModal',
  formId: uniqueId('ai-catalog-item-consumer-form-'),
  components: {
    FormProjectMultiSelect,
    FormProjectDropdown,
    FlowTriggerConditions,
    GlAlert,
    GlForm,
    GlFormGroup,
    GlFormTextarea,
    GlModal,
    GlSprintf,
    HelpPageLink,
    AiCatalogItemConsumerDisclaimer,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    isGlobalNamespace: {},
    isProjectNamespace: {},
    isGroupNamespace: {},
    contextProjectId: {
      from: 'projectId',
      default: null,
    },
    groupId: {
      default: null,
    },
    groupName: {
      default: null,
    },
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    modalId: {
      type: String,
      required: false,
      default: 'add-item-consumer-modal',
    },
    canEnable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['hide', 'submit'],
  data() {
    return {
      isOpen: this.open,
      projectId: null,
      projectIds: [],
      isDirty: false,
      error: null,
      triggerTypes: [],
      triggerGoals: {},
      goal: '',
      triggerFilter: {},
      areTriggersValid: true,
      mountedAt: null,
    };
  },
  computed: {
    itemRegistry() {
      return getRegistryItem(this.item.itemType);
    },
    defaultProjectId() {
      if (this.isProjectNamespace) {
        return convertToGraphQLId(TYPENAME_PROJECT, this.contextProjectId);
      }
      return this.item.visibility === VISIBILITY_LEVEL_PUBLIC ? null : this.item.project?.id;
    },
    showProjectSection() {
      return this.isGlobalNamespace;
    },
    isGroupPrivate() {
      return this.isGroupNamespace && this.isPrivate;
    },
    itemEditPath() {
      if (!this.item.project?.webPath) return null;
      return joinPaths(
        this.item.project.webPath,
        this.itemRegistry.namespacePath,
        getIdFromGraphQLId(this.item.id).toString(),
        'edit',
      );
    },
    modal() {
      if (this.isGroupPrivate) {
        return {
          actionPrimary: {
            text: sprintf(s__('AICatalog|Go to %{itemType} settings'), {
              itemType: this.itemTypeLabel,
            }),
            attributes: {
              variant: 'confirm',
              href: this.itemEditPath,
            },
          },
          actionCancel: null,
        };
      }
      return {
        actionPrimary: {
          text: this.primaryActionText,
          attributes: {
            variant: this.primaryActionVariant,
            type: 'submit',
            form: this.$options.formId,
            disabled: !this.canEnable,
          },
        },
        actionCancel: {
          text: __('Cancel'),
        },
      };
    },
    primaryActionText() {
      if (!this.isGroupNamespace) return __('Enable');
      return this.showGroupEnablementDisclaimer
        ? s__('AICatalog|Replace and enable for all projects')
        : __('Enable for all projects');
    },
    primaryActionVariant() {
      return this.showGroupEnablementDisclaimer ? 'danger' : 'confirm';
    },
    showGroupEnablementDisclaimer() {
      return this.isGroupNamespace && Boolean(this.item.hasDirectProjectConfigurationsInGroup);
    },
    itemTypeLabel() {
      return this.itemRegistry.label;
    },
    title() {
      if (this.isGroupPrivate) {
        return sprintf(s__('AICatalog|This %{itemType} is private'), {
          itemType: this.itemTypeLabel,
        });
      }
      if (this.isGroupNamespace) {
        return sprintf(s__('AICatalog|Enable %{itemType} for all projects in %{groupName}'), {
          itemType: this.itemTypeLabel,
          groupName: this.groupName,
        });
      }
      return sprintf(s__('AICatalog|Enable %{itemType} in your project'), {
        itemType: this.itemTypeLabel,
      });
    },
    isRestricted() {
      return this.item.visibility === VISIBILITY_LEVEL_RESTRICTED;
    },
    isPrivate() {
      return this.item.visibility === VISIBILITY_LEVEL_PRIVATE;
    },
    restrictedGroupName() {
      return this.item.project?.rootGroup?.fullName;
    },
    owningProjectName() {
      return getAiCatalogItemOwningProjectName(this.item);
    },
    canEnableOnMultipleProjects() {
      return this.item.visibility === VISIBILITY_LEVEL_PUBLIC && this.isGlobalNamespace;
    },
    projectLabelDescription() {
      return this.canEnableOnMultipleProjects
        ? AI_CATALOG_PROJECT_MULTI_CONSUMER_LABEL_DESCRIPTION[this.item.itemType]
        : AI_CATALOG_PROJECT_CONSUMER_LABEL_DESCRIPTION[this.item.itemType];
    },
    isProjectValid() {
      if (!this.isDirty) return true;
      return this.canEnableOnMultipleProjects
        ? this.projectIds.length > 0 && this.projectIds.length <= MAX_PROJECTS_BULK_ENABLE
        : Boolean(this.projectId);
    },
    projectInvalidFeedback() {
      if (!this.canEnableOnMultipleProjects) {
        return s__('AICatalog|Project is required.');
      }
      if (this.projectIds.length > MAX_PROJECTS_BULK_ENABLE) {
        return s__('AICatalog|Limit of 100 projects reached.');
      }
      return s__('AICatalog|At least one project is required.');
    },
    showStaticFields() {
      return this.isPrivate;
    },
    isFormValid() {
      if (this.isGroupNamespace) {
        return this.hasValidTriggers;
      }
      return this.isProjectValid && this.hasValidTriggers;
    },
    isFoundationalFlow() {
      return this.item.itemType === AI_CATALOG_TYPE_FLOW && this.item.foundational;
    },
    showFlowInheritanceDisclaimer() {
      return this.isGroupNamespace && this.item.itemType === AI_CATALOG_TYPE_FLOW;
    },
    flowInheritanceDisclaimer() {
      return AI_CATALOG_ITEM_CONSUMER_DISCLAIMER_TEXTS[AI_CATALOG_TYPE_FLOW].groupEnabledForMembers;
    },
    showTriggers() {
      if (this.isFoundationalFlow) {
        return false;
      }
      return [AI_CATALOG_TYPE_FLOW, AI_CATALOG_TYPE_THIRD_PARTY_FLOW].includes(this.item.itemType);
    },
    goalSupported() {
      return Boolean(this.glFeatures.aiFlowTriggerGoals && this.item.acceptsTriggerGoal);
    },
    isAutomationLayout() {
      return Boolean(this.glFeatures.duoAutomations && this.isProjectNamespace);
    },
    // Matches the automation modal: one set of instructions for every condition.
    isSharedGoalVisible() {
      return this.isAutomationLayout && this.goalSupported;
    },
    scheduleSupported() {
      return this.item.itemType !== AI_CATALOG_TYPE_THIRD_PARTY_FLOW;
    },
    hasValidTriggers() {
      return !this.showTriggers || this.areTriggersValid;
    },
  },
  watch: {
    defaultProjectId(newVal) {
      if (this.projectId == null && newVal) {
        this.projectId = newVal;
        Sentry.captureException(
          new Error('AiCatalogItemConsumerModal: project data arrived after mount'),
          {
            level: 'info',
            tags: {
              race_type: 'ai_catalog_project_field',
              item_type: this.item?.itemType,
            },
            extra: {
              item_id: this.item?.id,
              time_to_resolve_ms:
                this.mountedAt != null ? Math.round(performance.now() - this.mountedAt) : null,
            },
          },
        );
      }
    },
  },
  mounted() {
    this.mountedAt = performance.now();
    this.resetForm();
  },
  methods: {
    onError(error) {
      this.error = error;
    },
    handleSubmit() {
      this.isDirty = true;
      if (!this.isFormValid) {
        return;
      }
      this.isOpen = false;
      this.isDirty = false;

      let payload;

      if (this.canEnableOnMultipleProjects) {
        payload = { target: this.projectIds };
      } else if (this.isGroupNamespace) {
        payload = { target: { groupId: convertToGraphQLId(TYPENAME_GROUP, this.groupId) } };
      } else {
        payload = { target: { projectId: this.projectId } };
      }

      if (this.showTriggers) {
        // The field consolidates merge_request_ready (4) and merge_request_code_conflict (5)
        // into merge_request (6) with an action filter. The backend dispatches ready/conflict
        // via separate event types, so split them back out before submitting.
        const { eventTypes, filter, goals } = denormalizeMergeRequestEventTypes({
          eventTypes: eventTypeValuesToInts(this.triggerTypes),
          filter: this.triggerFilter,
          goals: this.triggerGoals,
        });

        payload.triggerTypes = eventTypeIntsToValues(eventTypes);
        if (Object.keys(filter).length > 0) {
          payload.triggerFilter = filter;
        }

        const goal = this.goal.trim();
        if (this.isSharedGoalVisible && goal) {
          payload.triggerGoals = Object.fromEntries(
            payload.triggerTypes.map((name) => [name, goal]),
          );
        } else if (!this.isSharedGoalVisible && Object.keys(goals).length > 0) {
          payload.triggerGoals = goals;
        }
      }

      this.$emit('submit', payload);
    },
    resetForm() {
      this.projectId = this.defaultProjectId;
      this.projectIds = [];
      this.isDirty = false;
      this.error = null;
      this.triggerTypes = [...DEFAULT_TRIGGER_TYPES];
      this.triggerFilter = {};
      this.triggerGoals = {};
      this.goal = '';
      this.areTriggersValid = true;
    },
    onHidden() {
      this.resetForm();
      this.$emit('hide');
    },
  },
  FLOW_TRIGGER_GOAL_MAX_LENGTH,
};
</script>

<template>
  <gl-modal
    v-model="isOpen"
    :modal-id="modalId"
    :title="title"
    :action-primary="modal.actionPrimary"
    :action-cancel="modal.actionCancel"
    @primary.prevent
    @hidden="onHidden"
  >
    <template v-if="isGroupPrivate">
      <p data-testid="group-private-message">
        <gl-sprintf
          :message="
            s__('AICatalog|%{itemName} is private and can\'t be shared with other projects.')
          "
        >
          <template #itemName>
            <strong>{{ item.name }}</strong>
          </template>
        </gl-sprintf>
      </p>
      <p v-if="item.project" class="gl-mb-0" data-testid="group-private-instructions">
        <gl-sprintf
          :message="
            s__(
              'AICatalog|To enable it for all projects in the group, change its visibility setting to %{boldStart}Restricted%{boldEnd} or %{boldStart}Public%{boldEnd} in %{projectName}.',
            )
          "
        >
          <template #bold="{ content }">
            <strong>{{ content }}</strong>
          </template>
          <template #projectName>
            <strong>{{ item.project.nameWithNamespace }}</strong>
          </template>
        </gl-sprintf>
      </p>
    </template>
    <template v-else>
      <gl-alert
        v-if="error"
        data-testid="error-alert"
        variant="danger"
        class="gl-mb-5"
        @dismiss="error = null"
      >
        {{ error }}
      </gl-alert>

      <gl-alert
        v-if="isPrivate && !isProjectNamespace && item.project"
        data-testid="private-alert"
        :dismissible="false"
        variant="info"
        class="gl-mb-5"
      >
        <gl-sprintf
          :message="
            s__(
              'AICatalog|This private %{itemType} is managed by %{projectName}. You can enable it only in that project. Duplicate the %{itemType} to use the same configuration in other projects.',
            )
          "
        >
          <template #itemType>{{ itemTypeLabel }}</template>
          <template #projectName>{{ owningProjectName }}</template>
        </gl-sprintf>
      </gl-alert>

      <gl-alert
        v-if="isRestricted && !isProjectNamespace && item.project"
        data-testid="restricted-alert"
        :dismissible="false"
        variant="info"
        class="gl-mb-5"
      >
        <gl-sprintf
          :message="
            s__(
              'AICatalog|This %{itemType} can only be enabled in projects within the top-level group %{groupName}.',
            )
          "
        >
          <template #itemType>{{ itemTypeLabel }}</template>
          <template #groupName>{{ restrictedGroupName }}</template>
        </gl-sprintf>
      </gl-alert>

      <dl>
        <dt class="gl-mb-2 gl-font-bold">
          <gl-sprintf :message="s__('AICatalog|Selected %{itemType}')">
            <template #itemType>{{ itemTypeLabel }}</template>
          </gl-sprintf>
        </dt>
        <dd class="gl-break-all">{{ item.name }}</dd>
      </dl>

      <gl-form :id="$options.formId" @submit.prevent="handleSubmit">
        <template v-if="showProjectSection">
          <div v-if="showStaticFields && item.project">
            <dl>
              <dt class="gl-mb-2 gl-font-bold">{{ __('Project') }}</dt>
              <dd data-testid="project-name">{{ item.project.nameWithNamespace }}</dd>
            </dl>
          </div>
          <div v-else>
            <form-project-multi-select
              v-if="canEnableOnMultipleProjects"
              id="project-ids"
              v-model="projectIds"
              data-testid="project-multi-select"
              :is-valid="isProjectValid"
              :item-id="item.id"
              :project-label-description="projectLabelDescription"
              :project-invalid-feedback="projectInvalidFeedback"
              @error="onError"
            />
            <gl-form-group
              v-else
              :label="__('Project')"
              :label-description="projectLabelDescription"
              label-for="project-id"
              :state="isProjectValid"
              :invalid-feedback="projectInvalidFeedback"
            >
              <form-project-dropdown
                id="project-id"
                v-model="projectId"
                data-testid="project-dropdown"
                :disabled="!canEnable"
                :is-valid="isProjectValid"
                :item-id="item.id"
                @error="onError"
              />
            </gl-form-group>
          </div>
        </template>
        <p v-if="showFlowInheritanceDisclaimer" data-testid="flow-disclaimer">
          {{ flowInheritanceDisclaimer }}
        </p>
        <dl v-if="showGroupEnablementDisclaimer" data-testid="group-enablement-disclaimer">
          <dt class="gl-mb-2 gl-font-bold">{{ s__('AICatalog|Group enablement') }}</dt>
          <dd>
            <gl-sprintf
              :message="
                s__(
                  'AICatalog|This %{itemType} is already enabled in one or more projects in this group. If you enable it for all projects, the project configuration for the %{itemType} will be deleted and the group configuration will be used instead.',
                )
              "
            >
              <template #itemType>{{ itemTypeLabel }}</template>
            </gl-sprintf>
          </dd>
        </dl>
        <gl-form-group
          v-if="showTriggers && canEnable && isSharedGoalVisible"
          label-for="item-consumer-goal"
          data-testid="item-consumer-goal-group"
        >
          <template #label>
            {{ s__('DuoAgentsPlatform|Instructions') }}
            <span class="gl-font-normal">{{ __('(optional)') }}</span>
          </template>
          <template #description>
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
          <gl-form-textarea
            id="item-consumer-goal"
            v-model="goal"
            :maxlength="$options.FLOW_TRIGGER_GOAL_MAX_LENGTH"
            :placeholder="
              s__(
                'DuoAgentsPlatform|Describe what should happen each time this runs. For example, review open issues labeled bug and open a merge request for the simplest fix.',
              )
            "
            rows="4"
            no-resize
            data-testid="item-consumer-goal"
          />
        </gl-form-group>
        <flow-trigger-conditions
          v-if="showTriggers && canEnable"
          :item-type-label="itemTypeLabel"
          :event-types="triggerTypes"
          :filter="triggerFilter"
          :show-errors="isDirty"
          :goals="triggerGoals"
          :goal-supported="goalSupported && !isAutomationLayout"
          goal-help-visible
          :schedule-supported="scheduleSupported"
          :compact="isAutomationLayout"
          @update:event-types="triggerTypes = $event"
          @update:filter="triggerFilter = $event"
          @update:filter-valid="areTriggersValid = $event"
          @update:goals="triggerGoals = $event"
        />
      </gl-form>
      <ai-catalog-item-consumer-disclaimer
        class="gl-pt-5"
        :item-type="item.itemType"
        :can-enable="canEnable"
        :trigger-types="triggerTypes"
      />
    </template>
  </gl-modal>
</template>
