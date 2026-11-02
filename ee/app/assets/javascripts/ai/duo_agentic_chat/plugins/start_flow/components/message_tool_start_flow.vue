<script>
import { GlAnimatedLoaderIcon, GlIcon, GlLink, GlLoadingIcon } from '@gitlab/ui';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import TodoChecklist from 'ee/ai/duo_agents_platform/components/common/todo_checklist.vue';
import {
  formatAgentDefinition,
  formatSessionLabel,
  getMessageData,
} from 'ee/ai/duo_agents_platform/utils';
import { parseToolInfo } from 'ee/ai/duo_agents_platform/icon_utils';
import getWorkflowLatestCheckpointQuery from 'ee/ai/graphql/get_workflow_latest_checkpoint.query.graphql';
import getWorkflowStatusQuery from 'ee/ai/graphql/get_workflow_status.query.graphql';
import workflowActivityUpdatedSubscription from 'ee/ai/graphql/workflow_activity_updated.subscription.graphql';
import { fetchPolicies } from '~/lib/graphql';
import { s__ } from '~/locale';
import { truncate } from '~/lib/utils/text_utility';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { EventsTracker } from 'ee/ai/duo_agentic_chat/observability/events_tracker';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import { WorkflowUtils } from 'ee/ai/duo_agentic_chat/utils/workflow_utils';

// Updates arrive over the `workflowEventsUpdated` subscription. Polling only catches
// events missed while the websocket was disconnected.
const POLL_INTERVAL = 60000;
// The subscription stays closed after an error, so polling takes over.
const FALLBACK_POLL_INTERVAL = 10000;
const TERMINAL_STATUSES = ['FINISHED', 'FAILED', 'STOPPED'];
const ACTIVITY_DETAIL_MAX_LENGTH = 140;
const isTerminalStatus = (status) => TERMINAL_STATUSES.includes(status);

const HOVER_CLASSES = ['gl-transition-colors', 'hover:gl-border-strong', 'active:gl-focus'];

const PILL_CLASSES = [
  'gl-border',
  'gl-inline-flex',
  '!gl-w-fit',
  'gl-items-center',
  'gl-gap-2',
  'gl-rounded-r-2xl',
  'gl-rounded-tl-2xl',
  'gl-border-default',
  'gl-bg-default',
  'gl-p-4',
  ...HOVER_CLASSES,
];

const EXPANDED_CARD_CLASSES = [
  'gl-flex',
  'gl-w-full',
  'gl-flex-col',
  'gl-gap-3',
  'gl-rounded-r-2xl',
  'gl-rounded-tl-2xl',
  'gl-border',
  'gl-border-default',
  'gl-bg-default',
  'gl-p-4',
  ...HOVER_CLASSES,
];

// GlLink applies link colour and underline; the card should keep its own text styling.
const LINK_CLASSES = ['!gl-text-default', '!gl-no-underline'];

export default {
  PILL_CLASSES,
  name: 'MessageToolStartFlow',
  components: {
    AgentStatusIcon,
    GlAnimatedLoaderIcon,
    GlIcon,
    GlLink,
    GlLoadingIcon,
    TodoChecklist,
  },
  apollo: {
    // Reads only the status and the last message. The full checkpoint is unbounded, so
    // it is read once on load and once on finish, to recover a plan the updates missed.
    // no-cache keeps this partial latestCheckpoint from replacing the session panel's copy.
    // eslint-disable-next-line @gitlab/vue-no-undef-apollo-properties -- manual, sets data itself
    workflowStatusQuery: {
      query: getWorkflowStatusQuery,
      fetchPolicy: fetchPolicies.NO_CACHE,
      variables() {
        return this.queryVariables;
      },
      skip() {
        return !this.workflowId;
      },
      pollInterval() {
        if (this.isTerminal || this.isPageHidden) return 0;
        return this.subscriptionFailed ? FALLBACK_POLL_INTERVAL : POLL_INTERVAL;
      },
      manual: true,
      result({ data }) {
        const [workflow] = data?.duoWorkflowWorkflows?.nodes ?? [];
        this.sessionTitle = workflow?.title ?? '';
        this.sessionDefinition = workflow?.workflowDefinition ?? '';
        this.applyWorkflowUpdate({
          status: WorkflowUtils.parseWorkflowStatus(data),
          lastDuoMessage: workflow?.latestCheckpoint?.lastDuoMessage ?? null,
        });
      },
    },
    $subscribe: {
      // eslint-disable-next-line @gitlab/vue-no-undef-apollo-properties
      workflowEvents: {
        query: workflowActivityUpdatedSubscription,
        fetchPolicy: fetchPolicies.NO_CACHE,
        variables() {
          return this.queryVariables;
        },
        skip() {
          // Waits for the first status, so a finished flow never subscribes. Under Vue 3,
          // @vue/apollo-option resubscribes after an error unless this returns true.
          return !this.workflowStatus || this.isTerminal || this.subscriptionFailed;
        },
        result({ data }) {
          const event = data?.workflowEventsUpdated;
          // An event published before the first checkpoint carries no message.
          this.applyWorkflowUpdate({
            status: event?.workflowStatus ?? this.workflowStatus,
            lastDuoMessage: event?.lastDuoMessage ?? this.latestMessage,
          });
        },
        error(error) {
          captureExceptionForDuoChat(error);
          this.subscriptionFailed = true;
        },
      },
    },
  },
  props: {
    message: {
      required: true,
      type: Object,
    },
  },
  data() {
    return {
      workflowStatus: '',
      sessionTitle: '',
      sessionDefinition: '',
      latestMessage: null,
      flowPlan: null,
      planVersion: 0,
      hasFetchedPlan: false,
      subscriptionFailed: false,
      isPageHidden: document.hidden,
    };
  },
  computed: {
    toolResponse() {
      try {
        return JSON.parse(this.message.tool_info?.tool_response?.content ?? '{}');
      } catch {
        return {};
      }
    },
    flowName() {
      return this.toolResponse.flow_name ?? '';
    },
    workflowId() {
      return this.toolResponse.workflow_id ?? null;
    },
    queryVariables() {
      return { workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this.workflowId) };
    },
    sessionUrl() {
      return this.toolResponse.session_url ?? null;
    },
    label() {
      if (!this.workflowId) return formatAgentDefinition(this.flowName);

      return formatSessionLabel({
        title: this.sessionTitle,
        agentDefinition: this.sessionDefinition,
        flowName: this.flowName,
        id: this.workflowId,
      });
    },
    toolName() {
      return this.message.tool_info?.name ?? '';
    },
    humanStatus() {
      return (this.workflowStatus ?? '').toLowerCase().replaceAll('_', ' ');
    },
    hasPlan() {
      return Boolean(this.flowPlan);
    },
    isTerminal() {
      return isTerminalStatus(this.workflowStatus);
    },
    latestActivity() {
      if (!this.latestMessage) return null;
      return getMessageData(this.latestMessage)?.title ?? null;
    },
    activityTitle() {
      return this.latestActivity ?? s__('DuoAgenticChat|Starting the session. Please wait');
    },
    activityDetail() {
      const content = this.latestMessage?.content?.trim();
      return content ? truncate(content, ACTIVITY_DETAIL_MAX_LENGTH) : '';
    },
    toolInfoName() {
      return parseToolInfo(this.latestMessage?.toolInfo)?.name ?? '';
    },
    showActivity() {
      return !this.hasPlan && !this.isTerminal;
    },
    isExpanded() {
      return this.hasPlan || this.showActivity;
    },
    isLoading() {
      return Boolean(this.workflowId) && !this.workflowStatus;
    },
    linkComponent() {
      return this.sessionUrl ? GlLink : 'button';
    },
    linkAttributes() {
      return this.sessionUrl ? { href: this.sessionUrl } : { type: 'button' };
    },
    wrapperProps() {
      const baseClasses = this.isExpanded ? EXPANDED_CARD_CLASSES : PILL_CLASSES;
      return {
        class: this.sessionUrl ? [...baseClasses, ...LINK_CLASSES] : baseClasses,
      };
    },
  },
  mounted() {
    document.addEventListener('visibilitychange', this.handleVisibilityChange);
    // Catches up on events missed while the websocket was down, without waiting for a poll.
    document.addEventListener('actioncable:reconnected', this.refetchStatus);
  },
  beforeDestroy() {
    document.removeEventListener('visibilitychange', this.handleVisibilityChange);
    document.removeEventListener('actioncable:reconnected', this.refetchStatus);
  },
  methods: {
    applyWorkflowUpdate({ status, lastDuoMessage }) {
      // A terminal status is final. This drops a poll that was in flight when the
      // subscription reported the finish.
      if (this.isTerminal) return;

      this.workflowStatus = status;
      this.latestMessage = lastDuoMessage;

      const latestTodo = this.latestMessage
        ? WorkflowUtils.findLatestTodoToolInfo(
            WorkflowUtils.normalizeDuoMessages([this.latestMessage]),
          )
        : null;
      if (latestTodo) {
        this.flowPlan = latestTodo;
        this.planVersion += 1;
      }

      if (!this.hasFetchedPlan || this.isTerminal) {
        this.fetchFlowPlan();
      }
    },
    handleVisibilityChange() {
      this.isPageHidden = document.hidden;
      this.refetchStatus();
    },
    refetchStatus() {
      if (!this.workflowId || this.isTerminal || this.isPageHidden) return;
      this.$apollo.queries.workflowStatusQuery.refetch();
    },
    async fetchFlowPlan(isRetry = false) {
      this.hasFetchedPlan = true;
      this.planVersion += 1;
      const version = this.planVersion;
      try {
        const { data } = await this.$apollo.query({
          query: getWorkflowLatestCheckpointQuery,
          variables: this.queryVariables,
          fetchPolicy: fetchPolicies.NO_CACHE,
        });
        // A newer plan from an update or a later fetch has already replaced this one.
        if (version !== this.planVersion) return;

        const messages = WorkflowUtils.parseWorkflowData(data)?.duoMessages ?? [];
        this.flowPlan =
          WorkflowUtils.findLatestTodoToolInfo(WorkflowUtils.normalizeDuoMessages(messages)) ??
          this.flowPlan;
      } catch (error) {
        captureExceptionForDuoChat(error);
        if (version !== this.planVersion) return;

        // Keep the plan the updates collected. A running flow retries on its next update,
        // but a finished one gets no more updates, so its final read is retried once here.
        this.hasFetchedPlan = false;
        if (this.isTerminal && !isRetry) this.fetchFlowPlan(true);
      }
    },
    openSession(event) {
      EventsTracker.trackClickThroughFlowWidget({ toolName: this.toolName });
      // Only a real link has a browser default to hand the modifier click to.
      if (this.sessionUrl && (event.metaKey || event.ctrlKey || event.shiftKey)) return;
      if (!this.workflowId) return;

      event.preventDefault();
      eventHub.$emit(SHOW_SESSION, { id: this.workflowId });
    },
  },
};
</script>

<template>
  <div
    v-if="isLoading"
    :class="$options.PILL_CLASSES"
    class="gl-justify-center"
    data-testid="start-flow-loading"
  >
    <gl-loading-icon size="sm" inline />
  </div>
  <component
    :is="linkComponent"
    v-else
    class="gl-text-left"
    v-bind="{ ...linkAttributes, ...wrapperProps }"
    data-testid="start-flow-message"
    @click="openSession"
  >
    <div class="gl-flex gl-items-start gl-justify-center gl-gap-2">
      <span
        class="gl-mt-1 gl-flex gl-h-5 gl-w-5 gl-shrink-0 gl-translate-y-px gl-items-center gl-justify-center"
        aria-hidden="true"
      >
        <agent-status-icon :status="workflowStatus" :human-status="humanStatus" />
      </span>
      <span class="gl-ml-2" :class="{ 'gl-flex-1': isExpanded && sessionUrl }">
        {{ label }}
        <strong>{{ humanStatus }}</strong>
      </span>
      <gl-icon
        v-if="sessionUrl"
        name="chevron-right"
        class="gl-mt-1 gl-shrink-0 gl-translate-y-px"
        aria-hidden="true"
      />
    </div>
    <todo-checklist
      v-if="hasPlan"
      :tool-info="flowPlan"
      :flow-finished="isTerminal"
      :bordered="false"
    />
    <div
      v-else-if="showActivity"
      class="gl-border-t -gl-mx-4 -gl-mb-4 gl-rounded-br-2xl gl-border-default gl-bg-subtle gl-px-4 gl-pb-4 gl-pt-3"
      data-testid="latest-activity"
    >
      <div class="gl-flex gl-items-center gl-gap-2">
        <strong class="gl-text-strong">{{ activityTitle }}</strong>
        <gl-animated-loader-icon is-on class="gl-shrink-0" />
      </div>
      <p
        v-if="activityDetail"
        class="gl-m-0 gl-mt-1 gl-text-subtle gl-wrap-anywhere"
        data-testid="latest-activity-detail"
      >
        <template v-if="toolInfoName"
          ><span data-testid="latest-activity-tool-name">{{ toolInfoName }}</span>
          <span aria-hidden="true">—</span> </template
        >{{ activityDetail }}
      </p>
    </div>
  </component>
</template>
