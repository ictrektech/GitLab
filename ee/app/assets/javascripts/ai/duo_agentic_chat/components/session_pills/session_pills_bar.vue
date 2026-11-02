<script>
import { GlCollapse, GlDisclosureDropdown, GlIcon, GlResizeObserverDirective } from '@gitlab/ui';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { convertToGraphQLId, getIdFromGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import getWorkflowsByIdsQuery from 'ee/ai/graphql/get_workflows_by_ids.query.graphql';
import workflowStatusUpdatedSubscription from 'ee/ai/graphql/workflow_status_updated.subscription.graphql';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';
import { cancelWorkflow } from 'ee/rest_api';
import { formatSessionLabel, formatSessionTooltip } from 'ee/ai/duo_agents_platform/utils';
import AgentFlowCancelationModal from 'ee/ai/duo_agents_platform/pages/show/components/agent_flow_cancelation_modal.vue';
import {
  MESSAGE_SUB_TYPE_START_FLOW,
  WORKFLOW_TERMINAL_STATUSES,
  WORKFLOW_AWAITING_INPUT_STATUSES,
} from 'ee/ai/duo_agents_platform/constants';
import SessionPill from './session_pill.vue';
import { getStatusDotClass } from './utils';
import { POLL_INTERVAL_MS, OVERFLOW_RESERVE_PX } from './constants';

const isTerminal = (workflow) =>
  WORKFLOW_TERMINAL_STATUSES.includes(workflow.status?.toUpperCase());

export default {
  name: 'SessionPillsBar',
  components: {
    AgentFlowCancelationModal,
    GlCollapse,
    GlDisclosureDropdown,
    GlIcon,
    SessionPill,
  },
  directives: {
    GlResizeObserver: GlResizeObserverDirective,
  },
  apollo: {
    activeWorkflows: {
      query: getWorkflowsByIdsQuery,
      variables() {
        return { ids: this.pollableWorkflowIds };
      },
      // Flows in a terminal status are not polled again. FAILED and STOPPED flows can be retried
      // in place, but that is unlikely for chat-started flows, so polling stops once none are left.
      skip() {
        return this.pollableWorkflowIds.length === 0;
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      pollInterval: POLL_INTERVAL_MS,
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.map((edge) => edge.node) ?? [];
      },
      result({ data }) {
        const workflows = (data?.duoWorkflowWorkflows?.edges ?? []).map((edge) => edge.node);
        const finishedIds = workflows
          .filter(isTerminal)
          .map((workflow) => workflow.id)
          .filter((id) => !this.finishedWorkflowIds.includes(id));

        if (finishedIds.length) {
          this.finishedWorkflowIds.push(...finishedIds);
        }

        this.syncStatusSubscriptions(workflows.filter((workflow) => !isTerminal(workflow)));
      },
    },
  },
  props: {
    messages: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['height-change'],
  data() {
    return {
      activeWorkflows: [],
      finishedWorkflowIds: [],
      containerWidth: 0,
      pillWidths: [],
      cancelWorkflowId: null,
      isCancelling: false,
      moreSessionsLabel: s__('DuoAgenticChat|More active sessions'),
    };
  },
  computed: {
    chatWorkflows() {
      return this.messages.reduce((map, message) => {
        if (message?.message_sub_type !== MESSAGE_SUB_TYPE_START_FLOW) return map;

        let payload;
        try {
          payload = JSON.parse(message?.tool_info?.tool_response?.content ?? '{}');
        } catch {
          return map;
        }

        const workflowId = Number(payload.workflow_id);
        const flowName = payload.flow_name;
        if (!workflowId || !flowName) return map;

        map.set(workflowId, { workflowId, flowName });
        return map;
      }, new Map());
    },
    chatWorkflowIds() {
      return Array.from(this.chatWorkflows.keys()).map((id) =>
        convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, id),
      );
    },
    pollableWorkflowIds() {
      return this.chatWorkflowIds.filter((id) => !this.finishedWorkflowIds.includes(id));
    },
    visiblePills() {
      const pills = this.activeWorkflows.flatMap((workflow) => {
        if (isTerminal(workflow)) return [];

        const status = workflow.status?.toUpperCase();

        // The query already returns only the ids we asked for. `flowName`
        // still comes from the chat message so the pill label is meaningful
        // even when the server response is minimal.
        const workflowId = Number(getIdFromGraphQLId(workflow.id));
        const fromChat = this.chatWorkflows.get(workflowId);
        if (!fromChat) return [];

        return [
          {
            workflowId,
            label: formatSessionLabel({
              title: workflow.title,
              agentDefinition: workflow.workflowDefinition,
              flowName: fromChat.flowName,
              id: workflowId,
            }),
            tooltip: formatSessionTooltip({
              title: workflow.title,
              agentDefinition: workflow.workflowDefinition,
              flowName: fromChat.flowName,
              id: workflowId,
            }),
            status,
          },
        ];
      });

      // Surface workflows waiting on the user (e.g. INPUT_REQUIRED) ahead of
      // anything else so they stay visible when the row overflows.
      return pills.sort((a, b) => {
        const aAwaiting = WORKFLOW_AWAITING_INPUT_STATUSES.includes(a.status);
        const bAwaiting = WORKFLOW_AWAITING_INPUT_STATUSES.includes(b.status);
        if (aAwaiting === bAwaiting) return 0;
        return aAwaiting ? -1 : 1;
      });
    },
    hasPills() {
      return this.visiblePills.length > 0;
    },
    visibleCount() {
      const { visiblePills, containerWidth, pillWidths: widths } = this;

      // Bootstrap: before the first ResizeObserver tick (or before pills have
      // been measured) we render all pills so `measurePills` has DOM nodes to
      // size. The next tick fills `pillWidths` and re-evaluates this getter
      // to collapse overflow into the dropdown — a deliberate two-pass render.
      if (!containerWidth || visiblePills.length === 0 || widths.length === 0) {
        return visiblePills.length;
      }

      let total = 0;
      let count = 0;
      for (let i = 0; i < visiblePills.length; i += 1) {
        const width = widths[i] ?? widths[widths.length - 1];
        const reserve = i < visiblePills.length - 1 ? OVERFLOW_RESERVE_PX : 0;
        if (total + width + reserve > containerWidth) break;
        total += width;
        count += 1;
      }
      return Math.max(count, 1);
    },
    renderedPills() {
      return this.visiblePills.slice(0, this.visibleCount);
    },
    overflowPills() {
      return this.visiblePills.slice(this.visibleCount);
    },
    overflowItems() {
      return this.overflowPills.map((pill) => ({
        text: pill.label,
        action: () => this.openSession(pill.workflowId),
        extraAttrs: {
          'data-workflow-id': pill.workflowId,
        },
        statusDotClass: getStatusDotClass(pill.status),
      }));
    },
  },
  watch: {
    pollableWorkflowIds(ids) {
      // A skipped query never reaches `result`, so close its subscriptions here.
      if (!ids.length) this.syncStatusSubscriptions([]);
    },
    visiblePills() {
      this.$nextTick(() => {
        this.measurePills();
      });
    },
  },
  // Not `created`: vue-apollo starts queries from a global mixin's `created`, which runs first,
  // and a cached result calls `result`, which uses this map, synchronously.
  beforeCreate() {
    this.statusSubscriptions = new Map();
  },
  methods: {
    // Subscribed through the client rather than `subscribeToMore`: vue-apollo replaces the
    // query's observer whenever its ids change, which would drop those subscriptions.
    syncStatusSubscriptions(workflows) {
      const workflowIds = workflows.map((workflow) => workflow.id);

      this.statusSubscriptions.forEach((subscription, workflowId) => {
        if (workflowIds.includes(workflowId)) return;

        subscription.unsubscribe();
        this.statusSubscriptions.delete(workflowId);
      });

      workflows
        .filter((workflow) => !this.statusSubscriptions.has(workflow.id))
        .forEach((workflow) => {
          const subscription = this.$apollo
            .subscribe({
              query: workflowStatusUpdatedSubscription,
              variables: { workflowId: workflow.id },
            })
            .subscribe({
              next: ({ data }) =>
                this.updateWorkflowStatus(workflow, data?.workflowEventsUpdated?.workflowStatus),
              error: (error) => {
                Sentry.captureException(error);
                // A failed subscription is closed for good. Forget it, so the next poll result
                // that changes resubscribes it; until then the poll keeps the pill current.
                this.statusSubscriptions.delete(workflow.id);
              },
            });

          this.statusSubscriptions.set(workflow.id, subscription);
        });
    },
    updateWorkflowStatus(workflow, status) {
      if (!status) return;

      const { cache } = this.$apollo.getClient();
      cache.modify({ id: cache.identify(workflow), fields: { status: () => status } });
    },
    handleResize(entry) {
      this.containerWidth = entry.contentRect.width;
      this.measurePills();
    },
    measurePills() {
      const refs = this.$refs.pill;
      if (!refs?.length) {
        this.pillWidths = [];
        return;
      }

      this.pillWidths = refs.map((ref) => {
        const el = ref?.$el ?? ref;
        return el?.getBoundingClientRect?.().width ?? 0;
      });
    },
    openSession(workflowId) {
      eventHub.$emit(SHOW_SESSION, { id: workflowId });
    },
    async confirmCancelSession() {
      this.isCancelling = true;

      try {
        await cancelWorkflow(this.cancelWorkflowId);

        createAlert({
          message: s__('DuoAgentsPlatform|Session has been canceled successfully.'),
          variant: 'success',
        });

        this.$apollo.queries.activeWorkflows.refetch();
      } catch (error) {
        createAlert({
          message:
            error.response?.data?.message ||
            s__('DuoAgentsPlatform|Failed to cancel session. Please try again.'),
          captureError: true,
          error,
          variant: 'danger',
        });
      } finally {
        this.isCancelling = false;
        this.cancelWorkflowId = null;
      }
    },
  },
};
</script>

<template>
  <gl-collapse :visible="hasPills" @shown="$emit('height-change')" @hidden="$emit('height-change')">
    <div
      v-gl-resize-observer="handleResize"
      data-testid="session-pills-bar"
      class="gl-flex gl-min-h-7 gl-items-center gl-gap-2 gl-overflow-hidden gl-py-2"
    >
      <session-pill
        v-for="pill in renderedPills"
        ref="pill"
        :key="pill.workflowId"
        :ref-in-for="true"
        :workflow-id="pill.workflowId"
        :label="pill.label"
        :tooltip="pill.tooltip"
        :status="pill.status"
        @click="openSession"
        @cancel="cancelWorkflowId = $event"
      />
      <gl-disclosure-dropdown
        v-if="overflowPills.length"
        data-testid="session-pills-overflow"
        icon="ellipsis_h"
        category="tertiary"
        size="small"
        no-caret
        text-sr-only
        :toggle-text="moreSessionsLabel"
        :items="overflowItems"
      >
        <template #list-item="{ item }">
          <span class="gl-inline-flex gl-items-center gl-gap-2">
            <gl-icon
              name="status_created_borderless"
              class="gl-shrink-0"
              :class="item.statusDotClass"
            />
            <span>{{ item.text }}</span>
          </span>
        </template>
      </gl-disclosure-dropdown>
    </div>

    <agent-flow-cancelation-modal
      :visible="Boolean(cancelWorkflowId)"
      :loading="isCancelling"
      @hide="cancelWorkflowId = null"
      @confirm="confirmCancelSession"
    />
  </gl-collapse>
</template>
