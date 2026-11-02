<script>
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { convertToGraphQLId, getIdFromGraphQLId } from '~/graphql_shared/utils';
import { getAgentFlow } from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow.query.graphql';
import getAgentFlowLinkedItems from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow_linked_items.query.graphql';
import {
  DUO_AGENT_PLATFORM_POLLING_INTERVAL,
  WORKFLOW_TERMINAL_STATUSES,
  STALE_ROUTE_ERROR_CODES,
  SIDE_PANEL_ROUTE_CONTEXT,
} from 'ee/ai/duo_agents_platform/constants';
import { clearRouteState, getStorageKey } from 'ee/ai/duo_agents_platform/utils/navigation_state';
import { safeRouterPush } from 'ee/ai/duo_agents_platform/utils/router_utils';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import {
  formatAgentDefinition,
  formatAgentFlowTitle,
  formatAgentStatus,
} from 'ee/ai/duo_agents_platform/utils';
import { cancelWorkflow, restartWorkflow } from 'ee/rest_api';
import { setAgentSessionStatus, setPanelTitle } from 'ee/ai/graphql';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import AgentFlowDetails from './components/agent_flow_details.vue';
import AgentFlowCancelationModal from './components/agent_flow_cancelation_modal.vue';

export default {
  name: 'DuoAgentsPlatformShow',
  components: {
    AgentFlowDetails,
    AgentFlowCancelationModal,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    isFlyout: { default: false },
    isSidePanelView: { default: false },
  },
  provide() {
    return {
      lastExecutorLogUrl: () => this.agentFlow?.lastExecutorLogsUrl || '',
    };
  },
  data() {
    return {
      agentFlow: null,
      linkedItems: null,
      showCancelConfirmation: false,
      isCancelling: false,
      isRetrying: false,
      canPoll: true,
    };
  },
  apollo: {
    agentFlow: {
      query: getAgentFlow,
      pollInterval: DUO_AGENT_PLATFORM_POLLING_INTERVAL,
      variables() {
        return {
          workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this.$route.params.id),
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.[0]?.node || {};
      },
      result() {
        if (this.isSidePanelView) {
          setAgentSessionStatus(this.agentFlow?.status);
          setPanelTitle(
            formatAgentFlowTitle(this.agentFlow?.title, this.agentFlow?.workflowDefinition),
          );
        }

        if (WORKFLOW_TERMINAL_STATUSES.includes(this.agentFlow?.status)) {
          this.stopPolling();
        }
      },
      error(err) {
        const hasStaleRouteError = (err?.graphQLErrors || []).some((e) =>
          STALE_ROUTE_ERROR_CODES.includes(e?.extensions?.code),
        );

        if (hasStaleRouteError) {
          this.stopPolling();

          if (this.isSidePanelView) {
            clearRouteState(getStorageKey(SIDE_PANEL_ROUTE_CONTEXT));
          }
        }

        createAlert({
          message:
            err?.message ||
            s__('DuoAgentsPlatform|Something went wrong while fetching Agent Flows'),
          captureError: true,
        });
      },
    },
    linkedItems: {
      query: getAgentFlowLinkedItems,
      pollInterval: DUO_AGENT_PLATFORM_POLLING_INTERVAL,
      variables() {
        return {
          workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this.$route.params.id),
        };
      },
      context: {
        featureCategory: 'duo_agent_platform',
      },
      update(data) {
        return data?.duoWorkflowWorkflows?.edges?.[0]?.node || {};
      },
      error(err) {
        Sentry.captureException(err);
      },
    },
  },
  computed: {
    isLoading() {
      const loadedId = getIdFromGraphQLId(this.agentFlow?.id);
      return (
        this.$apollo.queries.agentFlow.loading && String(loadedId) !== String(this.$route.params.id)
      );
    },
    agentFlowDetailsProps() {
      return {
        isLoading: this.isLoading,
        status: this.agentFlow?.status || '',
        humanStatus: formatAgentStatus(this.agentFlow?.humanStatus),
        title: formatAgentFlowTitle(this.agentFlow?.title, this.agentFlow?.workflowDefinition),
        agentFlowDefinition:
          this.agentFlow?.aiCatalogItem?.name ||
          formatAgentDefinition(this.agentFlow?.workflowDefinition),
        modelName: this.agentFlow?.modelMetadataName || '',
        modelIdentifier: this.agentFlow?.modelMetadataIdentifier || '',
        flowVersion: this.agentFlow?.flowMetadataVersion || '',
        aiCatalogItemPath: this.agentFlow?.aiCatalogItem?.webPath || '',
        duoMessages: this.agentFlow?.latestCheckpoint?.duoMessages || [],
        allExecutorUrls: this.agentFlow?.allExecutorLogsUrls || [],
        createdAt: this.agentFlow?.createdAt || '',
        updatedAt: this.agentFlow?.updatedAt || '',
        project: this.agentFlow?.project || {},
        user: this.agentFlow?.user || {},
        workflowId: this.$route.params.id?.toString() || '',
        canUpdateWorkflow: this.agentFlow?.userPermissions?.updateDuoWorkflow || false,
        canResumeWorkflow: this.agentFlow?.userPermissions?.resumeDuoWorkflow || false,
        canRestartWorkflow: this.agentFlow?.userPermissions?.restartDuoWorkflow || false,
        isRetrying: this.isRetrying,
        summary: this.agentFlow?.summary || '',
        workItem: this.agentFlow?.workItem ?? null,
        mergeRequest: this.agentFlow?.mergeRequest ?? null,
        workItemLinks: this.linkedItems?.workItemLinks?.nodes || [],
        mergeRequestLinks: this.linkedItems?.mergeRequestLinks?.nodes || [],
        noteLinks: this.linkedItems?.noteLinks?.nodes || [],
        pipelineLinks: this.linkedItems?.pipelineLinks?.nodes || [],
      };
    },
  },
  watch: {
    '$route.params.id': function resetPolling() {
      this.canPoll = true;

      if (this.glFeatures.dapSessionDetailsPolling && document.hidden) {
        this.$nextTick(this.onVisibilityChange);
      }
    },
  },
  mounted() {
    if (!this.glFeatures.dapSessionDetailsPolling) return;

    document.addEventListener('visibilitychange', this.onVisibilityChange);
    if (document.hidden) this.onVisibilityChange();
  },
  beforeDestroy() {
    document.removeEventListener('visibilitychange', this.onVisibilityChange);

    // Clear the panel title/subtitle/status reactive vars so the next mount
    // (e.g. returning to this route for the same workflow) is guaranteed to
    // produce a value change in `result()` and re-emit through Apollo. Without
    // this, Apollo's `makeVar` skips notifying subscribers when the new value
    // matches the previous one, leaving the panel header stuck in its
    // loading state.
    if (this.isSidePanelView) {
      setAgentSessionStatus(null);
      setPanelTitle(null);
    }
  },
  methods: {
    pausePolling() {
      this.$apollo.queries.agentFlow.stopPolling();
      this.$apollo.queries.linkedItems.stopPolling();
    },
    stopPolling() {
      this.canPoll = false;
      this.pausePolling();
    },
    onVisibilityChange() {
      if (document.hidden) {
        this.pausePolling();
        return;
      }

      if (!this.canPoll) return;

      const { agentFlow, linkedItems } = this.$apollo.queries;
      [agentFlow, linkedItems].forEach((query) => {
        query.refetch().catch(() => {});
        query.startPolling(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
      });
    },
    async confirmCancelSession() {
      this.isCancelling = true;
      this.showCancelConfirmation = false;

      try {
        await cancelWorkflow(this.$route.params.id);

        createAlert({
          message: s__('DuoAgentsPlatform|Session has been canceled successfully.'),
          variant: 'success',
        });
      } catch (error) {
        const errorMessage =
          error.response?.data?.message ||
          s__('DuoAgentsPlatform|Failed to cancel session. Please try again.');

        createAlert({
          message: errorMessage,
          captureError: true,
          error,
          variant: 'danger',
        });

        return;
      } finally {
        this.isCancelling = false;
      }

      await this.$apollo.queries.agentFlow.refetch().catch(() => {});
    },
    async retrySession() {
      this.isRetrying = true;

      let newWorkflowId;

      try {
        const { data } = await restartWorkflow(this.$route.params.id);

        newWorkflowId = data.id;
      } catch (error) {
        this.isRetrying = false;

        createAlert({
          message:
            error.response?.data?.message ||
            s__('DuoAgentPlatform|Failed to retry session. Please try again.'),
          captureError: true,
          error,
          variant: 'danger',
        });

        return;
      }

      try {
        await safeRouterPush(
          this.$router,
          { name: AGENTS_PLATFORM_SHOW_ROUTE, params: { id: String(newWorkflowId) } },
          { component: 'DuoAgentsPlatformShow' },
        );

        createAlert({
          message: s__('DuoAgentPlatform|Session has been restarted successfully.'),
          variant: 'success',
        });
      } catch {
        createAlert({
          message: s__(
            'DuoAgentPlatform|Session restarted, but the new session could not be opened.',
          ),
          variant: 'warning',
        });
      } finally {
        this.isRetrying = false;
      }
    },
  },
};
</script>
<template>
  <div>
    <agent-flow-details
      :class="isFlyout ? 'gl-mx-3' : ''"
      v-bind="agentFlowDetailsProps"
      @cancel-session="showCancelConfirmation = true"
      @retry-session="retrySession"
    />

    <agent-flow-cancelation-modal
      :visible="showCancelConfirmation"
      :loading="isCancelling"
      @hide="showCancelConfirmation = false"
      @confirm="confirmCancelSession"
    />
  </div>
</template>
