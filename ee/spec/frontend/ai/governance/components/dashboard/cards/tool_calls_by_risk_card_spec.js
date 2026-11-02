import {
  GL_COLOR_BLUE_400,
  GL_COLOR_BLUE_500,
  GL_COLOR_NEUTRAL_400,
  GL_COLOR_PURPLE_400,
  GL_COLOR_PURPLE_500,
  GL_COLOR_RED_400,
  GL_COLOR_RED_500,
} from '@gitlab/ui/src/tokens/build/js/tokens';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { print } from 'graphql/language/printer';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import ToolCallsByRiskCard from 'ee/ai/governance/components/dashboard/cards/tool_calls_by_risk_card.vue';
import DonutChart from 'ee/ai/governance/components/dashboard/charts/donut_chart.vue';
import getToolCallsByRiskQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_tool_calls_by_risk.query.graphql';

jest.mock('~/lib/utils/color_utils', () => ({
  darkModeEnabled: jest.fn(() => false),
}));

Vue.use(VueApollo);

const slice = (risk, count) => ({ __typename: 'AiGovernanceToolCallsRiskSlice', risk, count });

const byRisk = ({ read = 120000, write = 50000, destroy = 20100, unclassified = 0 } = {}) => ({
  __typename: 'AiGovernanceToolCallsByRisk',
  total: read + write + destroy + unclassified,
  slices: [
    slice('READ', read),
    slice('WRITE', write),
    slice('DESTROY', destroy),
    slice('UNCLASSIFIED', unclassified),
  ],
});

const response = (data, namespace = 'group') => ({
  data: {
    [namespace]: {
      __typename: namespace === 'group' ? 'Group' : 'Project',
      id: `gid://gitlab/${namespace === 'group' ? 'Group' : 'Project'}/1`,
      aiGovernanceToolCalls: {
        __typename: 'AiGovernanceToolCallsReport',
        byRisk: data,
      },
    },
  },
});

describe('ToolCallsByRiskCard', () => {
  let wrapper;

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(response(byRisk())),
    provide = {},
    props = {},
  } = {}) => {
    wrapper = shallowMountExtended(ToolCallsByRiskCard, {
      apolloProvider: createMockApollo([[getToolCallsByRiskQuery, handler]]),
      provide: { projectId: null, groupFullPath: 'acme', projectFullPath: '', ...provide },
      propsData: props,
      stubs: { GlCard: { template: '<div><slot name="header"></slot><slot></slot></div>' } },
    });
  };

  const findDonut = () => wrapper.findComponent(DonutChart);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  it('renders the title', () => {
    createComponent();

    expect(wrapper.find('h2').text()).toBe('Tool calls by action');
  });

  it('links to the tool registry', () => {
    createComponent();

    expect(findViewAllLink().attributes('aria-label')).toBe('View all tools in the tool registry');
    expect(findViewAllLink().text()).toBe('View all');
    expect(findViewAllLink().attributes('href')).toBe('?tab=tool-management');
  });

  it('shows the loading state while the query is in flight', () => {
    createComponent();

    expect(findDonut().props('loading')).toBe(true);
  });

  it('does not select the top tools list, so the backend skips that query', () => {
    const document = print(getToolCallsByRiskQuery);

    expect(document).toContain('byRisk');
    expect(document).not.toMatch(/\bnodes\b/);
    expect(document).not.toMatch(/\bapproximate\b/);
  });

  describe('query variables', () => {
    it('follows the dashboard filters at group scope', async () => {
      const handler = jest.fn().mockResolvedValue(response(byRisk()));
      createComponent({ handler, props: { agentClass: 'EXTERNAL', timeframe: 'LAST_30_DAYS' } });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        groupFullPath: 'acme',
        projectFullPath: '',
        isProject: false,
        agentClass: 'EXTERNAL',
        timeframe: 'LAST_30_DAYS',
      });
    });

    it('queries the project at project scope', async () => {
      const handler = jest.fn().mockResolvedValue(response(byRisk(), 'project'));
      createComponent({ handler, provide: { projectId: '1', projectFullPath: 'acme/app' } });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        groupFullPath: 'acme',
        projectFullPath: 'acme/app',
        isProject: true,
        agentClass: 'ALL',
        timeframe: 'LAST_7_DAYS',
      });
      expect(findDonut().props('slices')).toHaveLength(4);
    });
  });

  describe('with data', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('plots a slice per risk and keeps the risk as the slice name', () => {
      expect(findDonut().props('slices')).toEqual([
        { name: 'READ', label: 'Read', value: 120000 },
        { name: 'WRITE', label: 'Write', value: 50000 },
        { name: 'DESTROY', label: 'Destructive', value: 20100 },
        { name: 'UNCLASSIFIED', label: 'Unclassified', value: 0 },
      ]);
    });

    it('shows the compact total in the centre with the legend below and percentages', () => {
      expect(findDonut().props()).toMatchObject({
        centerValue: '190.1K',
        centerCaption: 'tool calls',
        description: 'Tool calls by action',
        legendPosition: 'bottom',
        showLegendPercentages: true,
        preserveOrder: true,
        loading: false,
      });
    });

    it('gives each risk a fixed colour', () => {
      expect(findDonut().props('sliceColors')).toEqual({
        READ: GL_COLOR_BLUE_500,
        WRITE: GL_COLOR_PURPLE_500,
        DESTROY: GL_COLOR_RED_500,
        UNCLASSIFIED: GL_COLOR_NEUTRAL_400,
      });
    });

    it('does not render an error', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('in dark mode', () => {
    beforeEach(() => darkModeEnabled.mockReturnValue(true));
    afterEach(() => darkModeEnabled.mockReturnValue(false));

    it('uses the lighter shades', async () => {
      createComponent();
      await waitForPromises();

      expect(findDonut().props('sliceColors')).toEqual({
        READ: GL_COLOR_BLUE_400,
        WRITE: GL_COLOR_PURPLE_400,
        DESTROY: GL_COLOR_RED_400,
        UNCLASSIFIED: GL_COLOR_NEUTRAL_400,
      });
    });
  });

  it('leaves a zero Unclassified slice out of the rendered chart', async () => {
    wrapper = shallowMountExtended(ToolCallsByRiskCard, {
      apolloProvider: createMockApollo([
        [getToolCallsByRiskQuery, jest.fn().mockResolvedValue(response(byRisk()))],
      ]),
      provide: { projectId: null, groupFullPath: 'acme', projectFullPath: '' },
      stubs: {
        GlCard: { template: '<div><slot name="header"></slot><slot></slot></div>' },
        DonutChart,
      },
    });
    await waitForPromises();

    const labels = wrapper
      .findAllByTestId('donut-legend-item')
      .wrappers.map((item) => item.text().replace(/\s+/g, ' '));

    expect(labels).toEqual(['Read 63%', 'Write 26%', 'Destructive 11%']);
  });

  it('uses the singular caption for a single tool call', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(response(byRisk({ read: 1, write: 0, destroy: 0, unclassified: 0 }))),
    });
    await waitForPromises();

    expect(findDonut().props()).toMatchObject({ centerValue: '1', centerCaption: 'tool call' });
  });

  // null is what the backend returns while ClickHouse or its flag is off.
  it.each([
    ['all zero slices', byRisk({ read: 0, write: 0, destroy: 0, unclassified: 0 })],
    ['null', null],
  ])('renders the empty state for %s', async (_, data) => {
    createComponent({ handler: jest.fn().mockResolvedValue(response(data)) });
    await waitForPromises();

    expect(findDonut().props()).toMatchObject({
      centerValue: '0',
      loading: false,
      emptyText: 'No tool calls in this period.',
    });
    expect(
      findDonut()
        .props('slices')
        .every(({ value }) => value === 0),
    ).toBe(true);
  });

  it('renders an error instead of the chart when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('GraphQL error')) });
    await waitForPromises();

    expect(findAlert().text()).toBe('Failed to load tool calls by action.');
    expect(findDonut().exists()).toBe(false);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(() => {
      createComponent();
    });

    it('marks the view-all link as a card link click on the tool calls by risk card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': 'click_card_link_on_ai_governance_dashboard',
        'data-event-label': 'tool_calls_by_risk',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a click on the view-all link', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="view-all-link"]');

      expect(trackEventSpy).toHaveBeenCalledWith('click_card_link_on_ai_governance_dashboard', {
        label: 'tool_calls_by_risk',
        property: 'view_all',
      });
    });
  });
});
