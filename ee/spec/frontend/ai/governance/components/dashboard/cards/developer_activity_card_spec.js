import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import DeveloperActivityCard from 'ee/ai/governance/components/dashboard/cards/developer_activity_card.vue';
import getDeveloperActivityQuery from 'ee/ai/governance/graphql/queries/get_developer_activity.query.graphql';

Vue.use(VueApollo);

const userNode = (id, sessionCount) => ({
  __typename: 'AiGovernanceUserActivity',
  sessionCount,
  user: {
    __typename: 'UserCore',
    id: `gid://gitlab/User/${id}`,
    name: `User ${id}`,
    username: `user${id}`,
    avatarUrl: `/uploads/-/system/user/avatar/${id}/avatar.png`,
    webUrl: `/user${id}`,
  },
});

const groupResponse = (nodes) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        topUsers: nodes,
      },
    },
  },
});

const projectResponse = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        topUsers: nodes,
      },
    },
  },
});

describe('DeveloperActivityCard', () => {
  let wrapper;

  const createComponent = ({ provide = {}, props = {}, handler } = {}) => {
    const apolloProvider = createMockApollo([
      [getDeveloperActivityQuery, handler ?? jest.fn().mockResolvedValue(groupResponse([]))],
    ]);

    wrapper = mountExtended(DeveloperActivityCard, {
      apolloProvider,
      propsData: props,
      provide: { groupFullPath: 'gitlab-duo', projectFullPath: null, ...provide },
    });
  };

  const findRows = () => wrapper.findAllByTestId('developer-activity-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  it('renders a row per ranked user', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([userNode(101, 142), userNode(102, 96)])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(2);
  });

  it('skips ranked entries whose user cannot be resolved', async () => {
    const unresolved = { __typename: 'AiGovernanceUserActivity', sessionCount: 9, user: null };
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([userNode(101, 142), unresolved])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    expect(findRows().at(0).text()).toContain('User 101');
  });

  it('maps the session count to the "N sessions" label', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(groupResponse([userNode(101, 142)])),
    });
    await waitForPromises();

    const top = findRows().at(0);
    expect(top.text()).toContain('User 101');
    expect(top.text()).toContain('142 sessions');
  });

  describe('row links', () => {
    useFakeDate(2026, 9, 19, 10);

    it.each([
      ['LAST_7_DAYS', '2026-10-12'],
      ['LAST_30_DAYS', '2026-09-19'],
    ])(
      'links each row to the audit report for that user GID over the %s window',
      async (timeframe, startTimeAfter) => {
        createComponent({
          props: { timeframe },
          handler: jest.fn().mockResolvedValue(groupResponse([userNode(101, 142)])),
        });
        await waitForPromises();

        expect(findRows().at(0).attributes('href')).toBe(
          `?tab=agent-artifacts&triggeredByUserId=${encodeURIComponent('gid://gitlab/User/101')}&startTimeAfter=${startTimeAfter}`,
        );
      },
    );

    it('carries the agent class it is given', async () => {
      createComponent({
        props: { agentClass: 'INTERNAL_DAP' },
        handler: jest.fn().mockResolvedValue(groupResponse([userNode(101, 142)])),
      });
      await waitForPromises();

      expect(findRows().at(0).attributes('href')).toBe(
        `?tab=agent-artifacts&triggeredByUserId=${encodeURIComponent('gid://gitlab/User/101')}&agentClass=INTERNAL_DAP&startTimeAfter=2026-10-12`,
      );
    });
  });

  it('shows a loading state while the query is in flight', () => {
    createComponent({ handler: jest.fn().mockReturnValue(new Promise(() => {})) });

    expect(findViewAllLink().exists()).toBe(true);
    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(false);
  });

  it('shows the empty state when there are no users', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  it('links "View all users" to the audit events tab', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe('?tab=agent-artifacts');
  });

  it('defaults to the ALL agent class', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'ALL' }));
  });

  it('segments the ranking by the agent class it is given', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ props: { agentClass: 'EXTERNAL' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
  });

  it('re-runs the query when the agent class changes', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    await wrapper.setProps({ agentClass: 'INTERNAL_DAP' });
    await waitForPromises();

    expect(handler).toHaveBeenLastCalledWith(
      expect.objectContaining({ agentClass: 'INTERNAL_DAP' }),
    );
  });

  it('renders no window footnote, since it honours the selected timeframe', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findByTestId('card-footnote').exists()).toBe(false);
  });

  it('defaults to the LAST_7_DAYS timeframe', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_7_DAYS' }));
  });

  it('scopes the ranking to the timeframe it is given', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ props: { timeframe: 'LAST_30_DAYS' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_30_DAYS' }));
  });

  it('re-runs the query when the timeframe changes', async () => {
    const handler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ handler });
    await waitForPromises();

    await wrapper.setProps({ timeframe: 'LAST_30_DAYS' });
    await waitForPromises();

    expect(handler).toHaveBeenLastCalledWith(
      expect.objectContaining({ timeframe: 'LAST_30_DAYS' }),
    );
  });

  it('uses the project-level query in project mode', async () => {
    const handler = jest.fn().mockResolvedValue(projectResponse([userNode(101, 5)]));
    createComponent({ provide: { projectFullPath: 'gitlab-duo/test' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({ projectFullPath: 'gitlab-duo/test', isProject: true }),
    );
    expect(findRows()).toHaveLength(1);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const CARD_LINK_EVENT = 'click_card_link_on_ai_governance_dashboard';

    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(groupResponse([userNode(101, 142)])),
      });
      await waitForPromises();
    });

    it('marks each row as a card link click on the developer activity card', () => {
      expect(findRows().at(0).attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'developer_activity',
        'data-event-property': 'row',
      });
    });

    it('marks the view-all link as a card link click on the developer activity card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'developer_activity',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a row click', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="developer-activity-row"]');

      expect(trackEventSpy).toHaveBeenCalledWith(CARD_LINK_EVENT, {
        label: 'developer_activity',
        property: 'row',
      });
    });
  });
});
