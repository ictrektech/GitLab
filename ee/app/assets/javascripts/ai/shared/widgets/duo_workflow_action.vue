<script>
import {
  GlButton,
  GlDisclosureDropdownItem,
  GlIcon,
  GlLink,
  GlPopover,
  GlTooltipDirective,
} from '@gitlab/ui';
import getDuoWorkflowStatusCheck from 'ee/ai/graphql/get_duo_workflow_status_check.query.graphql';
import getConfiguredFlows from 'ee/ai/graphql/get_configured_flows.query.graphql';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { s__, __ } from '~/locale';
import axios from '~/lib/utils/axios_utils';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { buildApiUrl } from '~/api/api_utils';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import FlowUnavailableButton from './flow_unavailable_button.vue';
import RepositoryRequiredButton from './repository_required_button.vue';

const FLOW_WEB_ENVIRONMENT = 'web';
const INIT_ERROR_MESSAGE = __('Something went wrong');
const RENDER_AS_BUTTON = 'button';
const RENDER_AS_DROPDOWN_ITEM = 'dropdown-item';

const MODE_NONE = 'none';
const MODE_BUTTON = 'button';
const MODE_UNAVAILABLE = 'unavailable';
const MODE_REPOSITORY_REQUIRED = 'repository-required';
const MODE_DROPDOWN_ITEM = 'dropdown-item';
const MODE_DROPDOWN_ITEM_UNAVAILABLE = 'dropdown-item-unavailable';

export default {
  name: 'DuoWorkflowAction',
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  components: {
    GlButton,
    GlDisclosureDropdownItem,
    GlIcon,
    GlLink,
    GlPopover,
    FlowUnavailableButton,
    RepositoryRequiredButton,
  },
  mixins: [glSlotsMixin],
  inject: {
    currentRef: {
      default: null,
      type: String,
    },
  },
  props: {
    projectPath: {
      type: String,
      required: true,
    },
    hoverMessage: {
      type: String,
      required: false,
      default: '',
    },
    disabledFlowMessage: {
      type: String,
      required: false,
      default: '',
    },
    disabledFlowHelpPath: {
      type: String,
      required: false,
      default: '',
    },
    goal: {
      type: String,
      required: true,
    },
    workflowDefinition: {
      type: String,
      required: true,
    },
    agentPrivileges: {
      type: Array,
      required: false,
      default: () => [1, 2],
    },
    promptValidatorRegex: {
      type: RegExp,
      required: false,
      default: null,
    },
    size: {
      type: String,
      default: 'small',
      required: false,
    },
    variant: {
      type: String,
      default: 'default',
      required: false,
    },
    category: {
      type: String,
      default: 'primary',
      required: false,
    },
    sourceBranch: {
      type: String,
      required: false,
      default: null,
    },
    workItemIid: {
      type: [String, Number],
      required: false,
      default: null,
    },
    mergeRequestId: {
      type: [String, Number],
      required: false,
      default: null,
    },
    additionalContext: {
      type: Array,
      required: false,
      default: () => [],
    },
    source: {
      type: String,
      required: false,
      default: null,
    },
    renderAs: {
      type: String,
      default: RENDER_AS_BUTTON,
      required: false,
      validator: (value) => [RENDER_AS_BUTTON, RENDER_AS_DROPDOWN_ITEM].includes(value),
    },
  },
  emits: ['agent-flow-started', 'prompt-validation-error', 'triggering', 'triggered'],
  data() {
    return {
      isStartingFlow: false,
      duoWorkflowData: null,
      aiCatalogItemConsumerId: null,
      hasLoadedConfiguredFlows: false,
    };
  },
  computed: {
    duoWorkflowInvokePath() {
      return buildApiUrl(`/api/:version/ai/duo_workflows/workflows`);
    },
    canStartFlow() {
      return Boolean(
        this.isDuoPlatformAvailable && this.isFlowExecutionEnabled && this.isFlowEnabledInSettings,
      );
    },
    isFlowExecutionEnabled() {
      return Boolean(this.duoWorkflowData?.remoteFlowsEnabled);
    },
    isDuoPlatformAvailable() {
      return Boolean(this.duoWorkflowData?.isDuoActionEnabled && this.projectId);
    },
    isFlowUnavailable() {
      if (!this.isDuoPlatformAvailable || !this.disabledFlowMessage) {
        return false;
      }

      if (this.duoWorkflowData?.remoteFlowsEnabled === false) {
        return true;
      }

      return (
        this.isFlowExecutionEnabled &&
        this.hasLoadedConfiguredFlows &&
        !this.isFlowEnabledInSettings
      );
    },
    projectId() {
      return this.duoWorkflowData?.projectId || null;
    },
    projectGid() {
      return this.duoWorkflowData?.projectGid || null;
    },
    isFlowEnabledInSettings() {
      return Boolean(this.aiCatalogItemConsumerId);
    },
    isRepositoryEmpty() {
      return Boolean(this.duoWorkflowData?.repositoryEmpty);
    },
    projectWebPath() {
      return this.duoWorkflowData.webPath;
    },
    renderMode() {
      const isButton = this.renderAs === RENDER_AS_BUTTON;
      const isDropdownItem = this.renderAs === RENDER_AS_DROPDOWN_ITEM;
      const canRun = this.canStartFlow && !this.isRepositoryEmpty;

      const conditions = {
        [MODE_BUTTON]: isButton && canRun,
        [MODE_UNAVAILABLE]: isButton && this.isFlowUnavailable,
        [MODE_REPOSITORY_REQUIRED]: isButton && this.canStartFlow && this.isRepositoryEmpty,
        [MODE_DROPDOWN_ITEM]: isDropdownItem && canRun,
        [MODE_DROPDOWN_ITEM_UNAVAILABLE]: isDropdownItem && this.isFlowUnavailable,
      };

      return Object.keys(conditions).find((mode) => conditions[mode]) ?? MODE_NONE;
    },
  },
  apollo: {
    duoWorkflowData: {
      query: getDuoWorkflowStatusCheck,
      variables() {
        return {
          projectPath: this.projectPath,
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      skip() {
        return !this.projectPath;
      },
      update(data) {
        if (data.project) {
          const { id, webPath, duoWorkflowStatusCheck, repository } = data.project;

          return {
            isDuoActionEnabled: this.duoActionEnabledFromStatusCheck(duoWorkflowStatusCheck),
            remoteFlowsEnabled: duoWorkflowStatusCheck?.remoteFlowsEnabled,
            projectId: getIdFromGraphQLId(id),
            projectGid: id,
            webPath,
            repositoryEmpty:
              Boolean(duoWorkflowStatusCheck) && (!repository || Boolean(repository.empty)),
          };
        }
        return null;
      },
      error(error) {
        createAlert({
          message: error?.message || INIT_ERROR_MESSAGE,
          captureError: true,
          error,
        });
      },
    },
    aiCatalogItemConsumerId: {
      query: getConfiguredFlows,
      variables() {
        return {
          projectId: this.projectGid,
          foundationalFlowReference: this.workflowDefinition,
        };
      },
      context: {
        featureCategory: 'ai_catalog_curation',
      },
      skip() {
        return !this.projectGid || !this.workflowDefinition;
      },
      update(data) {
        const configuredItems = data.aiCatalogConfiguredItems?.nodes || [];
        if (configuredItems.length > 0) {
          return data.aiCatalogConfiguredItems.nodes[0].id;
        }

        return null;
      },
      result({ data, error }) {
        this.hasLoadedConfiguredFlows = Boolean(data) && !error;
      },
      error(error) {
        createAlert({
          message: error?.message || INIT_ERROR_MESSAGE,
          captureError: true,
          error,
        });
      },
    },
  },
  methods: {
    duoActionEnabledFromStatusCheck(duoWorkflowStatusCheck) {
      if (duoWorkflowStatusCheck) {
        const { enabled, createDuoWorkflowForCiAllowed } = duoWorkflowStatusCheck;

        return enabled && createDuoWorkflowForCiAllowed !== false;
      }
      return false;
    },
    startWorkflow() {
      if (this.isStartingFlow || !this.canStartFlow) return;

      if (this.promptValidatorRegex && !this.promptValidatorRegex.test(this.goal)) {
        this.$emit('prompt-validation-error', this.goal);
        return;
      }

      const requestData = {
        project_id: this.projectId,
        start_workflow: true,
        goal: this.goal,
        environment: FLOW_WEB_ENVIRONMENT,
        workflow_definition: this.workflowDefinition,
        agent_privileges: this.agentPrivileges,
        additional_context: this.additionalContext,
      };

      if (this.source) {
        requestData.source = this.source;
      }

      if (this.aiCatalogItemConsumerId) {
        requestData.ai_catalog_item_consumer_id = getIdFromGraphQLId(this.aiCatalogItemConsumerId);
      }

      if (this.sourceBranch) {
        requestData.source_branch = this.sourceBranch;
      } else if (this.currentRef) {
        requestData.source_branch = this.currentRef;
      }

      if (this.workItemIid) {
        requestData.issue_id = this.workItemIid;
      }

      if (this.mergeRequestId) {
        requestData.merge_request_id = this.mergeRequestId;
      }

      this.isStartingFlow = true;
      this.$emit('triggering');

      axios
        .post(this.duoWorkflowInvokePath, requestData)
        .then(({ data }) => {
          if (data.workload && !data.workload.id && data.workload.message) {
            throw new Error(data.workload.message);
          }

          this.$emit('agent-flow-started', data);

          eventHub.$emit(SHOW_SESSION, data);
        })
        .catch((error) => {
          const errorMessage =
            error.response?.data?.message ||
            s__('DuoAgentPlatform|Error occurred when starting the flow.');

          createAlert({
            message: errorMessage,
            captureError: true,
            error,
            renderMessageHTML: true,
          });
        })
        .finally(() => {
          this.isStartingFlow = false;
          this.$emit('triggered');
        });
    },
  },
  dropdownItemExtraAttrs: {
    text: __('Duo workflow'),
    extraAttrs: { class: '!gl-whitespace-nowrap' },
  },
  unavailableDropdownItem: {
    text: __('Duo workflow'),
    extraAttrs: { class: '!gl-whitespace-nowrap', 'aria-disabled': 'true' },
  },
  MODE_BUTTON,
  MODE_UNAVAILABLE,
  MODE_REPOSITORY_REQUIRED,
  MODE_DROPDOWN_ITEM,
  MODE_DROPDOWN_ITEM_UNAVAILABLE,
};
</script>
<template>
  <gl-button
    v-if="renderMode === $options.MODE_BUTTON"
    v-gl-tooltip.hover.focus.viewport="{ placement: 'top' }"
    :category="category"
    icon="tanuki-ai"
    :loading="isStartingFlow"
    :title="hoverMessage"
    :size="size"
    :variant="variant"
    data-testid="duo-workflow-action-button"
    @click="startWorkflow"
    ><template v-if="glSlots().default" #default><slot></slot></template
  ></gl-button>
  <flow-unavailable-button
    v-else-if="renderMode === $options.MODE_UNAVAILABLE"
    :message="disabledFlowMessage"
    :help-path="disabledFlowHelpPath"
    :size="size"
    :variant="variant"
    :category="category"
    ><template v-if="glSlots().default" #default><slot></slot></template
  ></flow-unavailable-button>
  <repository-required-button
    v-else-if="renderMode === $options.MODE_REPOSITORY_REQUIRED"
    :project-web-path="projectWebPath"
    :size="size"
    :variant="variant"
    :category="category"
    ><template v-if="glSlots().default" #default><slot></slot></template
  ></repository-required-button>
  <gl-disclosure-dropdown-item
    v-else-if="renderMode === $options.MODE_DROPDOWN_ITEM"
    :item="$options.dropdownItemExtraAttrs"
    @action="startWorkflow"
  >
    <template #list-item>
      <span class="gl-new-dropdown-item-icon"><gl-icon name="tanuki-ai" variant="current" /></span>
      <slot></slot>
    </template>
  </gl-disclosure-dropdown-item>
  <gl-disclosure-dropdown-item
    v-else-if="renderMode === $options.MODE_DROPDOWN_ITEM_UNAVAILABLE"
    ref="unavailableItem"
    :item="$options.unavailableDropdownItem"
    disabled
  >
    <template #list-item>
      <span class="gl-new-dropdown-item-icon"><gl-icon name="tanuki-ai" variant="current" /></span>
      <slot></slot>
      <gl-popover
        :target="() => $refs.unavailableItem && $refs.unavailableItem.$el"
        triggers="hover focus"
        placement="left"
        boundary="viewport"
      >
        <p class="gl-mb-0">
          {{ disabledFlowMessage }}
          <template v-if="disabledFlowHelpPath">
            <gl-link :href="disabledFlowHelpPath" target="_blank">{{ __('Learn more') }}</gl-link
            >.
          </template>
        </p>
      </gl-popover>
    </template>
  </gl-disclosure-dropdown-item>
</template>
