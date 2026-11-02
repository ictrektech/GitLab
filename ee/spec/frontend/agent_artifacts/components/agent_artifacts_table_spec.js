import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  GlAvatar,
  GlKeysetPagination,
  GlTruncate,
  GlLoadingIcon,
  GlAlert,
  GlIcon,
} from '@gitlab/ui';
import { formatDate } from '~/lib/utils/datetime_utility';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import AgentArtifactsTable from 'ee/agent_artifacts/components/agent_artifacts_table.vue';
import getAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_agent_artifacts.query.graphql';
import getProjectAgentArtifactsQuery from 'ee/agent_artifacts/graphql/queries/get_project_agent_artifacts.query.graphql';
import getAiGovernanceSessionsQuery from 'ee/agent_artifacts/graphql/queries/get_agent_artifacts_ai_governance_sessions.query.graphql';
import getProjectAiGovernanceSessionsQuery from 'ee/agent_artifacts/graphql/queries/get_project_agent_artifacts_ai_governance_sessions.query.graphql';
import { normalizeLegacySession } from 'ee/agent_artifacts/utils';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { DEFAULT_CLIENT_TYPE } from 'ee/agent_artifacts/constants';
import {
  mockArtifactNodes,
  mockArtifactNodeNoWebPath,
  mockPageInfo,
  mockAgentArtifactsResponse,
  mockProjectAgentArtifactsResponse,
  mockEmptyAgentArtifactsResponse,
  mockUser,
  mockGitlabDuoSessionNode,
  mockClaudeCodeSessionNode,
  mockAiGovernanceSessionsResponse,
  mockProjectAiGovernanceSessionsResponse,
} from '../mock_data';

Vue.use(VueApollo);

const GROUP_FULL_PATH = 'gitlab-org';
const PROJECT_FULL_PATH = 'g/p';

describe('AgentArtifactsTable', () => {
  let wrapper;

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(mockAgentArtifactsResponse),
    filter = {},
    provide = {},
    deepLinkedSessionId = null,
  } = {}) => {
    const apolloProvider = createMockApollo([[getAgentArtifactsQuery, handler]]);

    wrapper = mountExtended(AgentArtifactsTable, {
      apolloProvider,
      provide: {
        groupFullPath: GROUP_FULL_PATH,
        ...provide,
      },
      propsData: {
        filter,
        deepLinkedSessionId,
      },
      stubs: {
        GlTruncate,
      },
    });

    return handler;
  };

  const findPagination = () => wrapper.findComponent(GlKeysetPagination);

  describe('deep-linked session', () => {
    // The drawer needs the loaded row, not just an id, so it can only open
    // after the query resolves.
    const firstId = () =>
      String(
        getIdFromGraphQLId(
          mockAgentArtifactsResponse.data.group.duoWorkflowSessionArtifacts.nodes[0].id,
        ),
      );

    it('emits row-click for the matching session once the rows load', async () => {
      createComponent({ deepLinkedSessionId: firstId() });
      await waitForPromises();

      const emitted = wrapper.emitted('row-click');
      expect(emitted).toHaveLength(1);
      expect(String(getIdFromGraphQLId(emitted[0][0].id))).toBe(firstId());
    });

    it('emits nothing when the id is not on this page', async () => {
      createComponent({ deepLinkedSessionId: '99999999' });
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toBeUndefined();
    });

    // Consumed on the first resolution whether or not it matched, so a later
    // page containing that session does not pop the drawer open unexpectedly.
    it('does not reopen the drawer when the session appears on a later page', async () => {
      const handler = jest
        .fn()
        .mockResolvedValueOnce(mockEmptyAgentArtifactsResponse)
        .mockResolvedValueOnce(mockAgentArtifactsResponse);

      createComponent({ handler, deepLinkedSessionId: firstId() });
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toBeUndefined();

      // A later fetch that DOES contain the session must not open the drawer.
      await wrapper.setProps({ filter: { projectPath: 'g/p' } });
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toBeUndefined();
      expect(wrapper.emitted('deep-link-missed')).toHaveLength(1);
    });

    it('emits nothing when there is no deep link', async () => {
      createComponent();
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toBeUndefined();
      expect(wrapper.emitted('deep-link-missed')).toBeUndefined();
    });
  });

  describe('the 180-day window note on the legacy field', () => {
    it('names the 180 days shown when the filter spans more than 180 days', async () => {
      createComponent({ filter: { startTimeAfter: '2025-01-01', startTimeBefore: '2026-01-15' } });
      await waitForPromises();

      expect(wrapper.findByTestId('clamped-window-alert').text()).toBe(
        'Showing the 180 days before Jan 15, 2026. Sessions are listed for up to 180 days at a time.',
      );
    });
  });

  describe('when loading', () => {
    beforeEach(() => {
      createComponent({ handler: jest.fn().mockReturnValue(new Promise(() => {})) });
    });

    it('shows the table with busy state', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    });
  });

  describe('when data is loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('displays ai items', () => {
      const truncate = wrapper.findByTestId('ai-item-name').findComponent(GlTruncate);
      expect(truncate.props('text')).toBe('False positive detection/v1');
    });

    // Plain text, not a link: the row already opens the drawer, and the old
    // link went to the session's own page, which 404s for anyone else.
    it('renders the session id as text', () => {
      const ids = wrapper.findAllByTestId('session-link');
      expect(ids).toHaveLength(2);
      expect(ids.at(0).attributes('href')).toBeUndefined();
      expect(ids.at(0).text()).toBe('#1908');
    });

    it('displays audit events count', () => {
      const auditCounts = wrapper.findAllByTestId('audit-events-count');
      expect(auditCounts).toHaveLength(2);
      expect(auditCounts.at(0).text()).toBe(`${mockArtifactNodes[0].auditEventsCount}`);
    });

    it('shows a zero audit events count rather than a dash', async () => {
      const { duoWorkflowSessionArtifacts } = mockAgentArtifactsResponse.data.group;
      createComponent({
        handler: jest.fn().mockResolvedValue({
          data: {
            group: {
              ...mockAgentArtifactsResponse.data.group,
              duoWorkflowSessionArtifacts: {
                ...duoWorkflowSessionArtifacts,
                nodes: [{ ...mockArtifactNodes[0], auditEventsCount: 0 }],
              },
            },
          },
        }),
      });
      await waitForPromises();

      expect(wrapper.findByTestId('audit-events-count').text()).toBe('0');
      expect(wrapper.findByTestId('audit-events-empty').exists()).toBe(false);
    });

    it('renders project links', () => {
      const { project } = mockArtifactNodes[0];
      const projectLinks = wrapper.findAllByTestId('project-link');
      expect(projectLinks).toHaveLength(2);
      expect(projectLinks.at(0).attributes('href')).toBe(project.webPath);
      const truncate = projectLinks.at(0).findComponent(GlTruncate);
      expect(truncate.props('text')).toBe(project.name);
    });

    it('displays formatted start time', () => {
      const startTimes = wrapper.findAllByTestId('start-time');
      expect(startTimes).toHaveLength(2);
      expect(startTimes.at(0).text()).toContain('2026-03-05');
      expect(startTimes.at(0).text()).toContain('22:14:17');
    });

    describe('user column', () => {
      it('renders the user name link when triggeredBy is present', () => {
        const userLinks = wrapper.findAllByTestId('user-link');
        expect(userLinks).toHaveLength(2);
        expect(userLinks.at(0).attributes('href')).toBe(mockUser.webPath);
        expect(userLinks.at(0).text()).toBe(mockUser.name);
      });

      it('renders the user avatar when triggeredBy is present', () => {
        const userAvatars = wrapper.findAllByTestId('user-avatar');
        expect(userAvatars).toHaveLength(2);
      });
    });

    describe('aiItem client type display', () => {
      it('renders the client type icon when the client type has an icon', () => {
        const icon = wrapper.findByTestId('ai-item-client-type-icon').findComponent(GlIcon);
        expect(icon.exists()).toBe(true);
        expect(icon.props('name')).toBe(DEFAULT_CLIENT_TYPE.icon);
      });

      it('renders the client type name', () => {
        expect(wrapper.findByTestId('ai-item-client-type-name').text()).toBe(
          DEFAULT_CLIENT_TYPE.name,
        );
      });

      describe('when a session was run by an external agent', () => {
        it('renders an initial avatar instead of a sprite icon', () => {
          const cell = wrapper.findAllByTestId('ai-item-client-type-icon').at(1);
          const avatar = cell.findComponent(GlAvatar);

          expect(avatar.exists()).toBe(true);
          expect(avatar.props('entityName')).toBe('Claude Code');
          expect(cell.findComponent(GlIcon).exists()).toBe(false);
        });

        it('renders the agent type name', () => {
          expect(wrapper.findAllByTestId('ai-item-client-type-name').at(1).text()).toBe(
            'Claude Code',
          );
        });
      });
    });
  });

  describe('empty cell fallbacks', () => {
    beforeEach(async () => {
      const handler = jest.fn().mockResolvedValue({
        data: {
          group: {
            id: 'gid://gitlab/Group/1',
            duoWorkflowSessionArtifacts: {
              count: 1,
              nodes: [mockArtifactNodeNoWebPath],
              pageInfo: { ...mockPageInfo, hasNextPage: false, hasPreviousPage: false },
              __typename: 'DuoWorkflowSessionArtifactConnection',
            },
            __typename: 'Group',
          },
        },
      });
      createComponent({ handler });
      await waitForPromises();
    });

    it('still renders the session id when webPath is null', () => {
      expect(wrapper.findByTestId('session-link').exists()).toBe(true);
      expect(wrapper.findByTestId('session-empty').exists()).toBe(false);
    });

    it('renders a hyphen instead of a project link when project is null', () => {
      expect(wrapper.findByTestId('project-link').exists()).toBe(false);
      expect(wrapper.findByTestId('project-empty').text()).toBe('—');
    });

    it('renders a hyphen instead of a user link when triggeredBy is null', () => {
      expect(wrapper.findByTestId('user-link').exists()).toBe(false);
      expect(wrapper.findByTestId('user-empty').text()).toBe('—');
    });
  });

  describe('pagination', () => {
    describe('when pages available', () => {
      let handler;

      beforeEach(async () => {
        handler = createComponent();
        await waitForPromises();
      });

      it('renders pagination', () => {
        expect(findPagination().exists()).toBe(true);
      });

      it('fetches next page when pagination emits next', async () => {
        findPagination().vm.$emit('next', mockPageInfo.endCursor);
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ after: mockPageInfo.endCursor, before: null }),
        );
      });

      it('fetches previous page when pagination emits prev', async () => {
        findPagination().vm.$emit('prev', mockPageInfo.startCursor);
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ before: mockPageInfo.startCursor, after: null }),
        );
      });
    });

    describe('when no pages available', () => {
      it('does not render pagination', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(mockEmptyAgentArtifactsResponse),
        });
        await waitForPromises();

        expect(findPagination().exists()).toBe(false);
      });
    });
  });

  describe('empty state', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(mockEmptyAgentArtifactsResponse),
      });
      await waitForPromises();
    });

    it('shows empty state message', () => {
      expect(wrapper.text()).toContain('No agent artifacts found.');
    });

    describe('when AI audit event storage is disabled', () => {
      const SETTINGS_PATH = '/groups/gitlab-org/-/settings/gitlab_duo/configuration';

      it('shows the storage disabled nudge when storage is disabled and no filter is active', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(mockEmptyAgentArtifactsResponse),
          provide: {
            aiAuditEventsStorageEnabled: false,
            aiAuditEventsSettingsPath: SETTINGS_PATH,
          },
        });
        await waitForPromises();

        expect(wrapper.findByTestId('storage-disabled-empty-state').exists()).toBe(true);
        expect(wrapper.text()).not.toContain('No agent artifacts found.');
        expect(wrapper.findByTestId('enable-storage-link').attributes('href')).toBe(SETTINGS_PATH);
      });

      it('shows the generic empty state when a filter is active', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(mockEmptyAgentArtifactsResponse),
          filter: { name: 'Test Agent' },
          provide: {
            aiAuditEventsStorageEnabled: false,
            aiAuditEventsSettingsPath: SETTINGS_PATH,
          },
        });
        await waitForPromises();

        expect(wrapper.findByTestId('storage-disabled-empty-state').exists()).toBe(false);
        expect(wrapper.text()).toContain('No agent artifacts found.');
      });

      it('shows the storage disabled nudge in project mode with the project settings path', async () => {
        const PROJECT_SETTINGS_PATH = '/g/p/-/edit#js-gitlab-duo-settings';
        const emptyProjectResponse = {
          data: {
            project: {
              id: 'gid://gitlab/Project/1',
              duoWorkflowSessionArtifacts: {
                count: 0,
                nodes: [],
                pageInfo: {
                  startCursor: null,
                  endCursor: null,
                  hasNextPage: false,
                  hasPreviousPage: false,
                  __typename: 'PageInfo',
                },
                __typename: 'DuoWorkflowSessionArtifactConnection',
              },
              __typename: 'Project',
            },
          },
        };
        const handler = jest.fn().mockResolvedValue(emptyProjectResponse);
        const apolloProvider = createMockApollo([[getProjectAgentArtifactsQuery, handler]]);

        wrapper = mountExtended(AgentArtifactsTable, {
          apolloProvider,
          provide: {
            groupFullPath: null,
            projectFullPath: PROJECT_FULL_PATH,
            aiAuditEventsStorageEnabled: false,
            aiAuditEventsSettingsPath: PROJECT_SETTINGS_PATH,
          },
          propsData: {
            filter: {},
          },
          stubs: {
            GlTruncate,
          },
        });
        await waitForPromises();

        expect(wrapper.findByTestId('storage-disabled-empty-state').exists()).toBe(true);
        expect(wrapper.text()).not.toContain('No agent artifacts found.');
        expect(wrapper.findByTestId('enable-storage-link').attributes('href')).toBe(
          PROJECT_SETTINGS_PATH,
        );
      });

      it('renders the nudge as plain text with no link when the settings path is empty', async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue(mockEmptyAgentArtifactsResponse),
          provide: {
            aiAuditEventsStorageEnabled: false,
            aiAuditEventsSettingsPath: '',
          },
        });
        await waitForPromises();

        expect(wrapper.findByTestId('storage-disabled-empty-state').exists()).toBe(true);
        expect(wrapper.findByTestId('enable-storage-link').exists()).toBe(false);
        expect(wrapper.text()).toContain('AI audit event storage is turned off');
        expect(wrapper.text()).toContain('Turn on storage');
      });
    });

    it('shows the generic empty state when storage is enabled', async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(mockEmptyAgentArtifactsResponse),
        provide: {
          aiAuditEventsStorageEnabled: true,
          aiAuditEventsSettingsPath: '/groups/gitlab-org/-/settings/gitlab_duo/configuration',
        },
      });
      await waitForPromises();

      expect(wrapper.findByTestId('storage-disabled-empty-state').exists()).toBe(false);
      expect(wrapper.text()).toContain('No agent artifacts found.');
    });
  });

  describe('error state', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockRejectedValue(new Error('GraphQL error')),
      });
      await waitForPromises();
    });

    it('shows error alert', () => {
      const alert = wrapper.findComponent(GlAlert);
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('Failed to load agent artifacts.');
    });

    it('does not show the storage disabled nudge on error, even when storage is disabled', async () => {
      createComponent({
        handler: jest.fn().mockRejectedValue(new Error('GraphQL error')),
        provide: {
          aiAuditEventsStorageEnabled: false,
          aiAuditEventsSettingsPath: '/groups/gitlab-org/-/settings/gitlab_duo/configuration',
        },
      });
      await waitForPromises();

      expect(wrapper.findComponent(GlAlert).exists()).toBe(true);
      expect(wrapper.findByTestId('storage-disabled-empty-state').exists()).toBe(false);
    });
  });

  describe('row click handling', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('emits row-click event when a row is clicked', async () => {
      const rows = wrapper.findAllByTestId('agent-artifacts-table-row');
      await rows.at(0).trigger('click');

      expect(wrapper.emitted('row-click')).toHaveLength(1);
      expect(wrapper.emitted('row-click')[0][0]).toEqual(
        normalizeLegacySession(mockArtifactNodes[0]),
      );
    });
  });

  describe('filtering', () => {
    it('passes filter to GraphQL query', async () => {
      const filter = { name: 'Test Agent' };
      const handler = createComponent({ filter });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(expect.objectContaining(filter));
    });

    it('passes not filter to GraphQL query', async () => {
      const filter = { not: { name: 'Excluded Agent' } };
      const handler = createComponent({ filter });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(expect.objectContaining(filter));
    });

    it('resets pagination when filter changes', async () => {
      const handler = createComponent({ filter: { name: 'Initial' } });
      await waitForPromises();

      findPagination().vm.$emit('next', mockPageInfo.endCursor);
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({ after: mockPageInfo.endCursor }),
      );

      await wrapper.setProps({ filter: { name: 'Updated' } });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(expect.objectContaining({ after: null, before: null }));
    });
  });

  describe('when neither groupFullPath nor projectFullPath is provided', () => {
    it('skips the query', async () => {
      const handler = createComponent({ provide: { groupFullPath: null } });
      await waitForPromises();

      expect(handler).not.toHaveBeenCalled();
    });
  });

  describe('project mode', () => {
    let handler;

    const createProjectComponent = () => {
      handler = jest.fn().mockResolvedValue(mockProjectAgentArtifactsResponse);
      const apolloProvider = createMockApollo([[getProjectAgentArtifactsQuery, handler]]);

      wrapper = mountExtended(AgentArtifactsTable, {
        apolloProvider,
        provide: {
          groupFullPath: null,
          projectFullPath: PROJECT_FULL_PATH,
        },
        propsData: {
          filter: {},
        },
        stubs: {
          GlTruncate,
        },
      });
    };

    beforeEach(async () => {
      createProjectComponent();
      await waitForPromises();
    });

    it('queries the project query with projectFullPath and no group/project path vars', () => {
      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({ projectFullPath: PROJECT_FULL_PATH }),
      );
      const variables = handler.mock.calls[0][0];
      expect(variables).not.toHaveProperty('groupFullPath');
      expect(variables).not.toHaveProperty('projectPath');
    });

    it('renders rows from data.project.duoWorkflowSessionArtifacts', () => {
      expect(wrapper.findAllByTestId('session-link')).toHaveLength(mockArtifactNodes.length);
    });

    it('hides the redundant Project column', () => {
      expect(wrapper.findAllByTestId('project-link')).toHaveLength(0);
      expect(wrapper.findAll('th').wrappers.map((th) => th.text())).not.toContain('Project');
    });
  });

  describe('group mode', () => {
    let handler;

    beforeEach(async () => {
      handler = createComponent();
      await waitForPromises();
    });

    it('queries the group query with groupFullPath', () => {
      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({ groupFullPath: GROUP_FULL_PATH }),
      );
    });

    it('renders rows from data.group.duoWorkflowSessionArtifacts', () => {
      expect(wrapper.findAllByTestId('session-link')).toHaveLength(mockArtifactNodes.length);
    });
  });
  describe('when the aiGovernanceSessionsApi feature flag is enabled', () => {
    let legacyHandler;
    let sessionsHandler;

    const createSessionsComponent = ({
      handler = jest.fn().mockResolvedValue(mockAiGovernanceSessionsResponse),
      deepLinkedSessionId = null,
      filter = {},
    } = {}) => {
      legacyHandler = jest.fn().mockResolvedValue(mockAgentArtifactsResponse);
      sessionsHandler = handler;

      wrapper = mountExtended(AgentArtifactsTable, {
        apolloProvider: createMockApollo([
          [getAgentArtifactsQuery, legacyHandler],
          [getAiGovernanceSessionsQuery, sessionsHandler],
        ]),
        provide: {
          groupFullPath: GROUP_FULL_PATH,
          glFeatures: { aiGovernanceSessionsApi: true },
        },
        propsData: { filter, deepLinkedSessionId },
        stubs: { GlTruncate },
      });
    };

    const findClampedWindowAlert = () => wrapper.findByTestId('clamped-window-alert');

    describe('the 180-day window note', () => {
      it('is hidden without a date filter', async () => {
        createSessionsComponent();
        await waitForPromises();

        expect(findClampedWindowAlert().exists()).toBe(false);
      });

      it('is hidden when the filter spans 180 days or less', async () => {
        createSessionsComponent({
          filter: { startTimeAfter: '2026-01-01', startTimeBefore: '2026-06-30' },
        });
        await waitForPromises();

        expect(findClampedWindowAlert().exists()).toBe(false);
      });

      it('counts UTC calendar days, so a 181-day span shows the note in every timezone', async () => {
        createSessionsComponent({
          filter: { startTimeAfter: '2026-01-01', startTimeBefore: '2026-07-01' },
        });
        await waitForPromises();

        expect(findClampedWindowAlert().text()).toContain('before Jul 1, 2026.');
      });

      it('names the 180 days shown when the filter spans more than 180 days', async () => {
        createSessionsComponent({
          filter: { startTimeAfter: '2025-01-01', startTimeBefore: '2026-01-15' },
        });
        await waitForPromises();

        expect(findClampedWindowAlert().text()).toBe(
          'Showing the 180 days before Jan 15, 2026. Sessions are listed for up to 180 days at a time.',
        );
      });

      it('shows the note when only "Created before" is set', async () => {
        createSessionsComponent({ filter: { startTimeBefore: '2025-03-01' } });
        await waitForPromises();

        expect(findClampedWindowAlert().text()).toBe(
          'Showing the 180 days before Mar 1, 2025. Sessions are listed for up to 180 days at a time.',
        );
      });

      it('counts up to today when only "Created after" is set', async () => {
        createSessionsComponent({ filter: { startTimeAfter: '2020-01-01' } });
        await waitForPromises();

        expect(findClampedWindowAlert().text()).toContain(
          `before ${formatDate(new Date(), 'mmm d, yyyy', true)}.`,
        );
      });
    });

    describe('in group mode', () => {
      beforeEach(async () => {
        createSessionsComponent();
        await waitForPromises();
      });

      it('queries aiGovernanceSessions instead of duoWorkflowSessionArtifacts', () => {
        expect(sessionsHandler).toHaveBeenCalledWith(
          expect.objectContaining({ groupFullPath: GROUP_FULL_PATH }),
        );
        expect(legacyHandler).not.toHaveBeenCalled();
      });

      it('renders the source session id, not the global id', () => {
        const ids = wrapper.findAllByTestId('session-link');

        expect(ids.at(0).text()).toBe(`#${mockGitlabDuoSessionNode.sessionId}`);
        expect(ids.at(1).text()).toBe(`#${mockClaudeCodeSessionNode.sessionId}`);
      });

      it('names a session by its flow type', () => {
        expect(wrapper.findAllByTestId('ai-item-name').at(0).text()).toBe(
          'False positive detection/v1',
        );
      });

      it('names a session without a flow type by its source', () => {
        expect(wrapper.findAllByTestId('ai-item-name').at(1).text()).toBe('Claude Code (glab)');
      });

      it('displays the audit events count of each session', () => {
        const auditCounts = wrapper.findAllByTestId('audit-events-count');

        expect(auditCounts).toHaveLength(2);
        expect(auditCounts.at(0).text()).toBe(`${mockGitlabDuoSessionNode.auditEventsCount}`);
        expect(auditCounts.at(1).text()).toBe(`${mockClaudeCodeSessionNode.auditEventsCount}`);
        expect(wrapper.findByTestId('audit-events-empty').exists()).toBe(false);
      });

      it('displays the session start time', () => {
        const startTime = wrapper.findAllByTestId('start-time').at(0);

        expect(startTime.text()).toContain('2026-03-05');
        expect(startTime.text()).toContain('22:14:17');
      });

      it('emits the session row unchanged on click', async () => {
        await wrapper.findAllByTestId('agent-artifacts-table-row').at(1).trigger('click');

        expect(wrapper.emitted('row-click')[0][0]).toEqual(mockClaudeCodeSessionNode);
      });
    });

    it('passes the filter through unchanged', async () => {
      const filter = { name: 'code_review/v1', not: { projectPath: 'g/p' } };
      legacyHandler = jest.fn();
      sessionsHandler = jest.fn().mockResolvedValue(mockAiGovernanceSessionsResponse);

      wrapper = mountExtended(AgentArtifactsTable, {
        apolloProvider: createMockApollo([[getAiGovernanceSessionsQuery, sessionsHandler]]),
        provide: {
          groupFullPath: GROUP_FULL_PATH,
          glFeatures: { aiGovernanceSessionsApi: true },
        },
        propsData: { filter },
      });
      await waitForPromises();

      expect(sessionsHandler).toHaveBeenCalledWith(expect.objectContaining(filter));
    });

    it.each([
      ['cursor', 'Cursor (glab)'],
      ['codex', 'Codex (glab)'],
      ['claude-code', 'Claude Code (glab)'],
      [null, 'Claude Code (glab)'],
    ])('names a glab session with the %s agent type after its agent', async (agentType, label) => {
      const handler = jest.fn().mockResolvedValue({
        data: {
          group: {
            ...mockAiGovernanceSessionsResponse.data.group,
            aiGovernanceSessions: {
              ...mockAiGovernanceSessionsResponse.data.group.aiGovernanceSessions,
              nodes: [{ ...mockClaudeCodeSessionNode, agentType }],
            },
          },
        },
      });
      createSessionsComponent({ handler });
      await waitForPromises();

      expect(wrapper.findByTestId('ai-item-name').text()).toBe(label);
    });

    it('shows a dash when a session has no session id', async () => {
      const handler = jest.fn().mockResolvedValue({
        data: {
          group: {
            ...mockAiGovernanceSessionsResponse.data.group,
            aiGovernanceSessions: {
              ...mockAiGovernanceSessionsResponse.data.group.aiGovernanceSessions,
              nodes: [{ ...mockGitlabDuoSessionNode, sessionId: null }],
            },
          },
        },
      });
      createSessionsComponent({ handler });
      await waitForPromises();

      expect(wrapper.findByTestId('session-link').exists()).toBe(false);
      expect(wrapper.findByTestId('session-id-empty').text()).toBe('—');
    });

    it('shows a dash when a session has no audit events count', async () => {
      const handler = jest.fn().mockResolvedValue({
        data: {
          group: {
            ...mockAiGovernanceSessionsResponse.data.group,
            aiGovernanceSessions: {
              ...mockAiGovernanceSessionsResponse.data.group.aiGovernanceSessions,
              nodes: [{ ...mockGitlabDuoSessionNode, auditEventsCount: null }],
            },
          },
        },
      });
      createSessionsComponent({ handler });
      await waitForPromises();

      expect(wrapper.findByTestId('audit-events-count').exists()).toBe(false);
      expect(wrapper.findByTestId('audit-events-empty').text()).toBe('—');
    });

    it.each([
      ['a GitLab Duo session by its workflow id', mockGitlabDuoSessionNode],
      ['an external session by its own session id', mockClaudeCodeSessionNode],
    ])('opens the deep-linked session, matching %s', async (_, node) => {
      createSessionsComponent({ deepLinkedSessionId: node.sessionId });
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toEqual([[node]]);
    });

    it('does not match a deep link against the global id', async () => {
      createSessionsComponent({ deepLinkedSessionId: '501' });
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toBeUndefined();
      expect(wrapper.emitted('deep-link-missed')).toHaveLength(1);
    });

    it('queries aiGovernanceSessions in project mode', async () => {
      const handler = jest.fn().mockResolvedValue(mockProjectAiGovernanceSessionsResponse);

      wrapper = mountExtended(AgentArtifactsTable, {
        apolloProvider: createMockApollo([[getProjectAiGovernanceSessionsQuery, handler]]),
        provide: {
          groupFullPath: null,
          projectFullPath: PROJECT_FULL_PATH,
          glFeatures: { aiGovernanceSessionsApi: true },
        },
        propsData: { filter: {} },
        stubs: { GlTruncate },
      });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({ projectFullPath: PROJECT_FULL_PATH }),
      );
      expect(wrapper.findAllByTestId('session-link')).toHaveLength(2);
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const LINKED_ITEM_EVENT = 'click_linked_item_on_ai_audit_events_report';
    let trackEventSpy;

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
      ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
    });

    it('tracks a session opened by a row click', async () => {
      await wrapper.findAllByTestId('agent-artifacts-table-row').at(0).trigger('click');

      expect(wrapper.emitted('row-click')).toHaveLength(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'open_session_on_ai_audit_events_report',
        {},
        undefined,
      );
    });

    it('does not track a session opened by a deep link', async () => {
      createComponent({
        deepLinkedSessionId: String(getIdFromGraphQLId(mockArtifactNodes[0].id)),
      });
      await waitForPromises();

      expect(wrapper.emitted('row-click')).toHaveLength(1);
      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it.each([
      ['next', mockPageInfo.endCursor],
      ['prev', mockPageInfo.startCursor],
    ])('tracks a %s page change', async (direction, cursor) => {
      findPagination().vm.$emit(direction, cursor);
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'paginate_ai_audit_events_report',
        { label: direction },
        undefined,
      );
    });

    it('marks the user links as linked item clicks', () => {
      expect(wrapper.findAllByTestId('user-link').at(0).attributes()).toMatchObject({
        'data-event-tracking': LINKED_ITEM_EVENT,
        'data-event-label': 'user',
        'data-event-property': 'table',
      });
      expect(
        wrapper.findAllByTestId('user-avatar').at(0).element.closest('a').dataset.eventLabel,
      ).toBe('user');
    });

    it('marks the project links as linked item clicks', () => {
      expect(wrapper.findAllByTestId('project-link').at(0).attributes()).toMatchObject({
        'data-event-tracking': LINKED_ITEM_EVENT,
        'data-event-label': 'project',
        'data-event-property': 'table',
      });
    });

    it.each([
      ['user', 'user-link'],
      ['project', 'project-link'],
    ])('tracks a click on a %s link', (label, testId) => {
      const { triggerEvent } = bindInternalEventDocument(wrapper.element);

      triggerEvent(`[data-testid="${testId}"]`);

      expect(trackEventSpy).toHaveBeenCalledWith(LINKED_ITEM_EVENT, { label, property: 'table' });
    });
  });
});
