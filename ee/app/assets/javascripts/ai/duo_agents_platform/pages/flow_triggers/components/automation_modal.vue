<script>
import fuzzaldrinPlus from 'fuzzaldrin-plus';
import { pick } from 'lodash-es';
import {
  GlAlert,
  GlCollapsibleListbox,
  GlFormGroup,
  GlFormInput,
  GlFormTextarea,
  GlModal,
  GlSprintf,
  GlToastMixin,
} from '@gitlab/ui';
import { __, s__ } from '~/locale';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_PROJECT } from '~/graphql_shared/constants';
import UserSelect from '~/vue_shared/components/user_select/user_select.vue';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import { DUO_WORKFLOW_DEVELOPER_DEFINITION } from 'ee/ai/constants';
import {
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  FOUNDATIONAL_FLOW_REFERENCE_CODE_REVIEW,
} from 'ee/ai/catalog/constants';
import {
  FLOW_TRIGGER_GOAL_MAX_LENGTH,
  FLOW_TRIGGER_MODE_SCHEDULE,
} from 'ee/ai/duo_agents_platform/constants';
import {
  automationSharedGoal,
  denormalizeMergeRequestEventTypes,
  eventTypeIntsToValues,
  eventTypeValuesToInts,
  normalizeMergeRequestEventTypes,
} from 'ee/ai/duo_agents_platform/utils';
import createAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/create_ai_flow_trigger.mutation.graphql';
import updateAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import getCatalogConsumerItemsQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_catalog_consumer_items.query.graphql';
import projectServiceAccountsQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_project_service_accounts.query.graphql';
import projectServiceAccountRolesQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_project_service_account_roles.query.graphql';
import FlowTriggerConditions from './flow_trigger_conditions.vue';

// Catalog items use their consumer gid as the listbox value, which never collides with this.
const CONFIG_PATH_VALUE = 'config_path';
const NAME_MAX_LENGTH = 255;

export default {
  name: 'AutomationModal',
  components: {
    FlowTriggerConditions,
    GlAlert,
    GlCollapsibleListbox,
    GlFormGroup,
    GlFormInput,
    GlFormTextarea,
    GlModal,
    GlSprintf,
    HelpPageLink,
    UserSelect,
  },
  mixins: [GlToastMixin, glAbilitiesMixin(), glFeatureFlagsMixin()],
  inject: ['projectPath', 'projectId'],
  props: {
    automation: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['hidden', 'saved'],
  apollo: {
    catalogItems: {
      query: getCatalogConsumerItemsQuery,
      variables() {
        return {
          projectId: convertToGraphQLId(TYPENAME_PROJECT, this.projectId),
          itemTypes: this.catalogItemTypes,
        };
      },
      skip() {
        return this.catalogItemTypes.length === 0;
      },
      update(data) {
        // Code Review runs when `@GitLabDuo` is assigned as a reviewer, not from automations.
        return (data.aiCatalogConfiguredItems?.nodes ?? []).filter(
          ({ item }) => item.foundationalFlowReference !== FOUNDATIONAL_FLOW_REFERENCE_CODE_REVIEW,
        );
      },
      error() {
        this.errorMessages.push(
          s__(
            'DuoAgentsPlatform|An error occurred while fetching flows configured for this project.',
          ),
        );
      },
    },
    serviceAccountRoles: {
      query: projectServiceAccountRolesQuery,
      variables() {
        return { fullPath: this.projectPath };
      },
      skip() {
        return this.catalogItemTypes.length === 0;
      },
      update(data) {
        return Object.fromEntries(
          (data.project?.projectMembers?.nodes ?? [])
            .filter(({ user }) => user)
            .map(({ user, accessLevel }) => [user.id, accessLevel?.humanAccess]),
        );
      },
      error() {
        this.errorMessages.push(
          s__('DuoAgentsPlatform|An error occurred while fetching service account roles.'),
        );
      },
    },
  },
  data() {
    const { eventTypes, filter } = normalizeMergeRequestEventTypes({
      eventTypes: this.automation?.eventTypes ?? [],
      filter: this.automation?.filter ?? {},
    });
    const configPath = this.automation?.configPath ?? '';
    const consumerId = this.automation?.aiCatalogItemConsumer?.id;

    return {
      catalogItems: [],
      serviceAccountRoles: {},
      searchTerm: '',
      selected: consumerId || (configPath ? CONFIG_PATH_VALUE : null),
      name: this.automation?.description ?? '',
      goal: (this.automation && automationSharedGoal(this.automation)) ?? '',
      configPath,
      selectedUsers: this.automation?.user && configPath ? [this.automation.user] : [],
      eventTypes: eventTypeIntsToValues(eventTypes),
      filter,
      isTriggerFilterValid: false,
      showErrors: false,
      isSaving: false,
      errorMessages: [],
    };
  },
  computed: {
    isEditing() {
      return Boolean(this.automation);
    },
    catalogItemTypes() {
      return [
        this.glAbilities.readAiCatalogFlow && AI_CATALOG_TYPE_FLOW,
        this.glAbilities.readAiCatalogThirdPartyFlow && AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
      ].filter(Boolean);
    },
    developerItem() {
      return this.catalogItems.find(
        ({ item }) => item.foundationalFlowReference === DUO_WORKFLOW_DEVELOPER_DEFINITION,
      );
    },
    selectedValue() {
      if (this.selected || this.isEditing) return this.selected;
      if (this.catalogItemTypes.length === 0) return CONFIG_PATH_VALUE;

      return this.developerItem?.id ?? null;
    },
    isConfigPath() {
      return this.selectedValue === CONFIG_PATH_VALUE;
    },
    selectedItem() {
      return this.catalogItems.find(({ id }) => id === this.selectedValue);
    },
    isDeveloper() {
      return Boolean(this.selectedItem) && this.selectedItem === this.developerItem;
    },
    targetGroups() {
      const filter = (options) =>
        this.searchTerm
          ? fuzzaldrinPlus.filter(options, this.searchTerm, { key: ['text'] })
          : options;
      const toOptions = (items) =>
        filter(items.map(({ id, item }) => ({ value: id, text: item.name })));
      const others = this.catalogItems.filter((item) => item !== this.developerItem);

      return [
        {
          text: s__('DuoAgentsPlatform|Recommended'),
          options: toOptions(this.developerItem ? [this.developerItem] : []),
        },
        { text: s__('DuoAgentsPlatform|Flows and external agents'), options: toOptions(others) },
        {
          text: __('Other'),
          options: this.glAbilities.createAiCatalogThirdPartyFlow
            ? filter([
                { value: CONFIG_PATH_VALUE, text: s__('DuoAgentsPlatform|Configuration file') },
              ])
            : [],
        },
      ].filter((group) => group.options.length);
    },
    targetToggleText() {
      if (this.isConfigPath) return s__('DuoAgentsPlatform|Configuration file');

      const item = this.selectedItem?.item ?? this.automation?.aiCatalogItemConsumer?.item;

      return item?.name ?? s__('DuoAgentsPlatform|Select a flow or agent');
    },
    serviceAccountRole() {
      return this.serviceAccountRoles[this.selectedItem?.parentItemConsumer?.serviceAccount?.id];
    },
    isGoalVisible() {
      return Boolean(
        this.glFeatures.aiFlowTriggerGoals &&
        (this.isConfigPath || this.selectedItem?.item.acceptsTriggerGoal),
      );
    },
    // Only foundational flows are known to read the goal.
    showInstructionsHelp() {
      return this.isGoalVisible && !this.selectedItem?.item.foundationalFlowReference;
    },
    instructionsState() {
      return this.goalState === false || this.targetState === false ? false : null;
    },
    selectedUserName() {
      return this.selectedUsers[0]?.name ?? s__('DuoAgentsPlatform|Select a service account');
    },
    hasSchedule() {
      return this.eventTypes.includes(FLOW_TRIGGER_MODE_SCHEDULE);
    },
    // An unpicked target stays schedulable so conditions can be added before it;
    // the model rejects the combination on save if it turns out to be unsupported.
    scheduleSupported() {
      if (this.isConfigPath) {
        return false;
      }

      return this.selectedItem?.item.itemType !== AI_CATALOG_TYPE_THIRD_PARTY_FLOW;
    },
    nameState() {
      return this.showErrors ? Boolean(this.name.trim()) : null;
    },
    goalState() {
      if (!this.showErrors || !this.isGoalVisible || !this.isDeveloper) return null;

      return Boolean(this.goal.trim());
    },
    targetState() {
      return this.showErrors ? Boolean(this.selectedValue) : null;
    },
    configPathState() {
      return this.showErrors ? Boolean(this.configPath.trim()) : null;
    },
    serviceAccountState() {
      return this.showErrors ? this.selectedUsers.length > 0 : null;
    },
    isValid() {
      const states = [this.nameState, this.goalState, this.targetState];
      if (this.isConfigPath) states.push(this.configPathState, this.serviceAccountState);

      return states.every((state) => state !== false) && this.isTriggerFilterValid;
    },
    actionPrimary() {
      return {
        text: this.isEditing ? s__('DuoAgentsPlatform|Save changes') : __('Create'),
        attributes: {
          variant: 'confirm',
          loading: this.isSaving || this.$apollo.queries.catalogItems.loading,
        },
      };
    },
    actionCancel() {
      return { text: __('Cancel'), attributes: { disabled: this.isSaving } };
    },
  },
  watch: {
    // Hiding the add button leaves the previous schedule in place; the model rejects the
    // whole automation, not just that condition. buildInput narrows `filter` to the
    // remaining event types, so only these need clearing.
    scheduleSupported(isSupported) {
      if (isSupported) {
        return;
      }

      this.eventTypes = this.eventTypes.filter((type) => type !== FLOW_TRIGGER_MODE_SCHEDULE);
    },
  },
  methods: {
    buildInput() {
      const { eventTypes, filter } = denormalizeMergeRequestEventTypes({
        eventTypes: eventTypeValuesToInts(this.eventTypes),
        filter: pick(this.filter, this.eventTypes),
      });
      const eventTypeNames = eventTypeIntsToValues(eventTypes);
      const goal = this.goal.trim();

      // Keep the stored goals when the flag is off (the model refuses new ones), or when the
      // flow is not in the list, so it is unknown whether the flow accepts goals.
      let goals = pick(this.automation?.goals, eventTypeNames);
      if (this.glFeatures.aiFlowTriggerGoals && (this.isConfigPath || this.selectedItem)) {
        goals =
          this.isGoalVisible && goal
            ? Object.fromEntries(eventTypeNames.map((name) => [name, goal]))
            : {};
      }

      return {
        description: this.name.trim(),
        eventTypes,
        filter,
        goals,
        aiCatalogItemConsumerId: this.isConfigPath ? null : this.selectedValue,
        configPath: this.isConfigPath ? this.configPath.trim() : null,
        userId: this.isConfigPath ? this.selectedUsers[0].id : null,
      };
    },
    async onPrimary(event) {
      event.preventDefault();
      this.showErrors = true;
      if (!this.isValid) return;

      this.isSaving = true;
      this.errorMessages = [];

      try {
        const input = this.buildInput();
        const { data } = await this.$apollo.mutate(
          this.isEditing
            ? {
                mutation: updateAiFlowTriggerMutation,
                variables: { input: { ...input, id: this.automation.id } },
              }
            : {
                mutation: createAiFlowTriggerMutation,
                variables: { input: { ...input, projectPath: this.projectPath, active: true } },
              },
        );
        const { errors } = data.aiFlowTriggerUpdate ?? data.aiFlowTriggerCreate;
        if (errors.length) {
          this.errorMessages = errors;
          return;
        }

        this.$toast.show(
          this.isEditing
            ? s__('DuoAgentsPlatform|Automation updated successfully.')
            : s__('DuoAgentsPlatform|Automation created successfully.'),
        );
        this.$emit('saved');
        this.$refs.modal.hide();
      } catch (error) {
        this.errorMessages = [
          error.message ||
            (this.isEditing
              ? s__('DuoAgentsPlatform|The automation could not be updated. Try again.')
              : s__('DuoAgentsPlatform|The automation could not be created. Try again.')),
        ];
      } finally {
        this.isSaving = false;
      }
    },
    onUserSelectError() {
      this.errorMessages.push(s__('DuoAgentsPlatform|An error occurred while fetching users.'));
    },
    // The Code Review flow's account runs from reviewer assignment, not from automations.
    usersProcessor(data) {
      return (data.project?.projectMembers?.nodes ?? [])
        .map(({ user }) => user)
        .filter((user) => user && !user.username?.startsWith('duo-code-review-'));
    },
  },
  projectServiceAccountsQuery,
  NAME_MAX_LENGTH,
  FLOW_TRIGGER_GOAL_MAX_LENGTH,
  i18n: {
    permissions: s__('DuoAgentsPlatform|Permissions: %{role}'),
  },
};
</script>

<template>
  <gl-modal
    ref="modal"
    modal-id="automation-modal"
    :title="
      isEditing ? s__('DuoAgentsPlatform|Edit automation') : s__('DuoAgentsPlatform|New automation')
    "
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    visible
    @primary="onPrimary"
    @hidden="$emit('hidden')"
  >
    <gl-alert
      v-if="errorMessages.length"
      variant="danger"
      class="gl-mb-5"
      data-testid="automation-modal-errors"
      @dismiss="errorMessages = []"
    >
      <ul class="!gl-mb-0 gl-pl-5">
        <li v-for="(message, index) in errorMessages" :key="index">{{ message }}</li>
      </ul>
    </gl-alert>

    <div class="gl-flex gl-flex-col gl-gap-5">
      <gl-form-group
        :label="__('Name')"
        label-for="automation-name"
        :state="nameState"
        :invalid-feedback="s__('DuoAgentsPlatform|Name is required.')"
        class="!gl-mb-0"
      >
        <gl-form-input
          id="automation-name"
          v-model="name"
          :state="nameState"
          :maxlength="$options.NAME_MAX_LENGTH"
          :placeholder="s__('DuoAgentsPlatform|Weekly dependency check')"
          data-testid="automation-name"
        />
      </gl-form-group>

      <gl-form-group
        :label-for="isGoalVisible ? 'automation-goal' : null"
        :state="instructionsState"
        :invalid-feedback="
          goalState === false
            ? s__('DuoAgentsPlatform|Instructions are required.')
            : s__('DuoAgentsPlatform|Select a flow or agent.')
        "
        class="!gl-mb-0"
      >
        <template v-if="isGoalVisible" #label>
          {{ s__('DuoAgentsPlatform|Instructions') }}
          <span v-if="!isDeveloper" class="gl-font-normal" data-testid="automation-goal-optional">
            {{ __('(optional)') }}
          </span>
        </template>
        <template v-if="showInstructionsHelp" #description>
          <gl-sprintf
            :message="
              s__(
                'DuoAgentsPlatform|This flow might not use these instructions, depending on how it\'s configured. %{linkStart}How flows use instructions%{linkEnd}',
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
        <!-- The box draws the input border, so the textarea inside it has none. -->
        <div
          class="gl-bg-control gl-border gl-rounded-control focus-within:gl-focus"
          :class="instructionsState === false ? 'gl-border-control-error' : 'gl-border-control'"
        >
          <div
            class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-x-4 gl-px-4 gl-py-2 gl-text-subtle"
            :class="{ 'gl-border-b gl-border-b-control-default': isGoalVisible }"
          >
            <div class="gl-flex gl-items-center">
              <span id="automation-target-label">{{ s__('DuoAgentsPlatform|Runs with') }}</span>
              <gl-collapsible-listbox
                :items="targetGroups"
                :selected="selectedValue"
                :toggle-text="targetToggleText"
                toggle-aria-labelled-by="automation-target-label"
                :icon="isConfigPath ? 'doc-text' : 'flow-ai'"
                :header-text="s__('DuoAgentsPlatform|Select a flow or agent')"
                :loading="$apollo.queries.catalogItems.loading"
                :no-results-text="__('No results found')"
                category="tertiary"
                size="small"
                searchable
                @search="searchTerm = $event.trim()"
                @select="selected = $event"
              />
            </div>
            <span v-if="serviceAccountRole" data-testid="automation-permissions">
              <gl-sprintf :message="$options.i18n.permissions">
                <template #role>
                  <help-page-link href="user/permissions" anchor="roles">{{
                    serviceAccountRole
                  }}</help-page-link>
                </template>
              </gl-sprintf>
            </span>
          </div>
          <gl-form-textarea
            v-if="isGoalVisible"
            id="automation-goal"
            v-model="goal"
            :maxlength="$options.FLOW_TRIGGER_GOAL_MAX_LENGTH"
            :placeholder="
              s__(
                'DuoAgentsPlatform|Describe what should happen each time this runs. For example, review open issues labeled bug and open a merge request for the simplest fix.',
              )
            "
            rows="4"
            no-resize
            textarea-classes="!gl-bg-transparent !gl-shadow-none"
            data-testid="automation-goal"
          />
        </div>
      </gl-form-group>

      <template v-if="isConfigPath">
        <gl-form-group
          :label="s__('DuoAgentsPlatform|Configuration path')"
          :label-description="s__('DuoAgentsPlatform|Enter the path to your configuration file.')"
          label-for="automation-config-path"
          :state="configPathState"
          :invalid-feedback="s__('DuoAgentsPlatform|Configuration path is required.')"
          class="!gl-mb-0"
        >
          <gl-form-input
            id="automation-config-path"
            v-model="configPath"
            :state="configPathState"
            :placeholder="s__('DuoAgentsPlatform|Path to configuration file')"
            data-testid="automation-config-path"
          />
        </gl-form-group>

        <gl-form-group
          :label="s__('DuoAgentsPlatform|Service account')"
          label-for="automation-service-account"
          :state="serviceAccountState"
          :invalid-feedback="s__('DuoAgentsPlatform|Service account is required.')"
          class="!gl-mb-0"
        >
          <user-select
            id="automation-service-account"
            :value="selectedUsers"
            :text="selectedUserName"
            :header-text="s__('DuoAgentsPlatform|Select a service account')"
            :full-path="projectPath"
            :allow-multiple-assignees="false"
            :custom-search-users-query="$options.projectServiceAccountsQuery"
            :custom-search-users-processor="usersProcessor"
            class="gl-w-full"
            @input="selectedUsers = $event"
            @error="onUserSelectError"
          />
        </gl-form-group>
      </template>

      <flow-trigger-conditions
        :item-type-label="s__('AICatalog|agent or flow')"
        :event-types="eventTypes"
        :filter="filter"
        :show-errors="showErrors"
        :service-account-role="serviceAccountRole"
        :schedule-supported="scheduleSupported"
        :start-with-schedule="!isEditing"
        compact
        @update:event-types="eventTypes = $event"
        @update:filter="filter = $event"
        @update:filter-valid="isTriggerFilterValid = $event"
      />

      <p
        v-if="hasSchedule"
        class="gl-border gl-mb-0 gl-rounded-lg gl-border-subtle gl-bg-subtle gl-px-4 gl-py-3 gl-text-subtle"
        data-testid="automation-schedule-notice"
      >
        {{
          s__(
            'DuoAgentsPlatform|Scheduled runs are unattended and use only service account permissions.',
          )
        }}
        <help-page-link href="user/duo_agent_platform/security_threats">{{
          s__('DuoAgentsPlatform|See safe use guide')
        }}</help-page-link>
      </p>
    </div>
  </gl-modal>
</template>
