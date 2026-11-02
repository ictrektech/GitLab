import { waitFor, screen } from '@testing-library/vue';
import { waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { setFeatureFlags, setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { AGENT_PLATFORM_SIDE_PANEL_PAGE } from 'ee/ai/duo_agents_platform/constants';
import {
  buildChatConfiguration,
  findChatToggle,
  findSessionsToggle,
  mountAISidebar,
  setupDuoChatTest,
  teardownDuoChatTest,
} from './test_support/test_setup';
import { getUserAgentFlowInbox, installDuoAIPanelHandlers } from './test_support/api_handlers';
// Imported here rather than from `api_handlers.js` so a stale fixture takes down this
// spec alone, not every suite that loads the Duo panel handlers.
import userAgentFlowInboxVariants from './fixture_variants/get_user_agent_flow_inbox';

const findAgentSessionInbox = () => screen.queryByTestId('agent-session-inbox');
const findFilteredSearch = () => screen.queryByTestId('agent-sessions-search-container');

// `GlTab` keeps every pane mounted and hides the inactive ones, so an unscoped
// document-wide query would find rows on a tab the user cannot see. Going through
// the accessibility tree scopes each finder to the pane that is actually showing.
const inVisibleTabPanel = (testId) =>
  screen.queryAllByRole('tabpanel')[0]?.querySelector(`[data-testid="${testId}"]`) ?? null;

const findNeedsDecisionFlowList = () => inVisibleTabPanel('needs-decision-flow-list');
const findAllFlowList = () => inVisibleTabPanel('all-flow-list');
const findDecisionEmptyState = () => inVisibleTabPanel('needs-decision-empty-state');
// The All tab supplies no `empty-state` slot, so it keeps rendering `all-flow-list` and
// lets that component show the shared copy. Only the decision tab gets its own div.
const allTabRows = () => findAllFlowList()?.querySelectorAll('li') ?? [];

const { needsDecisionThreads, allThreads } = getUserAgentFlowInbox;
describe('AgentSessionInbox integration', () => {
  beforeEach(() => {
    // `createRouter` reads the flag at construction time, so set it before `mountAISidebar` runs.
    setFeatureFlags({ duoPanelSessionInbox: true });
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => {
    teardownDuoChatTest();
  });

  const openSessions = async ({ experimentFeaturesEnabled = true } = {}) => {
    mountAISidebar({
      chatConfiguration: buildChatConfiguration({ experimentFeaturesEnabled }),
      namespace: AGENT_PLATFORM_SIDE_PANEL_PAGE,
    });

    await waitForElement(findChatToggle);
    findChatToggle().click();
    const sessionsToggle = await waitForElement(findSessionsToggle);
    sessionsToggle.click();
  };

  const navigateToInbox = async () => {
    await openSessions();

    await waitFor(() => {
      expect(findAgentSessionInbox()).not.toBeNull();
    });
  };

  // Matched loosely so the tab-count badge landing on these titles later does not break them.
  const findAllTab = () => screen.getByRole('tab', { name: /^All/ });
  const switchToAllTab = () => findAllTab().click();
  const switchToDecisionTab = () => screen.getByRole('tab', { name: /^Needs a decision/ }).click();

  describe('Duo experiment and beta features setting', () => {
    const findFlatSessionList = () => screen.queryByTestId('agent-sessions');
    const findInboxTab = () => screen.queryByRole('tab', { name: /^Needs a decision/ });

    it('renders the inbox with its tabs when the setting and the flag are on', async () => {
      await openSessions({ experimentFeaturesEnabled: true });

      await waitFor(() => {
        expect(findAgentSessionInbox()).not.toBeNull();
      });

      expect(findInboxTab()).not.toBeNull();
      expect(findAllTab()).not.toBeNull();
      expect(findFlatSessionList()).toBeNull();
    });

    it.each`
      description                                | flag     | experimentFeaturesEnabled
      ${'the setting is off'}                    | ${true}  | ${false}
      ${'the flag is off, even with setting on'} | ${false} | ${true}
    `(
      'renders the flat session list when $description',
      async ({ flag, experimentFeaturesEnabled }) => {
        setFeatureFlags({ duoPanelSessionInbox: flag });

        await openSessions({ experimentFeaturesEnabled });

        await waitFor(() => {
          expect(findFlatSessionList()).not.toBeNull();
        });

        expect(findAgentSessionInbox()).toBeNull();
        expect(findInboxTab()).toBeNull();
      },
    );
  });

  it('opens on the All tab', async () => {
    await navigateToInbox();

    await waitFor(() => {
      expect(findAllFlowList()).not.toBeNull();
    });

    expect(findAllTab().getAttribute('aria-selected')).toBe('true');
    expect(findNeedsDecisionFlowList()).toBeNull();
  });

  it('lists the needsDecision alias rows after switching to the Needs a decision tab', async () => {
    await navigateToInbox();

    // The list only mounts once the query resolves with at least one row, so waiting
    // for it is also the signal that the loading gate cleared.
    await waitFor(() => {
      expect(findAllFlowList()).not.toBeNull();
    });

    switchToDecisionTab();

    await waitFor(() => {
      const list = findNeedsDecisionFlowList();
      expect(list).not.toBeNull();
      expect(list.querySelectorAll('li')).toHaveLength(needsDecisionThreads().length);
    });
  });

  it('lists the all alias rows on the tab it opens on', async () => {
    await navigateToInbox();

    await waitFor(() => {
      const list = findAllFlowList();
      expect(list).not.toBeNull();
      expect(list.querySelectorAll('li')).toHaveLength(allThreads().length);
    });
  });

  // The two aliases are 20 rows each but not the same 20, because the running sessions
  // sort ahead of every awaiting one. Discriminating on status rather than on the row
  // title, because `title` falls back to the workflow definition and so is identical on
  // every seeded row.
  it('gives each tab its own alias rather than one shared list', async () => {
    await navigateToInbox();

    await waitFor(() => {
      expect(findAllFlowList()).not.toBeNull();
    });
    const allRows = findAllFlowList().textContent;

    switchToDecisionTab();
    await waitFor(() => {
      expect(findNeedsDecisionFlowList()).not.toBeNull();
    });
    const decisionRows = findNeedsDecisionFlowList().textContent;
    // Switching tabs takes the All pane out of the accessibility tree, so this also
    // pins the finders to the visible pane rather than to every mounted one.
    expect(findAllFlowList()).toBeNull();

    // `running` is not an awaiting-input status, so it can only reach the screen from
    // the `all` alias. Both halves are asserted: present on one tab, absent on the other.
    const runningOnlyInAll =
      allThreads().some(({ humanStatus }) => humanStatus === 'running') &&
      !needsDecisionThreads().some(({ humanStatus }) => humanStatus === 'running');
    expect(runningOnlyInAll).toBe(true);

    expect(allRows).toContain('Running');
    expect(decisionRows).not.toContain('Running');
  });

  describe('empty states', () => {
    describe('when nothing needs a decision', () => {
      beforeEach(async () => {
        setQueryVariant(userAgentFlowInboxVariants).decisionEmpty();

        await navigateToInbox();

        switchToDecisionTab();

        await waitFor(() => {
          expect(findDecisionEmptyState()).not.toBeNull();
        });
      });

      it('shows the decision tab its own empty state while the All tab still has rows', async () => {
        // The decision tab does not delegate to the shared list empty state, whose copy
        // reads as a search result and is wrong for a fixed-meaning tab.
        expect(findDecisionEmptyState().textContent).toContain('Nothing needs you right now');
        expect(findNeedsDecisionFlowList()).toBeNull();

        // `all` is untouched by this variant, so the other tab must still list rows.
        switchToAllTab();
        await waitFor(() => {
          expect(findAllFlowList()).not.toBeNull();
        });
        expect(allTabRows().length).toBeGreaterThan(0);
      });

      it('offers a button that moves the user to the All tab', async () => {
        screen.getByRole('button', { name: /View all sessions/ }).click();

        await waitFor(() => {
          expect(screen.getByRole('tab', { name: /^All/ }).getAttribute('aria-selected')).toBe(
            'true',
          );
        });
      });
    });

    it('shows the All tab the shared empty copy when neither alias returns a row', async () => {
      setQueryVariant(userAgentFlowInboxVariants).bothEmpty();

      await navigateToInbox();

      await waitFor(() => {
        expect(findAllFlowList()).not.toBeNull();
      });

      expect(findAllFlowList().textContent).toContain('No agent sessions yet');
      expect(allTabRows()).toHaveLength(0);
    });
  });

  it('counts the needsDecision alias on the tab heading', async () => {
    await navigateToInbox();

    // The needsDecision alias returns a full page with a further page, so the badge reads
    // the overflow form: the connection has no count field, so it counts loaded edges, not a total.
    const needsDecisionBadge = await screen.findByTestId('needs-decision-tab-badge');

    expect(needsDecisionBadge.textContent.trim()).toBe(`${needsDecisionThreads().length}+`);
  });

  describe('CLI sessions', () => {
    const RUN_TITLE = 'Headless duo run waiting for input';
    const CLI_TITLE = 'CLI session started from the terminal';

    beforeEach(() => {
      setQueryVariant(userAgentFlowInboxVariants).withCliSession();
    });

    it('lists every CLI session on "All", and only the headless run on "Needs a decision"', async () => {
      await navigateToInbox();

      await waitFor(() => {
        expect(findAllFlowList()).not.toBeNull();
      });
      const allText = findAllFlowList().textContent;

      switchToDecisionTab();

      await waitFor(() => {
        expect(findNeedsDecisionFlowList()).not.toBeNull();
      });
      const decisionText = findNeedsDecisionFlowList().textContent;

      expect(allText).toContain(RUN_TITLE);
      expect(allText).toContain(CLI_TITLE);
      expect(decisionText).toContain(RUN_TITLE);
      expect(decisionText).not.toContain(CLI_TITLE);
    });

    it('badges `Needs a decision` with the overflow count while more pages remain', async () => {
      await navigateToInbox();

      const badge = await screen.findByTestId('needs-decision-tab-badge');

      expect(badge.textContent.trim()).toBe('20+');
    });
  });

  it('renders the AgentFlowFilteredSearch bar, proving the import resolves', async () => {
    await navigateToInbox();

    // The testid sits on <filtered-search-bar>, which AgentFlowFilteredSearch gates on
    // `hasInitialWorkflows`. So this also proves the inbox flipped that flag from the
    // `all` alias's edges, not just that the module graph resolved.
    await waitFor(() => {
      expect(findFilteredSearch()).not.toBeNull();
    });
  });
});
