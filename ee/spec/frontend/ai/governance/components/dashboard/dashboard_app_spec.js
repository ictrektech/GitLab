import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import AiGovernanceDashboardApp from 'ee/ai/governance/components/dashboard/dashboard_app.vue';
import AuditTrailCard from 'ee/ai/governance/components/dashboard/cards/audit_trail_card.vue';
import AgentInventoryCard from 'ee/ai/governance/components/dashboard/cards/agent_inventory_card.vue';
import getAiGovernanceMetricsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_metrics.query.graphql';
import SessionDistributionCard from 'ee/ai/governance/components/dashboard/cards/session_distribution_card.vue';

Vue.use(VueApollo);

const GROUP_FULL_PATH = 'gitlab-org';

const point = (c, i) => ({ bucketStart: `2026-07-2${i}T00:00:00Z`, count: c });

const kpi = (count, previousCount, counts) => ({
  count,
  previousCount,
  trend: counts.map(point),
  cumulativeTrend: null,
});

const withCumulativeTrend = (base, counts) => ({ ...base, cumulativeTrend: counts.map(point) });

const metricsResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      aiGovernanceMetrics: {
        agents: kpi(12, 8, [8, 10, 12]),
        sessions: kpi(40, 55, [55, 48, 40]),
        toolCalls: null,
      },
    },
  },
};

describe('AiGovernanceDashboardApp', () => {
  let wrapper;

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(metricsResponse),
    glFeatures = {
      aiGovernanceMcpServerActivity: true,
      aiGovernanceConnectedAgentsFilter: true,
      aiGovernanceToolCalls: true,
    },
    provide = {},
  } = {}) => {
    const apolloProvider = createMockApollo([[getAiGovernanceMetricsQuery, handler]]);

    wrapper = shallowMountExtended(AiGovernanceDashboardApp, {
      apolloProvider,
      provide: {
        groupFullPath: GROUP_FULL_PATH,
        projectFullPath: '',
        projectId: null,
        glFeatures,
        ...provide,
      },
    });
  };

  const findSummaryMetric = (key) => wrapper.findComponentByTestId(`summary-metric-${key}`);
  const findCard = (key) => wrapper.findByTestId(`dashboard-card-${key}`);
  const findAgentClassFilter = () => wrapper.findComponentByTestId('agent-class-filter');
  const findTimeframeFilter = () => wrapper.findComponentByTestId('timeframe-filter');

  const toolCallsResponse = {
    data: {
      group: {
        ...metricsResponse.data.group,
        aiGovernanceMetrics: {
          ...metricsResponse.data.group.aiGovernanceMetrics,
          toolCalls: kpi(190, 122, [40, 60, 90]),
        },
      },
    },
  };

  const createWithTile = (handler = jest.fn().mockResolvedValue(toolCallsResponse)) =>
    createComponent({ handler, glFeatures: { aiGovernanceToolCalls: true } });

  describe('summary header', () => {
    beforeEach(() => createComponent());

    it.each(['agents', 'sessions'])('renders the %s summary metric', (key) => {
      expect(findSummaryMetric(key).exists()).toBe(true);
    });

    it('does not render a compliance posture tile', () => {
      expect(findSummaryMetric('posture').exists()).toBe(false);
    });
  });

  describe('AI tool calls tile', () => {
    it('is hidden and not requested when the feature flag is off', async () => {
      const handler = jest.fn().mockResolvedValue(metricsResponse);
      createComponent({ handler, glFeatures: {} });
      await waitForPromises();

      expect(findSummaryMetric('tool-calls').exists()).toBe(false);
      expect(handler).toHaveBeenCalledWith(expect.objectContaining({ includeToolCalls: false }));
    });

    it('leaves the dashboard as it was before tool calls when the feature flag is off', async () => {
      const handler = jest.fn().mockResolvedValue(metricsResponse);
      createComponent({ handler, glFeatures: { aiGovernanceMcpServerActivity: true } });
      await waitForPromises();

      const testIds = (prefix) =>
        wrapper
          .findAll(`[data-testid^="${prefix}"]`)
          .wrappers.map((w) => w.attributes('data-testid'));

      expect(testIds('summary-metric-')).toEqual([
        'summary-metric-agents',
        'summary-metric-sessions',
      ]);
      expect(testIds('dashboard-card-')).toEqual([
        'dashboard-card-agent-inventory',
        'dashboard-card-audit-trail',
        'dashboard-card-developer-activity',
        'dashboard-card-project-exposure',
        'dashboard-card-mcp-server-activity',
      ]);
      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler).toHaveBeenCalledWith(expect.objectContaining({ includeToolCalls: false }));
    });

    it('explains each tile in a popover, in the words of the API field descriptions', async () => {
      createWithTile();
      await waitForPromises();

      expect(findSummaryMetric('agents').props('helpText')).toBe(
        'Distinct AI agents with at least one session in the time range. Agentic Chat conversations are not counted.',
      );
      expect(findSummaryMetric('sessions').props('helpText')).toBe(
        'AI sessions started in the time range, including Agentic Chat conversations.',
      );
      expect(findSummaryMetric('tool-calls').props('helpText')).toBe(
        'Every tool call made by AI agents in the time range.',
      );
    });

    it('requests the toolCalls field when the feature flag is on', async () => {
      const handler = jest.fn().mockResolvedValue(toolCallsResponse);
      createWithTile(handler);
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(expect.objectContaining({ includeToolCalls: true }));
    });

    it('renders the count, the change as a share of the previous period and the trend', async () => {
      createWithTile();
      await waitForPromises();

      const tile = findSummaryMetric('tool-calls');

      expect(tile.props()).toMatchObject({
        label: 'Total number of tool calls',
        value: '190',
        delta: '+56% this week',
        deltaDirection: 'up',
      });
      expect(tile.props('chartData')).toHaveLength(3);
    });

    it('charts cumulativeTrend in preference to trend', async () => {
      const cumulativeResponse = {
        data: {
          group: {
            ...metricsResponse.data.group,
            aiGovernanceMetrics: {
              ...metricsResponse.data.group.aiGovernanceMetrics,
              toolCalls: withCumulativeTrend(kpi(190, 122, [40, 60, 90]), [150, 170, 190]),
            },
          },
        },
      };
      createWithTile(jest.fn().mockResolvedValue(cumulativeResponse));
      await waitForPromises();

      expect(
        findSummaryMetric('tool-calls')
          .props('chartData')
          .map(([, count]) => count),
      ).toEqual([150, 170, 190]);
    });

    it('falls back to a placeholder when the KPI is missing', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(metricsResponse),
        glFeatures: { aiGovernanceToolCalls: true },
      });
      await waitForPromises();

      expect(findSummaryMetric('tool-calls').props('value')).toBe('\u2014');
    });
  });

  describe('metrics wiring', () => {
    it('requests group metrics with the default timeframe and agent class', async () => {
      const handler = jest.fn().mockResolvedValue(metricsResponse);
      createComponent({ handler });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({
          groupFullPath: GROUP_FULL_PATH,
          isProject: false,
          timeframe: 'LAST_7_DAYS',
          agentClass: 'ALL',
        }),
      );
    });

    it('re-queries with the selected agent class when the filter changes', async () => {
      const handler = jest.fn().mockResolvedValue(metricsResponse);
      createComponent({ handler });
      await waitForPromises();

      findAgentClassFilter().vm.$emit('input', 'EXTERNAL');
      await waitForPromises();

      expect(handler).toHaveBeenLastCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
    });

    it.each([
      'audit-trail',
      'agent-inventory',
      'developer-activity',
      'project-exposure',
      'tool-calls',
      'tool-calls-by-risk',
    ])('passes the selected agent class down to the %s card', async (key) => {
      createComponent();
      await waitForPromises();

      expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('agentClass')).toBe(
        'ALL',
      );

      findAgentClassFilter().vm.$emit('input', 'INTERNAL_DAP');
      await waitForPromises();

      expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('agentClass')).toBe(
        'INTERNAL_DAP',
      );
    });

    describe('date range filter', () => {
      it('offers only the 7 and 30 day windows', () => {
        createComponent();

        expect(findTimeframeFilter().props('options')).toEqual([
          { value: 'LAST_7_DAYS', text: 'Last 7 days' },
          { value: 'LAST_30_DAYS', text: 'Last 30 days' },
        ]);
      });

      it('queries the selected window', async () => {
        const handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ handler });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_7_DAYS' }));
      });

      it('re-queries with LAST_30_DAYS when picked', async () => {
        const handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ handler });
        await waitForPromises();

        findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
        await waitForPromises();

        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ timeframe: 'LAST_30_DAYS' }),
        );
      });

      it.each(['developer-activity', 'project-exposure', 'tool-calls', 'tool-calls-by-risk'])(
        'passes the selected window down to the %s card',
        async (key) => {
          createComponent();
          await waitForPromises();

          expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('timeframe')).toBe(
            'LAST_7_DAYS',
          );

          findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
          await waitForPromises();

          expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('timeframe')).toBe(
            'LAST_30_DAYS',
          );
        },
      );

      it('relabels the tile delta for the selected window', async () => {
        createComponent();
        await waitForPromises();

        expect(findSummaryMetric('agents').props('delta')).toBe('+4 this week');

        findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
        await waitForPromises();

        expect(findSummaryMetric('agents').props('delta')).toBe('+4 this month');
      });
    });

    describe('with the connected agents filter disabled', () => {
      const dapOnly = { aiGovernanceMcpServerActivity: true, aiGovernanceToolCalls: true };

      it('offers DAP as the only agent class', () => {
        createComponent({ glFeatures: dapOnly });

        expect(findAgentClassFilter().props('options')).toEqual([
          { value: 'INTERNAL_DAP', text: 'DAP' },
        ]);
      });

      it('queries DAP metrics rather than all agents', async () => {
        const handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ glFeatures: dapOnly, handler });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(
          expect.objectContaining({ agentClass: 'INTERNAL_DAP' }),
        );
      });

      it.each([
        'audit-trail',
        'agent-inventory',
        'developer-activity',
        'project-exposure',
        'tool-calls',
        'tool-calls-by-risk',
      ])('scopes the %s card to DAP', async (key) => {
        createComponent({ glFeatures: dapOnly });
        await waitForPromises();

        expect(wrapper.findComponentByTestId(`dashboard-card-${key}`).props('agentClass')).toBe(
          'INTERNAL_DAP',
        );
      });
    });

    it('maps a rising KPI to an up delta and a trend sparkline', async () => {
      createComponent();
      await waitForPromises();

      const agents = findSummaryMetric('agents');
      expect(agents.props('value')).toBe('12');
      expect(agents.props('delta')).toBe('+4 this week');
      expect(agents.props('deltaDirection')).toBe('up');

      // No cumulativeTrend in this fixture, so the tile falls back to `trend`.
      const chartData = agents.props('chartData');
      expect(chartData.map((p) => p[1])).toEqual([8, 10, 12]);
      // x-axis is a formatted date label (from bucketStart), not a bare index.
      expect(typeof chartData[0][0]).toBe('string');
    });

    it('charts cumulativeTrend in preference to trend when the backend returns it', async () => {
      const withCumulative = {
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            aiGovernanceMetrics: {
              agents: withCumulativeTrend(kpi(12, 8, [8, 10, 12]), [40, 44, 52]),
              sessions: withCumulativeTrend(kpi(40, 55, [55, 48, 40]), [100, 148, 188]),
              toolCalls: null,
            },
          },
        },
      };
      createComponent({ handler: jest.fn().mockResolvedValue(withCumulative) });
      await waitForPromises();

      expect(
        findSummaryMetric('agents')
          .props('chartData')
          .map((p) => p[1]),
      ).toEqual([40, 44, 52]);
      expect(
        findSummaryMetric('sessions')
          .props('chartData')
          .map((p) => p[1]),
      ).toEqual([100, 148, 188]);
    });

    it('falls back to trend when cumulativeTrend comes back empty', async () => {
      const emptyCumulative = {
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            aiGovernanceMetrics: {
              agents: withCumulativeTrend(kpi(12, 8, [8, 10, 12]), []),
              sessions: kpi(40, 55, [55, 48, 40]),
              toolCalls: null,
            },
          },
        },
      };
      createComponent({ handler: jest.fn().mockResolvedValue(emptyCumulative) });
      await waitForPromises();

      expect(
        findSummaryMetric('agents')
          .props('chartData')
          .map((p) => p[1]),
      ).toEqual([8, 10, 12]);
    });

    it('maps a falling KPI to a down delta', async () => {
      createComponent();
      await waitForPromises();

      const sessions = findSummaryMetric('sessions');
      expect(sessions.props('value')).toBe('40');
      expect(sessions.props('delta')).toBe('-27% this week');
      expect(sessions.props('deltaDirection')).toBe('down');
    });

    describe('sessions and tool calls tile change as a percentage', () => {
      const withSessions = (sessions) => ({
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            aiGovernanceMetrics: { ...metricsResponse.data.group.aiGovernanceMetrics, sessions },
          },
        },
      });

      it('shows the rise as a share of the previous period', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(withSessions(kpi(62, 50, [50, 56, 62]))),
        });
        await waitForPromises();

        expect(findSummaryMetric('sessions').props('delta')).toBe('+24% this week');
        expect(findSummaryMetric('sessions').props('deltaDirection')).toBe('up');
      });

      it('falls back to the count when the previous period had no sessions', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(withSessions(kpi(9, 0, [0, 4, 9]))),
        });
        await waitForPromises();

        expect(findSummaryMetric('sessions').props('delta')).toBe('+9 this week');
      });

      it('falls back to the count when the share rounds to zero', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(withSessions(kpi(1001, 1000, [1000, 1000, 1001]))),
        });
        await waitForPromises();

        expect(findSummaryMetric('sessions').props('delta')).toBe('+1 this week');
      });

      it('shows the tool calls rise as a share of the previous period', async () => {
        createWithTile();
        await waitForPromises();

        expect(findSummaryMetric('tool-calls').props('delta')).toBe('+56% this week');
        expect(findSummaryMetric('tool-calls').props('deltaDirection')).toBe('up');
      });

      it('keeps the count on the agents tile', async () => {
        createComponent();
        await waitForPromises();

        expect(findSummaryMetric('agents').props('delta')).toBe('+4 this week');
      });
    });

    it('falls back to a neutral placeholder when metrics are unavailable', async () => {
      const nullResponse = {
        data: { group: { id: 'gid://gitlab/Group/1', aiGovernanceMetrics: null } },
      };
      createComponent({ handler: jest.fn().mockResolvedValue(nullResponse) });
      await waitForPromises();

      const agents = findSummaryMetric('agents');
      expect(agents.props('value')).toBe('—');
    });
  });

  describe('session distribution card', () => {
    const findSessionDistributionCard = () =>
      wrapper.findComponentByTestId('dashboard-card-session-distribution');

    describe('with the charts feature flag on', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: {
            aiGovernanceDashboardCharts: true,
            aiGovernanceConnectedAgentsFilter: true,
          },
        });
        await waitForPromises();
      });

      it('renders the card', () => {
        expect(wrapper.findComponent(SessionDistributionCard).exists()).toBe(true);
      });

      it('renders the card right after the AI agent inventory card', () => {
        const order = wrapper
          .findAll('[data-testid^="dashboard-card-"]')
          .wrappers.map((w) => w.attributes('data-testid'));

        expect(order.indexOf('dashboard-card-session-distribution')).toBe(
          order.indexOf('dashboard-card-agent-inventory') + 1,
        );
      });

      it('passes the selected filters down to the card', async () => {
        expect(findSessionDistributionCard().props()).toMatchObject({
          agentClass: 'ALL',
          timeframe: 'LAST_7_DAYS',
        });

        findAgentClassFilter().vm.$emit('input', 'EXTERNAL');
        findTimeframeFilter().vm.$emit('input', 'LAST_30_DAYS');
        await waitForPromises();

        expect(findSessionDistributionCard().props()).toMatchObject({
          agentClass: 'EXTERNAL',
          timeframe: 'LAST_30_DAYS',
        });
      });
    });

    describe('with the charts feature flag off', () => {
      let handler;

      beforeEach(async () => {
        handler = jest.fn().mockResolvedValue(metricsResponse);
        createComponent({ handler, glFeatures: { aiGovernanceDashboardCharts: false } });
        await waitForPromises();
      });

      it('does not render the card', () => {
        expect(findSessionDistributionCard().exists()).toBe(false);
      });

      it('still renders the AI agent inventory card', () => {
        expect(findCard('agent-inventory').exists()).toBe(true);
      });

      it('does not send a session distribution variable with the metrics query', () => {
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0]).not.toHaveProperty('includeSessionDistribution');
      });
    });

    // A variable used only inside a node that @gl_introduced strips looks unused
    // to the backend validator, which then rejects the whole operation.
    it('keeps the session distribution out of the shared metrics query', () => {
      const [operation] = getAiGovernanceMetricsQuery.definitions;
      const variableNames = operation.variableDefinitions.map(
        ({ variable }) => variable.name.value,
      );

      expect(variableNames).not.toContain('includeSessionDistribution');
      expect(getAiGovernanceMetricsQuery.loc.source.body).not.toContain('sessionDistribution');
    });
  });

  describe('data-backed cards', () => {
    beforeEach(() => createComponent());

    it('renders the Audit logs card', () => {
      expect(wrapper.findComponent(AuditTrailCard).exists()).toBe(true);
      expect(findCard('audit-trail').exists()).toBe(true);
    });

    it('renders the AI agent inventory card', () => {
      expect(wrapper.findComponent(AgentInventoryCard).exists()).toBe(true);
      expect(findCard('agent-inventory').exists()).toBe(true);
    });

    it('renders the Developer activity card', () => {
      expect(findCard('developer-activity').exists()).toBe(true);
    });

    it('renders the MCP server activity card when its feature flag is on', () => {
      expect(findCard('mcp-server-activity').exists()).toBe(true);
    });

    it('hides the MCP server activity card when its feature flag is off', () => {
      createComponent({ glFeatures: { aiGovernanceMcpServerActivity: false } });

      expect(findCard('mcp-server-activity').exists()).toBe(false);
    });

    it('renders the Project exposure card', () => {
      expect(findCard('project-exposure').exists()).toBe(true);
    });

    it('does not segment the MCP servers card by agent class', () => {
      // The card declares no agentClass prop, so a stray template binding would
      // arrive as an attribute; asserting on props passes either way.
      const mcpCard = wrapper.findComponentByTestId('dashboard-card-mcp-server-activity');

      expect(mcpCard.attributes('agent-class')).toBeUndefined();
    });

    it('renders the SkillGuard card when its feature flag is on', () => {
      createComponent({ glFeatures: { aiGovernanceSkillguardWidget: true } });

      expect(findCard('skillguard').exists()).toBe(true);
    });

    it('hides the SkillGuard card when its feature flag is off', () => {
      createComponent({ glFeatures: { aiGovernanceSkillguardWidget: false } });

      expect(findCard('skillguard').exists()).toBe(false);
    });

    it('renders the SkillGuard card at project scope too', () => {
      createComponent({
        glFeatures: { aiGovernanceSkillguardWidget: true },
        provide: { projectId: '1', projectFullPath: 'gitlab-duo/test' },
      });

      expect(findCard('skillguard').exists()).toBe(true);
    });

    it('renders the Top tools by calls card when its feature flag is on', () => {
      expect(findCard('tool-calls').exists()).toBe(true);
    });

    it('hides the Top tools by calls card when its feature flag is off', () => {
      createComponent({ glFeatures: { aiGovernanceToolCalls: false } });

      expect(findCard('tool-calls').exists()).toBe(false);
    });

    it('renders the Tool calls by action card when the tool calls flag is on', () => {
      expect(findCard('tool-calls-by-risk').exists()).toBe(true);
    });

    it('hides the Tool calls by action card when the tool calls flag is off', () => {
      createComponent({ glFeatures: { aiGovernanceToolCalls: false } });

      expect(findCard('tool-calls-by-risk').exists()).toBe(false);
    });

    it('renders the MCP server activity card last', () => {
      const order = wrapper
        .findAll('[data-testid^="dashboard-card-"]')
        .wrappers.map((w) => w.attributes('data-testid'));

      expect(order.at(-1)).toBe('dashboard-card-mcp-server-activity');
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks one dashboard view on mount', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith('view_ai_governance_dashboard', {}, undefined);
    });

    it.each`
      filter           | findFilter              | value             | property
      ${'agent_class'} | ${findAgentClassFilter} | ${'INTERNAL_DAP'} | ${'internal_dap'}
      ${'agent_class'} | ${findAgentClassFilter} | ${'EXTERNAL'}     | ${'external'}
      ${'timeframe'}   | ${findTimeframeFilter}  | ${'LAST_30_DAYS'} | ${'last_30_days'}
    `('tracks a $filter change to $property', ({ filter, findFilter, value, property }) => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findFilter().vm.$emit('input', value);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'apply_filter_on_ai_governance_dashboard',
        { label: filter, property },
        undefined,
      );
    });

    it.each`
      filter           | findFilter              | value
      ${'agent_class'} | ${findAgentClassFilter} | ${'ALL'}
      ${'timeframe'}   | ${findTimeframeFilter}  | ${'LAST_7_DAYS'}
    `(
      'does not track a click on the $filter option that is already selected',
      ({ findFilter, value }) => {
        createComponent();
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findFilter().vm.$emit('input', value);

        expect(trackEventSpy).not.toHaveBeenCalledWith(
          'apply_filter_on_ai_governance_dashboard',
          expect.anything(),
          undefined,
        );
      },
    );
  });
});
