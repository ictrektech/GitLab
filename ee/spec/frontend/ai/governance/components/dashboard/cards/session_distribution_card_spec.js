import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import SessionDistributionCard from 'ee/ai/governance/components/dashboard/cards/session_distribution_card.vue';
import DonutChart from 'ee/ai/governance/components/dashboard/charts/donut_chart.vue';
import getSessionDistributionQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_session_distribution.query.graphql';

Vue.use(VueApollo);

const slice = (name, developers, sessions = developers * 10) => ({
  __typename: 'AiGovernanceSessionDistributionSlice',
  name,
  sessions,
  developers,
});

const distribution = (slices, { totalDevelopers = 3, totalSessions = 1505 } = {}) => ({
  __typename: 'AiGovernanceSessionDistribution',
  totalSessions,
  totalDevelopers,
  slices,
});

// Slices sum to 4 developers against a total of 3: one developer used two agents.
const sessionDistribution = distribution([
  slice('gitlab_duo', 2, 1200),
  slice('claude-code', 1, 300),
  slice('unknown', 1, 5),
]);

const response = (data, namespace = 'group') => ({
  data: {
    [namespace]: {
      __typename: namespace === 'group' ? 'Group' : 'Project',
      id: `gid://gitlab/${namespace === 'group' ? 'Group' : 'Project'}/1`,
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        sessionDistribution: data,
      },
    },
  },
});

describe('SessionDistributionCard', () => {
  let wrapper;

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(response(sessionDistribution)),
    provide = {},
    props = {},
  } = {}) => {
    wrapper = shallowMountExtended(SessionDistributionCard, {
      apolloProvider: createMockApollo([[getSessionDistributionQuery, handler]]),
      provide: { groupFullPath: 'acme', projectFullPath: '', ...provide },
      propsData: props,
      stubs: { GlCard: { template: '<div><slot name="header"></slot><slot></slot></div>' } },
    });
  };

  const findDonut = () => wrapper.findComponent(DonutChart);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  it('renders the title', () => {
    createComponent();

    expect(wrapper.find('h2').text()).toBe('Which AI agents developers are using');
  });

  it('shows the loading state while the query is in flight', () => {
    createComponent();

    expect(findDonut().props('loading')).toBe(true);
  });

  describe('view all agents link', () => {
    it('links to the group agents page at group scope', () => {
      createComponent();

      expect(findViewAllLink().attributes('aria-label')).toBe('View all agents');
      expect(findViewAllLink().text()).toBe('View all');
      expect(findViewAllLink().attributes('href')).toBe('/groups/acme/-/automate/agents');
    });

    it('links to the project agents page at project scope', () => {
      createComponent({ provide: { projectFullPath: 'acme/app' } });

      expect(findViewAllLink().attributes('href')).toBe('/acme/app/-/automate/agents');
    });
  });

  describe('query variables', () => {
    it('follows the dashboard filters at group scope', async () => {
      const handler = jest.fn().mockResolvedValue(response(sessionDistribution));
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
      const handler = jest.fn().mockResolvedValue(response(sessionDistribution, 'project'));
      createComponent({ handler, provide: { projectFullPath: 'acme/app' } });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        groupFullPath: 'acme',
        projectFullPath: 'acme/app',
        isProject: true,
        agentClass: 'ALL',
        timeframe: 'LAST_7_DAYS',
      });
      expect(findDonut().props('slices')).toHaveLength(3);
    });
  });

  describe('with data', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('plots developers per slice and keeps the type as the slice name', () => {
      expect(findDonut().props('slices')).toEqual([
        { name: 'gitlab_duo', label: 'GitLab Duo', value: 2 },
        { name: 'claude-code', label: 'Claude Code', value: 1 },
        { name: 'unknown', label: 'Unknown', value: 1 },
      ]);
    });

    it('shows the total developer count in the centre, not the sum of slices', () => {
      expect(findDonut().props()).toMatchObject({
        centerValue: '3',
        centerCaption: 'developers',
        description: 'Developers by AI agent',
        legendPosition: 'right',
        maxSlices: 10,
        loading: false,
      });
    });

    it('passes the developer total as the percentage base, since slices overlap', () => {
      expect(findDonut().props('percentageTotal')).toBe(3);
    });

    it('does not render an error', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  it('formats a large developer total', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(
          response(distribution([slice('chat', 1200)], { totalDevelopers: 1200 })),
        ),
    });
    await waitForPromises();

    expect(findDonut().props('centerValue')).toBe('1,200');
  });

  it.each([
    ['gitlab_duo', 'GitLab Duo'],
    ['claude-code', 'Claude Code'],
    ['cursor', 'Cursor'],
    ['opencode', 'OpenCode'],
    ['chat', 'Chat'],
    ['secrets_fp_detection', 'Secrets fp detection'],
    ['software_development', 'Software development'],
  ])('labels the %s slice as %s', async (name, label) => {
    createComponent({
      handler: jest.fn().mockResolvedValue(response(distribution([slice(name, 5)]))),
    });
    await waitForPromises();

    expect(findDonut().props('slices')).toEqual([{ name, label, value: 5 }]);
  });

  it('keeps a known agent on the same colour when the other slices change', async () => {
    const colorsFor = async (slices) => {
      createComponent({ handler: jest.fn().mockResolvedValue(response(distribution(slices))) });
      await waitForPromises();
      return findDonut().props('sliceColors');
    };

    const all = await colorsFor([
      slice('claude-code', 4),
      slice('gitlab_duo', 3),
      slice('opencode', 2),
    ]);
    const connected = await colorsFor([slice('claude-code', 4), slice('opencode', 2)]);

    expect(connected.opencode).toBe(all.opencode);
    expect(connected['claude-code']).toBe(all['claude-code']);
    expect(new Set(Object.values(all)).size).toBe(Object.keys(all).length);
  });

  it('uses the singular caption for a single developer', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(response(distribution([slice('chat', 1)], { totalDevelopers: 1 }))),
    });
    await waitForPromises();

    expect(findDonut().props('centerCaption')).toBe('developer');
  });

  // null is what the backend returns while its flag is off.
  it.each([
    ['no slices', distribution([], { totalDevelopers: 0, totalSessions: 0 })],
    ['null', null],
  ])('renders the empty state for %s', async (_, data) => {
    createComponent({ handler: jest.fn().mockResolvedValue(response(data)) });
    await waitForPromises();

    expect(findDonut().props()).toMatchObject({
      slices: [],
      centerValue: '0',
      loading: false,
      emptyText: 'No sessions in this period.',
    });
  });

  it('renders an error instead of the chart when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('GraphQL error')) });
    await waitForPromises();

    expect(findAlert().text()).toBe('Failed to load session distribution.');
    expect(findDonut().exists()).toBe(false);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(() => {
      createComponent();
    });

    it('marks the view-all link as a card link click on the session distribution card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': 'click_card_link_on_ai_governance_dashboard',
        'data-event-label': 'session_distribution',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a click on the view-all link', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="view-all-link"]');

      expect(trackEventSpy).toHaveBeenCalledWith('click_card_link_on_ai_governance_dashboard', {
        label: 'session_distribution',
        property: 'view_all',
      });
    });
  });
});
