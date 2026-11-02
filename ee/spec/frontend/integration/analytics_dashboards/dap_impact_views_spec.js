import {
  getText,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  DAP_IMPACT_SEARCH,
  DAP_IMPACT_VIEWS,
  GROUP_PATH,
  bootDashboard,
  expectPanels,
  findPanel,
  findPanelFooterLink,
  findSection,
  findViewTab,
  panelTitles,
  searchParam,
} from './test_setup';

const waitForPanels = (titles) => waitForAssertion(() => expectPanels(titles));

const selectedTab = () =>
  DAP_IMPACT_VIEWS.find(({ title }) => findViewTab(title)?.getAttribute('aria-selected') === 'true')
    ?.title;

const PANELS_WITH_VIEW_LINKS = DAP_IMPACT_VIEWS.flatMap(({ panels }) =>
  panels.filter((panel) => panel.footer?.dashboardViewLink),
);

describe('DAP Impact dashboard views', () => {
  describe('switching views', () => {
    it.each(PANELS_WITH_VIEW_LINKS.map((panel) => [panel.title, panel]))(
      'opens the view the %s footer links to',
      async (title, { footer }) => {
        const { text, view } = footer.dashboardViewLink;

        await bootDashboard(DAP_IMPACT_SEARCH);

        const link = await waitForElement(() => findPanelFooterLink(title));

        expect(getText(link)).toBe(text);

        link.click();

        await waitForPanels(panelTitles(view));
        await waitForAssertion(() => expect(selectedTab()).toBe(DAP_IMPACT_VIEWS[view].title));
        expect(searchParam('view')).toBe(String(view));
      },
    );

    it('shows only the chosen view, with its section headings', async () => {
      await bootDashboard(DAP_IMPACT_SEARCH);

      (await waitForElement(() => findViewTab(DAP_IMPACT_VIEWS[1].title))).click();

      await waitForPanels(panelTitles(1));

      expect(
        panelTitles(0).filter((title) => !panelTitles(1).includes(title) && findPanel(title)),
      ).toEqual([]);
      const sections = [
        { title: 'Users', description: 'Who is using DAP, and how many of them are new.' },
        {
          title: 'Engagement',
          description: 'How deeply and how widely those users engage in the selected date range.',
        },
        {
          title: 'Adoption tiers',
          description:
            'How platform engagement is distributed across all users in the selected date range.',
        },
      ];

      sections.forEach(({ title, description }) => {
        expect(getText(findSection(title))).toContain(title);
        expect(getText(findSection(title))).toContain(description);
      });
    });

    it('opens the view chosen from the tabs and keeps the scope', async () => {
      await bootDashboard(DAP_IMPACT_SEARCH);

      const lastView = DAP_IMPACT_VIEWS.length - 1;

      (await waitForElement(() => findViewTab(DAP_IMPACT_VIEWS[lastView].title))).click();

      await waitForPanels(panelTitles(lastView));
      await waitForAssertion(() => expect(selectedTab()).toBe(DAP_IMPACT_VIEWS[lastView].title));
      expect(searchParam('view')).toBe(String(lastView));
      expect(searchParam('scope')).toBe(GROUP_PATH);
    });

    it('opens the view named in the URL', async () => {
      await bootDashboard(`${DAP_IMPACT_SEARCH}&view=2`, 2);

      await waitForAssertion(() => expect(selectedTab()).toBe(DAP_IMPACT_VIEWS[2].title));
    });
  });
});
