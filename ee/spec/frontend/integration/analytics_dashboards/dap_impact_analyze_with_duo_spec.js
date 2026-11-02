import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant, setUserSession } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  waitForAssertion,
  waitForElement,
  waitForSetup,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  createAiDuoWorkflowVariants,
  getFoundationalChatAgents,
  installDuoAIPanelHandlers,
} from 'ee_jest/integration/ai_duo_panel/test_support/api_handlers';
import {
  findButton,
  findChatSubheader,
  findChatMessages,
  findEmptyState,
  findResponseLoader,
  mountAISidebar,
  setupDuoChatTest,
  teardownDuoChatTest,
} from 'ee_jest/integration/ai_duo_panel/test_support/test_setup';
import {
  getSockets,
  lastAdditionalContext,
  lastWebsocketParams,
  waitForSocket,
} from 'ee_jest/integration/ai_duo_panel/test_support/websocket_mock';
import {
  DAP_IMPACT_SEARCH,
  DAP_IMPACT_SLUG,
  DAP_IMPACT_VIEWS,
  GROUP_PATH,
  findPanel,
  findViewTab,
  mountAnalyticsDashboard,
  panelTitles,
} from './test_setup';

const { referenceWithVersion: DATA_ANALYST_REFERENCE } = getFoundationalChatAgents
  .agents()
  .find(({ name }) => name === 'Data Analyst');

const OVERVIEW_PROMPT = DAP_IMPACT_VIEWS[0].duoPrompts[0];

const GROUP_SCOPE_CLAUSE = `and group = "${GROUP_PATH}"`;

const findAnalyzeWithDuoButton = () => findButton('Analyze with Duo');

const findSuggestedPrompts = () =>
  Array.from(findEmptyState()?.querySelectorAll('button') ?? []).map(getText);

const dashboardContext = () => {
  const item = lastAdditionalContext().find(({ category }) => category === 'dashboard_context');

  return item ? JSON.parse(item.content) : null;
};

const selectView = async (title) => {
  findViewTab(title).click();

  await waitForAssertion(() =>
    expect(findViewTab(title).getAttribute('aria-selected')).toBe('true'),
  );
};

const openChatWithDuo = async () => {
  (await waitForElement(findAnalyzeWithDuoButton)).click();

  await waitForAssertion(() => expect(getText(findChatSubheader())).toContain('Data Analyst'));
};

const sendSuggestedPrompt = async (prompt) => {
  const socketsBefore = getSockets().length;

  (await waitForElement(() => findButton(prompt, findEmptyState() ?? undefined))).click();

  await waitForAssertion(() => expect(getSockets()).toHaveLength(socketsBefore + 1));
  await waitForSocket();
};

describe('DAP Impact dashboard | Analyze with Duo', () => {
  beforeEach(async () => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
    setUserSession(true);

    mountAISidebar();
    mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: DAP_IMPACT_SEARCH });

    await waitForSetup(() => expect(findPanel(panelTitles(0)[0])).not.toBe(null));
  });

  afterEach(() => teardownDuoChatTest());

  describe.each(DAP_IMPACT_VIEWS)('from the $title view', ({ title, duoPrompts }) => {
    beforeEach(async () => {
      if (title !== 'Overview') await selectView(title);

      await openChatWithDuo();
    });

    it('opens the Data Analyst agent with the view suggested prompts', async () => {
      expect(duoPrompts).not.toHaveLength(0);

      await waitForAssertion(() => expect(findSuggestedPrompts()).toEqual(duoPrompts));
    });

    it('sends a suggested prompt to the Data Analyst agent with the view panels', async () => {
      await sendSuggestedPrompt(duoPrompts[0]);

      expect(lastRequestVariables('createAiDuoWorkflow')).toMatchObject({
        goal: duoPrompts[0],
        workflowDefinition: DATA_ANALYST_REFERENCE,
      });
      expect(lastWebsocketParams().get('workflow_definition')).toBe(DATA_ANALYST_REFERENCE);
      expect(dashboardContext().panels.map((panel) => panel.title)).toEqual(
        panelTitles(DAP_IMPACT_VIEWS.findIndex((view) => view.title === title)),
      );
    });
  });

  describe('the dashboard context', () => {
    beforeEach(async () => {
      await openChatWithDuo();
      await sendSuggestedPrompt(OVERVIEW_PROMPT);
    });

    it('carries the selected scope and date range', () => {
      expect(dashboardContext()).toMatchObject({
        dashboard_scope: { groups: [GROUP_PATH], projects: [] },
        date_range: {
          option: 'custom',
          start_date: '2020-06-01',
          end_date: '2020-06-30',
          previous: { start_date: '2020-05-02', end_date: '2020-05-31' },
        },
        additional_instructions: expect.stringContaining('analyse the current dashboard'),
      });
    });

    it('scopes every panel query to the selected group and dates', () => {
      const { panels } = dashboardContext();

      expect(panels[0]).toEqual({
        title: 'Active projects',
        description:
          'Distinct projects with at least one GitLab Duo Agent Platform (DAP) session in the selected date range. Sessions not scoped to a project are not counted.',
        glql: [
          'display: stat',
          'mode: analytics',
          `query: type = DuoWorkflow and created >= "2020-06-01" and created <= "2020-06-30" ${GROUP_SCOPE_CLAUSE}`,
          'metrics: projectsCount',
          'displayConfig:',
          '  description: Projects with at least one DAP session',
          '',
        ].join('\n'),
      });
      panels.forEach(({ glql }) => {
        expect(glql).toContain('"2020-06-01"');
        expect(glql).toContain(GROUP_SCOPE_CLAUSE);
        expect(glql).not.toContain('%{');
      });
    });
  });

  it('reads the panels of the view that is open when the prompt is sent', async () => {
    await openChatWithDuo();
    await selectView('Spend');

    await waitForAssertion(() =>
      expect(findSuggestedPrompts()).toEqual(DAP_IMPACT_VIEWS[0].duoPrompts),
    );

    await sendSuggestedPrompt(OVERVIEW_PROMPT);

    expect(dashboardContext().panels.map((panel) => panel.title)).toEqual(panelTitles(3));
  });

  it('shows an error instead of a loader when the workflow cannot be created', async () => {
    setQueryVariant(createAiDuoWorkflowVariants).agentDisabled();

    await openChatWithDuo();
    (
      await waitForElement(() => findButton(OVERVIEW_PROMPT, findEmptyState() ?? undefined))
    ).click();

    await waitForAssertion(() =>
      expect(getText(findChatMessages())).toContain('foundation agent disabled for namespace'),
    );
    expect(findResponseLoader()).toBe(null);
    expect(getSockets()).toHaveLength(0);
  });
});
