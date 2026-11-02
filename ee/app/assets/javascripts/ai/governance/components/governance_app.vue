<script>
import { defineAsyncComponent } from 'vue';
import { GlEmptyState, GlTab, GlTabs } from '@gitlab/ui';
import EmptyAccessSvg from '@gitlab/svgs/dist/illustrations/empty-state/empty-access-md.svg?url';
import { s__ } from '~/locale';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import { InternalEvents } from '~/tracking';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';

const TABS = {
  DASHBOARD: {
    title: s__('AiGovernance|Dashboard'),
    queryParamValue: 'dashboard',
    trackingLabel: 'dashboard',
  },
  TOOL_MANAGEMENT: {
    title: s__('AiGovernance|Tool management'),
    queryParamValue: 'tool-management',
    trackingLabel: 'tool_management',
  },
  AGENT_ARTIFACTS: {
    title: s__('AiGovernance|Audit events'),
    queryParamValue: 'agent-artifacts',
    trackingLabel: 'audit_events',
  },
  MCP_REGISTRY: {
    title: s__('AiGovernance|MCP registry'),
    queryParamValue: 'mcp-registry',
    trackingLabel: 'mcp_registry',
  },
};

export default {
  TABS,
  EmptyAccessSvg,
  i18n: {
    noAccessTitle: s__("AiGovernance|You don't have access to this tab"),
    noAccessDescription: s__(
      'AiGovernance|To view this content, ask an administrator or a group Owner for access.',
    ),
  },
  name: 'GovernanceApp',
  components: {
    GlEmptyState,
    GlTabs,
    GlTab,
    PageHeading,
    AiGovernanceDashboardApp: defineAsyncComponent(
      () =>
        import(
          /* webpackChunkName: 'ai_governance_dashboard_app' */ './dashboard/dashboard_app.vue'
        ),
    ),
    AiToolManagementApp: defineAsyncComponent(
      () =>
        import(
          /* webpackChunkName: 'ai_tool_management_app' */ './ai_tool_management/ai_tool_management_app.vue'
        ),
    ),
    AgentArtifactsApp: defineAsyncComponent(
      () =>
        import(
          /* webpackChunkName: 'agent_artifacts_app' */ 'ee/agent_artifacts/components/agent_artifacts_app.vue'
        ),
    ),
    McpRegistryApp: defineAsyncComponent(
      () =>
        import(/* webpackChunkName: 'mcp_registry_app' */ './mcp_registry/mcp_registry_app.vue'),
    ),
  },
  mixins: [glFeatureFlagMixin(), InternalEvents.mixin()],
  inject: {
    permittedTabs: { default: () => [] },
  },
  data() {
    return {
      activeTabIndex: 0,
    };
  },
  computed: {
    showDashboardTab() {
      return this.glFeatures.aiGovernanceDashboard;
    },
    showAgentArtifactsTab() {
      return this.glFeatures.agentArtifactsPage;
    },
  },
  methods: {
    isPermitted(tab) {
      return this.permittedTabs.includes(tab.queryParamValue);
    },
    // Clicks only, so the tab opened from the URL on load is not counted.
    trackTabClick(tab) {
      this.trackEvent('click_tab_on_ai_governance_page', { label: tab.trackingLabel });
    },
  },
};
</script>

<template>
  <div>
    <page-heading :heading="s__('AiGovernance|AI Governance')">
      <template #description>
        {{ s__('AiGovernance|Control how your AI-powered features are used.') }}
      </template>
    </page-heading>

    <gl-tabs v-model="activeTabIndex" content-class="gl-pt-0" sync-active-tab-with-query-params>
      <gl-tab
        v-if="showDashboardTab"
        data-testid="dashboard-tab"
        :title="$options.TABS.DASHBOARD.title"
        :query-param-value="$options.TABS.DASHBOARD.queryParamValue"
        lazy
        @click="trackTabClick($options.TABS.DASHBOARD)"
      >
        <ai-governance-dashboard-app v-if="isPermitted($options.TABS.DASHBOARD)" />
        <gl-empty-state
          v-else
          :svg-path="$options.EmptyAccessSvg"
          :title="$options.i18n.noAccessTitle"
          :description="$options.i18n.noAccessDescription"
          data-testid="no-access-empty-state"
        />
      </gl-tab>

      <gl-tab
        data-testid="tool-management-tab"
        :title="$options.TABS.TOOL_MANAGEMENT.title"
        :query-param-value="$options.TABS.TOOL_MANAGEMENT.queryParamValue"
        lazy
        @click="trackTabClick($options.TABS.TOOL_MANAGEMENT)"
      >
        <ai-tool-management-app v-if="isPermitted($options.TABS.TOOL_MANAGEMENT)" />
        <gl-empty-state
          v-else
          :svg-path="$options.EmptyAccessSvg"
          :title="$options.i18n.noAccessTitle"
          :description="$options.i18n.noAccessDescription"
          data-testid="no-access-empty-state"
        />
      </gl-tab>

      <gl-tab
        v-if="showAgentArtifactsTab"
        data-testid="agent-artifacts-tab"
        :title="$options.TABS.AGENT_ARTIFACTS.title"
        :query-param-value="$options.TABS.AGENT_ARTIFACTS.queryParamValue"
        lazy
        @click="trackTabClick($options.TABS.AGENT_ARTIFACTS)"
      >
        <agent-artifacts-app v-if="isPermitted($options.TABS.AGENT_ARTIFACTS)" />
        <gl-empty-state
          v-else
          :svg-path="$options.EmptyAccessSvg"
          :title="$options.i18n.noAccessTitle"
          :description="$options.i18n.noAccessDescription"
          data-testid="no-access-empty-state"
        />
      </gl-tab>

      <gl-tab
        data-testid="mcp-registry-tab"
        :title="$options.TABS.MCP_REGISTRY.title"
        :query-param-value="$options.TABS.MCP_REGISTRY.queryParamValue"
        lazy
        @click="trackTabClick($options.TABS.MCP_REGISTRY)"
      >
        <mcp-registry-app v-if="isPermitted($options.TABS.MCP_REGISTRY)" />
        <gl-empty-state
          v-else
          :svg-path="$options.EmptyAccessSvg"
          :title="$options.i18n.noAccessTitle"
          :description="$options.i18n.noAccessDescription"
          data-testid="no-access-empty-state"
        />
      </gl-tab>
    </gl-tabs>
  </div>
</template>
