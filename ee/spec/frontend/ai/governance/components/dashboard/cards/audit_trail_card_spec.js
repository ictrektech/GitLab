import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import AuditTrailCard from 'ee/ai/governance/components/dashboard/cards/audit_trail_card.vue';
import getAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_agent_artifacts.query.graphql';
import getProjectAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_project_agent_artifacts.query.graphql';
import getAiGovernanceSessionsQuery from 'ee/ai/governance/graphql/queries/get_ai_governance_sessions.query.graphql';
import getProjectAiGovernanceSessionsQuery from 'ee/ai/governance/graphql/queries/get_project_ai_governance_sessions.query.graphql';

Vue.use(VueApollo);

const sessionNode = (id) => ({
  __typename: 'DuoWorkflowSessionArtifact',
  id: `gid://gitlab/Ai::DuoWorkflows::Workflow/${id}`,
  workflowDefinition: 'software_development',
  agentType: null,
  webPath: `/gitlab-duo/test/-/automate/agent-sessions/${id}`,
  downloadPath: `/download/${id}`,
  auditEventsCount: 3,
  workflowCreatedAt: '2026-07-01T10:00:00Z',
  project: {
    __typename: 'Project',
    id: 'gid://gitlab/Project/1',
    name: 'test',
    webPath: '/gitlab-duo/test',
    fullPath: 'gitlab-duo/test',
  },
  triggeredBy: {
    __typename: 'UserCore',
    id: 'gid://gitlab/User/1',
    name: 'Alice Smith',
    username: 'alice',
    avatarUrl: '/uploads/-/system/user/avatar/1/avatar.png',
    webPath: '/alice',
  },
});

const artifactsConnection = (nodes) => ({
  __typename: 'DuoWorkflowSessionArtifactConnection',
  count: nodes.length,
  nodes,
  pageInfo: {
    __typename: 'PageInfo',
    hasNextPage: false,
    hasPreviousPage: false,
    startCursor: null,
    endCursor: null,
  },
});

const governanceSessionNode = ({
  id = 77,
  sessionId = '246234',
  flowType = 'software_development',
  source = 'GITLAB_DUO',
  agentType = null,
  auditEventsCount = 3,
} = {}) => ({
  __typename: 'AiGovernanceSession',
  id: `gid://gitlab/Ai::Governance::Session/${id}`,
  sessionId,
  flowType,
  source,
  agentType,
  sessionStartedAt: '2026-07-01T10:00:00Z',
  auditEventsCount,
});

const sessionsConnection = (nodes) => ({
  __typename: 'AiGovernanceSessionConnection',
  nodes,
});

const groupSessionsResponse = (nodes) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      aiGovernanceSessions: sessionsConnection(nodes),
    },
  },
});

const projectSessionsResponse = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      aiGovernanceSessions: sessionsConnection(nodes),
    },
  },
});

const groupResponse = (nodes) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      duoWorkflowSessionArtifacts: artifactsConnection(nodes),
    },
  },
});

const projectResponse = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      duoWorkflowSessionArtifacts: artifactsConnection(nodes),
    },
  },
});

describe('AuditTrailCard', () => {
  let wrapper;

  const createComponent = ({
    provide = {},
    props = {},
    connectedAgentsFilter = true,
    sessionsApi = false,
    groupHandler,
    projectHandler,
    groupSessionsHandler,
    projectSessionsHandler,
  } = {}) => {
    const apolloProvider = createMockApollo([
      [getAgentArtifactsQuery, groupHandler ?? jest.fn().mockResolvedValue(groupResponse([]))],
      [
        getProjectAgentArtifactsQuery,
        projectHandler ?? jest.fn().mockResolvedValue(projectResponse([])),
      ],
      [
        getAiGovernanceSessionsQuery,
        groupSessionsHandler ?? jest.fn().mockResolvedValue(groupSessionsResponse([])),
      ],
      [
        getProjectAiGovernanceSessionsQuery,
        projectSessionsHandler ?? jest.fn().mockResolvedValue(projectSessionsResponse([])),
      ],
    ]);

    wrapper = mountExtended(AuditTrailCard, {
      apolloProvider,
      propsData: props,
      provide: {
        groupFullPath: 'gitlab-duo',
        projectFullPath: null,
        glFeatures: {
          aiGovernanceConnectedAgentsFilter: connectedAgentsFilter,
          aiGovernanceSessionsApi: sessionsApi,
        },
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAllByTestId('audit-trail-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  const findChevron = (row) => row.find('[data-testid="audit-trail-chevron"]');

  it('renders a row per recent session with a humanized title', async () => {
    createComponent({
      groupHandler: jest.fn().mockResolvedValue(groupResponse([sessionNode(246234)])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    expect(findRows().at(0).text()).toContain('Session #246234');
    expect(findRows().at(0).text()).toContain('3 audit events');
  });

  it('links a session to the audit events tab and shows a chevron', async () => {
    createComponent({
      groupHandler: jest.fn().mockResolvedValue(groupResponse([sessionNode(246234)])),
    });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.element.tagName).toBe('A');
    expect(row.attributes('href')).toBe('?tab=agent-artifacts&session=246234');
    expect(findChevron(row).exists()).toBe(true);
  });

  // The link is built from the session id rather than the backend's webPath,
  // so a session with no project still links. webPath pointed at the session's
  // own page, which 404s for anyone who did not run it.
  it('still links a session that has no webPath', async () => {
    const node = { ...sessionNode(246234), webPath: null };
    createComponent({ groupHandler: jest.fn().mockResolvedValue(groupResponse([node])) });
    await waitForPromises();

    const row = findRows().at(0);
    expect(row.element.tagName).toBe('A');
    expect(row.attributes('href')).toBe('?tab=agent-artifacts&session=246234');
  });

  it('links "View all audit logs" to the audit events tab', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe('?tab=agent-artifacts');
  });

  it('shows the empty state when there are no sessions', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ groupHandler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  // 19.4 ships this card with no agent-class filter. `INTERNAL_DAP` resolves
  // to `agent_type IS NULL`, which is narrower than sending nothing, so the
  // flag-off path must send no `agentClass` key at all.
  describe('with the connected agents filter flag off', () => {
    it('sends no agentClass for a group, matching the 19.4 query', async () => {
      const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
      createComponent({ connectedAgentsFilter: false, groupHandler });
      await waitForPromises();

      expect(groupHandler).toHaveBeenCalledWith({ groupFullPath: 'gitlab-duo', first: 5 });
    });

    it('sends no agentClass for a project, matching the 19.4 query', async () => {
      const projectHandler = jest.fn().mockResolvedValue(projectResponse([]));
      createComponent({
        connectedAgentsFilter: false,
        provide: { projectFullPath: 'gitlab-duo/test' },
        projectHandler,
      });
      await waitForPromises();

      expect(projectHandler).toHaveBeenCalledWith({
        projectFullPath: 'gitlab-duo/test',
        first: 5,
      });
    });

    it('ignores the agentClass prop it is given', async () => {
      const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
      createComponent({
        connectedAgentsFilter: false,
        props: { agentClass: 'INTERNAL_DAP' },
        groupHandler,
      });
      await waitForPromises();

      expect(groupHandler).toHaveBeenCalledWith({ groupFullPath: 'gitlab-duo', first: 5 });
    });
  });

  it('defaults to the ALL agent class', async () => {
    const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ groupHandler });
    await waitForPromises();

    expect(groupHandler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'ALL' }));
  });

  it('segments the sessions by the agent class it is given', async () => {
    const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ props: { agentClass: 'EXTERNAL' }, groupHandler });
    await waitForPromises();

    expect(groupHandler).toHaveBeenCalledWith(expect.objectContaining({ agentClass: 'EXTERNAL' }));
  });

  it('re-runs the query when the agent class changes', async () => {
    const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
    createComponent({ groupHandler });
    await waitForPromises();

    await wrapper.setProps({ agentClass: 'INTERNAL_DAP' });
    await waitForPromises();

    expect(groupHandler).toHaveBeenLastCalledWith(
      expect.objectContaining({ agentClass: 'INTERNAL_DAP' }),
    );
  });

  it('uses the project-level query in project mode', async () => {
    const projectHandler = jest.fn().mockResolvedValue(projectResponse([sessionNode(1)]));
    createComponent({ provide: { projectFullPath: 'gitlab-duo/test' }, projectHandler });
    await waitForPromises();

    expect(projectHandler).toHaveBeenCalledWith(
      expect.objectContaining({ projectFullPath: 'gitlab-duo/test', first: 5, agentClass: 'ALL' }),
    );
    expect(findRows()).toHaveLength(1);
  });

  describe('with the sessions API flag on', () => {
    it('reads aiGovernanceSessions instead of the workflow artifacts', async () => {
      const groupHandler = jest.fn().mockResolvedValue(groupResponse([]));
      const groupSessionsHandler = jest
        .fn()
        .mockResolvedValue(groupSessionsResponse([governanceSessionNode()]));
      createComponent({ sessionsApi: true, groupHandler, groupSessionsHandler });
      await waitForPromises();

      expect(groupSessionsHandler).toHaveBeenCalledWith({
        groupFullPath: 'gitlab-duo',
        first: 5,
        agentClass: 'ALL',
      });
      expect(groupHandler).not.toHaveBeenCalled();
      expect(findRows()).toHaveLength(1);
    });

    // The audit events tab opens its drawer by Duo workflow id, so the link
    // carries `sessionId`, not the session row id.
    it('titles a Duo session by its workflow id and flow type, shows its count and source, and links its drawer', async () => {
      createComponent({
        sessionsApi: true,
        groupSessionsHandler: jest
          .fn()
          .mockResolvedValue(groupSessionsResponse([governanceSessionNode()])),
      });
      await waitForPromises();

      const row = findRows().at(0);
      expect(row.text()).toContain('Session #246234 · Software development');
      expect(row.find('.gl-text-sm').text()).toBe('3 audit events · GitLab Duo');
      expect(row.attributes('href')).toBe('?tab=agent-artifacts&session=246234');
    });

    it('names an external session by its agent, shows the count alone, and links to its drawer', async () => {
      const node = governanceSessionNode({
        id: 78,
        sessionId: 'sess_9f2c',
        flowType: null,
        source: 'CLAUDE_CODE_GLAB',
        auditEventsCount: 2,
      });
      createComponent({
        sessionsApi: true,
        groupSessionsHandler: jest.fn().mockResolvedValue(groupSessionsResponse([node])),
      });
      await waitForPromises();

      const row = findRows().at(0);
      expect(row.text()).toContain('Session #sess_9f2c done by Claude Code (glab)');
      expect(row.find('.gl-text-sm').text()).toBe('2 audit events');
      expect(row.attributes('href')).toBe('?tab=agent-artifacts&session=sess_9f2c');
    });

    it.each([
      ['CLAUDE_CODE_GLAB', 'cursor', 'Cursor (glab)'],
      ['CLAUDE_CODE_GLAB', 'codex', 'Codex (glab)'],
      ['CLAUDE_CODE_GLAB', 'claude-code', 'Claude Code (glab)'],
      ['CLAUDE_CODE_GLAB', null, 'Claude Code (glab)'],
      ['CLAUDE_CODE_COMPLIANCE_API', 'claude-code', 'Claude Code (Compliance API)'],
    ])(
      'names a %s session with the %s agent type after its agent',
      async (source, agentType, label) => {
        const node = governanceSessionNode({
          sessionId: 'sess_9f2c',
          flowType: null,
          source,
          agentType,
        });
        createComponent({
          sessionsApi: true,
          groupSessionsHandler: jest.fn().mockResolvedValue(groupSessionsResponse([node])),
        });
        await waitForPromises();

        expect(findRows().at(0).text()).toContain(`Session #sess_9f2c done by ${label}`);
      },
    );

    it.each([
      ['5f1c2e9a-0b7d-4c3e-9a21-6d8e4f0b1c2a', 'Session #5f1c2e9a done by Cursor (glab)'],
      ['sess_9f2c', 'Session #sess_9f2c done by Cursor (glab)'],
    ])('shortens the external session id %s only when it is a UUID', async (sessionId, title) => {
      const node = governanceSessionNode({
        sessionId,
        flowType: null,
        source: 'CLAUDE_CODE_GLAB',
        agentType: 'cursor',
      });
      createComponent({
        sessionsApi: true,
        groupSessionsHandler: jest.fn().mockResolvedValue(groupSessionsResponse([node])),
      });
      await waitForPromises();

      expect(findRows().at(0).text()).toContain(title);
    });

    it('keeps the full id and the flow type in a GitLab Duo session title', async () => {
      const node = governanceSessionNode({ sessionId: '5f1c2e9a-0b7d-4c3e-9a21-6d8e4f0b1c2a' });
      createComponent({
        sessionsApi: true,
        groupSessionsHandler: jest.fn().mockResolvedValue(groupSessionsResponse([node])),
      });
      await waitForPromises();

      expect(findRows().at(0).text()).toContain(
        'Session #5f1c2e9a-0b7d-4c3e-9a21-6d8e4f0b1c2a · Software development',
      );
    });

    it('renders an unknown source with the flow type name and the count alone', async () => {
      const node = governanceSessionNode({ id: 79, sessionId: 'x1', source: 'SOMETHING_NEW' });
      createComponent({
        sessionsApi: true,
        groupSessionsHandler: jest.fn().mockResolvedValue(groupSessionsResponse([node])),
      });
      await waitForPromises();

      const row = findRows().at(0);
      expect(row.text()).toContain('Session #x1 · Software development');
      expect(row.text()).not.toContain('undefined');
      expect(row.find('.gl-text-sm').text()).toBe('3 audit events');
    });

    it('shows a zero count as "0 audit events"', async () => {
      const node = governanceSessionNode({ id: 80, sessionId: '1', auditEventsCount: 0 });
      createComponent({
        sessionsApi: true,
        groupSessionsHandler: jest.fn().mockResolvedValue(groupSessionsResponse([node])),
      });
      await waitForPromises();

      expect(findRows().at(0).find('.gl-text-sm').text()).toBe('0 audit events · GitLab Duo');
    });

    it('uses the project-level sessions query in project mode', async () => {
      const projectSessionsHandler = jest
        .fn()
        .mockResolvedValue(projectSessionsResponse([governanceSessionNode()]));
      createComponent({
        sessionsApi: true,
        provide: { projectFullPath: 'gitlab-duo/test' },
        projectSessionsHandler,
      });
      await waitForPromises();

      expect(projectSessionsHandler).toHaveBeenCalledWith({
        projectFullPath: 'gitlab-duo/test',
        first: 5,
        agentClass: 'ALL',
      });
      expect(findRows()).toHaveLength(1);
    });
  });

  it('states the 180-day window and that it is not scoped to the selected date range', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findByTestId('card-footnote').text()).toBe(
      'Shows the last 180 days, not filtered by date range.',
    );
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const CARD_LINK_EVENT = 'click_card_link_on_ai_governance_dashboard';

    beforeEach(async () => {
      createComponent({
        groupHandler: jest.fn().mockResolvedValue(groupResponse([sessionNode(246234)])),
      });
      await waitForPromises();
    });

    it('marks each row as a card link click on the audit trail card', () => {
      expect(findRows().at(0).attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'audit_trail',
        'data-event-property': 'row',
      });
    });

    it('marks the view-all link as a card link click on the audit trail card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'audit_trail',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a row click', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="audit-trail-row"]');

      expect(trackEventSpy).toHaveBeenCalledWith(CARD_LINK_EVENT, {
        label: 'audit_trail',
        property: 'row',
      });
    });
  });
});
