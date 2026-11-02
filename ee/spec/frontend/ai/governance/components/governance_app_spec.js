import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlEmptyState, GlTabs } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import GovernanceApp from 'ee/ai/governance/components/governance_app.vue';
import AiGovernanceDashboardApp from 'ee/ai/governance/components/dashboard/dashboard_app.vue';
import AgentArtifactsApp from 'ee/agent_artifacts/components/agent_artifacts_app.vue';
import AiToolManagementApp from 'ee/ai/governance/components/ai_tool_management/ai_tool_management_app.vue';
import getMcpServersQuery from 'ee/ai/governance/graphql/queries/get_mcp_servers.query.graphql';
import PageHeading from '~/vue_shared/components/page_heading.vue';

Vue.use(VueApollo);

const ALL_TABS = ['dashboard', 'tool-management', 'agent-artifacts', 'mcp-registry'];

describe('GovernanceApp', () => {
  let wrapper;

  const createComponent = ({
    glFeatures = {},
    permittedTabs = ALL_TABS,
    mountFn = shallowMountExtended,
  } = {}) => {
    // The lazy tabs resolve their async components after waitForPromises; provide a
    // client so the Apollo-backed MCP registry tab does not error when it mounts.
    const apolloProvider = createMockApollo([
      [
        getMcpServersQuery,
        jest.fn().mockResolvedValue({
          data: {
            aiCatalogMcpServers: {
              nodes: [],
              pageInfo: { hasNextPage: false, hasPreviousPage: false, __typename: 'PageInfo' },
              __typename: 'AiCatalogMcpServerConnection',
            },
          },
        }),
      ],
    ]);

    wrapper = mountFn(GovernanceApp, {
      apolloProvider,
      provide: {
        glFeatures,
        groupFullPath: 'gitlab-org',
        permittedTabs,
      },
    });
  };

  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findTabs = () => wrapper.findComponent(GlTabs);
  const findToolManagementTab = () => wrapper.findByTestId('tool-management-tab');
  const findAgentArtifactsTab = () => wrapper.findByTestId('agent-artifacts-tab');
  const findDashboardTab = () => wrapper.findByTestId('dashboard-tab');
  const findMcpRegistryTab = () => wrapper.findByTestId('mcp-registry-tab');

  describe('page heading', () => {
    it('renders the page heading', () => {
      createComponent();

      expect(findPageHeading().exists()).toBe(true);
      expect(findPageHeading().text()).toContain('Control how your AI-powered features are used.');
    });
  });

  describe('tabs', () => {
    it('renders the GlTabs component', () => {
      createComponent();

      expect(findTabs().exists()).toBe(true);
    });

    it('renders the Tool management tab', () => {
      createComponent();

      expect(findToolManagementTab().exists()).toBe(true);
    });

    it('renders the MCP registry tab', () => {
      createComponent();

      expect(findMcpRegistryTab().exists()).toBe(true);
    });
  });

  describe('when agentArtifactsPage feature flag is enabled', () => {
    beforeEach(() => {
      createComponent({ glFeatures: { agentArtifactsPage: true } });
    });

    it('renders the Audit events tab', () => {
      expect(findAgentArtifactsTab().exists()).toBe(true);
    });

    it('renders AgentArtifactsApp when the Audit events tab is active', async () => {
      await findTabs().vm.$emit('input', 1);
      await waitForPromises();

      expect(wrapper.findComponent(AgentArtifactsApp).exists()).toBe(true);
    });
  });

  describe('when agentArtifactsPage feature flag is disabled', () => {
    beforeEach(() => {
      createComponent({ glFeatures: { agentArtifactsPage: false } });
    });

    it('does not render the Audit events tab', () => {
      expect(findAgentArtifactsTab().exists()).toBe(false);
    });
  });

  describe('when aiGovernanceDashboard feature flag is enabled', () => {
    beforeEach(() => {
      createComponent({ glFeatures: { aiGovernanceDashboard: true } });
    });

    it('renders the Dashboard tab', () => {
      expect(findDashboardTab().exists()).toBe(true);
    });

    it('renders AiGovernanceDashboardApp when the Dashboard tab is active', async () => {
      await waitForPromises();

      expect(wrapper.findComponent(AiGovernanceDashboardApp).exists()).toBe(true);
    });
  });

  describe('when aiGovernanceDashboard feature flag is disabled', () => {
    beforeEach(() => {
      createComponent({ glFeatures: { aiGovernanceDashboard: false } });
    });

    it('does not render the Dashboard tab', () => {
      expect(findDashboardTab().exists()).toBe(false);
    });
  });

  describe('tab permissions', () => {
    it('renders the tab app when the tab is permitted', async () => {
      createComponent({ permittedTabs: ['tool-management'] });
      await waitForPromises();

      expect(wrapper.findComponent(AiToolManagementApp).exists()).toBe(true);
      expect(findToolManagementTab().findComponent(GlEmptyState).exists()).toBe(false);
    });

    it('renders the empty state instead of the tab app when the tab is not permitted', async () => {
      createComponent({ permittedTabs: [] });
      await waitForPromises();

      expect(findToolManagementTab().exists()).toBe(true);
      expect(wrapper.findComponent(AiToolManagementApp).exists()).toBe(false);
      expect(findToolManagementTab().findComponent(GlEmptyState).props('title')).toBe(
        "You don't have access to this tab",
      );
    });

    it('still renders every tab whose feature flag is on', () => {
      createComponent({
        glFeatures: { aiGovernanceDashboard: true, agentArtifactsPage: true },
        permittedTabs: [],
      });

      expect(findDashboardTab().exists()).toBe(true);
      expect(findToolManagementTab().exists()).toBe(true);
      expect(findAgentArtifactsTab().exists()).toBe(true);
      expect(findMcpRegistryTab().exists()).toBe(true);
    });

    it('opens an unpermitted tab from the tab query param with the empty state', async () => {
      setWindowLocation('?tab=agent-artifacts');

      createComponent({
        glFeatures: { agentArtifactsPage: true },
        permittedTabs: ['tool-management'],
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findTabs().props('value')).toBe(1);
      expect(wrapper.findComponent(AiToolManagementApp).exists()).toBe(false);
      expect(wrapper.findComponent(AgentArtifactsApp).exists()).toBe(false);
      expect(findAgentArtifactsTab().findComponent(GlEmptyState).exists()).toBe(true);
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(() => {
      createComponent({ glFeatures: { aiGovernanceDashboard: true, agentArtifactsPage: true } });
    });

    it.each`
      testId                   | label
      ${'dashboard-tab'}       | ${'dashboard'}
      ${'tool-management-tab'} | ${'tool_management'}
      ${'agent-artifacts-tab'} | ${'audit_events'}
      ${'mcp-registry-tab'}    | ${'mcp_registry'}
    `('tracks a click on the $label tab', ({ testId, label }) => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      wrapper.findComponentByTestId(testId).vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_tab_on_ai_governance_page',
        { label },
        undefined,
      );
    });

    it('does not track the tab opened on load', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findTabs().vm.$emit('input', 1);

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        'click_tab_on_ai_governance_page',
        expect.anything(),
        undefined,
      );
    });
  });
});
