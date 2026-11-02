import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlBadge } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import ToolCallsCard from 'ee/ai/governance/components/dashboard/cards/tool_calls_card.vue';
import getAiGovernanceToolCallsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_tool_calls.query.graphql';

Vue.use(VueApollo);

const toolNode = (toolName, count, { title = toolName, actionType = null } = {}) => ({
  __typename: 'AiGovernanceToolCall',
  toolName,
  title,
  actionType,
  count,
});

const toolCallsResponse = (nodes, { isProject = false, approximate = false } = {}) => {
  const report = { __typename: 'AiGovernanceToolCallsReport', nodes, approximate };

  return {
    data: {
      group: isProject
        ? null
        : { __typename: 'Group', id: 'gid://gitlab/Group/1', aiGovernanceToolCalls: report },
      project: isProject
        ? { __typename: 'Project', id: 'gid://gitlab/Project/2', aiGovernanceToolCalls: report }
        : null,
    },
  };
};

describe('ToolCallsCard', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = {}, handler } = {}) => {
    const apolloProvider = createMockApollo([
      [
        getAiGovernanceToolCallsQuery,
        handler ?? jest.fn().mockResolvedValue(toolCallsResponse([])),
      ],
    ]);

    wrapper = mountExtended(ToolCallsCard, {
      apolloProvider,
      propsData: props,
      provide: {
        projectId: null,
        groupFullPath: 'gitlab-duo',
        projectFullPath: null,
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAllByTestId('tool-call-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');
  const findApproximateNote = () => wrapper.findByTestId('approximate-note');
  const findAlert = () => wrapper.findComponent(GlAlert);

  it('renders a row per tool with name and call count', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(toolCallsResponse([toolNode('Bash', 4)])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    const row = findRows().at(0);
    expect(row.find('[data-testid="tool-name"]').text()).toBe('Bash');
    expect(row.find('[data-testid="tool-count"]').text()).toBe('4 calls');
  });

  it('shows the Tool management title and action type of a governed tool', async () => {
    createComponent({
      handler: jest.fn().mockResolvedValue(
        toolCallsResponse([
          toolNode('gitlab_merge_request_search', 2, {
            title: 'GitLab Merge Request Search',
            actionType: 'READ',
          }),
        ]),
      ),
    });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.find('[data-testid="tool-name"]').text()).toBe('GitLab Merge Request Search');
    expect(row.findComponent(GlBadge).text()).toBe('READ');
    expect(row.findComponent(GlBadge).props('variant')).toBe('info');
  });

  it.each([
    ['WRITE', 'warning'],
    ['DESTROY', 'danger'],
  ])('uses the Tool management badge variant for %s', async (actionType, variant) => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(toolCallsResponse([toolNode('run_command', 1, { actionType })])),
    });
    await waitForPromises();

    expect(findRows().at(0).findComponent(GlBadge).props('variant')).toBe(variant);
  });

  it('shows the recorded name without a badge when no rule governs the tool', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(toolCallsResponse([toolNode('orbit_invoke_command', 11)])),
    });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.find('[data-testid="tool-name"]').text()).toBe('orbit_invoke_command');
    expect(row.findComponent(GlBadge).exists()).toBe(false);
  });

  it('renders tools in the order returned by the backend', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(toolCallsResponse([toolNode('Bash', 9), toolNode('create_issue', 3)])),
    });
    await waitForPromises();

    const names = findRows().wrappers.map((row) => row.find('[data-testid="tool-name"]').text());
    expect(names).toEqual(['Bash', 'create_issue']);
  });

  it('shows the approximate note when the backend flags approximate counts', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(toolCallsResponse([toolNode('Bash', 4)], { approximate: true })),
    });
    await waitForPromises();

    expect(findApproximateNote().exists()).toBe(true);
  });

  it('hides the approximate note when counts are exact', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(toolCallsResponse([toolNode('Bash', 4)], { approximate: false })),
    });
    await waitForPromises();

    expect(findApproximateNote().exists()).toBe(false);
  });

  it('links to the tool management tab', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('aria-label')).toBe('View all tools in tool management');
    expect(findViewAllLink().text()).toBe('View all');
    expect(findViewAllLink().attributes('href')).toBe('?tab=tool-management');
  });

  it('queries tool calls scoped to the group', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        groupFullPath: 'gitlab-duo',
        isProject: false,
        timeframe: 'LAST_7_DAYS',
      }),
    );
  });

  it('queries tool calls scoped to the project in project mode', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([], { isProject: true }));
    createComponent({ provide: { projectId: '2', projectFullPath: 'gitlab-duo/test' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        projectFullPath: 'gitlab-duo/test',
        isProject: true,
      }),
    );
  });

  it('defaults to the ALL agent class', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'ALL' }));
  });

  it('segments the tool calls by the agent class it is given', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([]));
    createComponent({ props: { agentClass: 'INTERNAL_DAP' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'INTERNAL_DAP' }));
  });

  it('re-runs the query when the agent class changes', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([]));
    createComponent({ handler });
    await waitForPromises();

    await wrapper.setProps({ agentClass: 'EXTERNAL' });
    await waitForPromises();

    expect(handler).toHaveBeenLastCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
  });

  it('queries the timeframe it is given', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([]));
    createComponent({ props: { timeframe: 'LAST_30_DAYS' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(expect.objectContaining({ timeframe: 'LAST_30_DAYS' }));
  });

  it('re-runs the query when the timeframe changes', async () => {
    const handler = jest.fn().mockResolvedValue(toolCallsResponse([]));
    createComponent({ handler });
    await waitForPromises();

    await wrapper.setProps({ timeframe: 'LAST_30_DAYS' });
    await waitForPromises();

    expect(handler).toHaveBeenLastCalledWith(
      expect.objectContaining({ timeframe: 'LAST_30_DAYS' }),
    );
  });

  it('shows the empty state when there are no tool calls', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  it('shows the empty state when the backend returns no report', async () => {
    const response = toolCallsResponse([]);
    response.data.group.aiGovernanceToolCalls = null;
    createComponent({ handler: jest.fn().mockResolvedValue(response) });
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
    expect(findAlert().exists()).toBe(false);
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  it('clears the error alert when a later query succeeds', async () => {
    const handler = jest
      .fn()
      .mockRejectedValueOnce(new Error('failed'))
      .mockResolvedValue(toolCallsResponse([toolNode('Bash', 4)]));
    createComponent({ handler });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);

    await wrapper.setProps({ timeframe: 'LAST_30_DAYS' });
    await waitForPromises();

    expect(findAlert().exists()).toBe(false);
    expect(findRows()).toHaveLength(1);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(() => {
      createComponent();
    });

    it('marks the view-all link as a card link click on the top tools card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': 'click_card_link_on_ai_governance_dashboard',
        'data-event-label': 'top_tools',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a click on the view-all link', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="view-all-link"]');

      expect(trackEventSpy).toHaveBeenCalledWith('click_card_link_on_ai_governance_dashboard', {
        label: 'top_tools',
        property: 'view_all',
      });
    });
  });
});
