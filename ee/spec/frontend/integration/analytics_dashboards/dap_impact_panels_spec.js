import { HttpResponse } from 'msw';
import { server } from 'ee_jest/integration/server';
import { respondToGlqlPanels } from 'ee_jest/integration/analytics_dashboards/handlers';
import {
  getText,
  waitForAssertion,
  waitForElement,
  waitForSetup,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  DAP_IMPACT_SEARCH,
  DAP_IMPACT_SLUG,
  DAP_IMPACT_VIEWS,
  findFailedPanelStates,
  findPanel,
  findViewTab,
  isPanelLoaded,
  mountAnalyticsDashboard,
  panelTitles,
} from './test_setup';

// Tables and bar lists show trends in their own columns, so only stat tiles have a badge.
const trendStatTitles = (viewIndex) =>
  DAP_IMPACT_VIEWS[viewIndex].panels
    .filter(
      (panel) =>
        panel.visualization?.options?.showTrends &&
        /^display: stat$/m.test(panel.visualization.data.query.glql),
    )
    .map(({ title }) => title);

const unloadedPanels = (titles) => titles.filter((title) => !isPanelLoaded(title));

const expectNoFailedPanels = (titles) =>
  titles.forEach((title) =>
    expect([title, findFailedPanelStates(findPanel(title))]).toEqual([title, []]),
  );

describe('DAP Impact dashboard panels', () => {
  let captureException;

  beforeEach(async () => {
    captureException = jest.spyOn(Sentry, 'captureException');

    mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: DAP_IMPACT_SEARCH });

    // The first mount compiles and fetches every Overview query, which a starved CI runner
    // can stretch past a test's wait. That is boot, so it runs on the setup budget.
    await waitForSetup(() => {
      expect(unloadedPanels(panelTitles(0))).toEqual([]);
    });
  });

  // Seeded by ee/spec/frontend/fixtures/analytics_dashboards_integration.rb.
  it.each`
    title                   | value  | trend
    ${'Active projects'}    | ${'2'} | ${'100%'}
    ${'Active users'}       | ${'2'} | ${'100%'}
    ${'Completed sessions'} | ${'2'} | ${'100%'}
    ${'Credits consumed'}   | ${'8'} | ${'700%'}
  `(
    'shows $value for $title, $trend up on the previous period',
    async ({ title, value, trend }) => {
      await waitForAssertion(() => {
        expect(getText(findPanel(title))).toContain(`${value} ${trend} vs prior`);
      });
    },
  );

  describe.each(DAP_IMPACT_VIEWS.map(({ title }, index) => ({ title, index })))(
    'the $title view',
    ({ title: viewTitle, index }) => {
      beforeEach(async () => {
        (await waitForElement(() => findViewTab(viewTitle))).click();

        // Opening a view compiles and fetches every panel in it, which is boot for that view.
        await waitForSetup(() => {
          expect(unloadedPanels(panelTitles(index))).toEqual([]);
        });
      });

      it('compares every trend tile against the previous period', () => {
        trendStatTitles(index).forEach((title) => {
          const badge = within(findPanel(title)).queryByTestId('meta-badge');

          expect([title, badge && getText(badge)]).toEqual([
            title,
            expect.stringMatching(/^(.+ vs prior|New)$/),
          ]);
        });
      });

      it('renders without a failed panel', () => {
        expectNoFailedPanels(panelTitles(index));

        expect(captureException).not.toHaveBeenCalled();
      });
    },
  );

  describe('on the Adoption view', () => {
    const ADOPTION_INDEX = DAP_IMPACT_VIEWS.findIndex(({ title }) => title === 'Adoption');

    beforeEach(async () => {
      (await waitForElement(() => findViewTab('Adoption'))).click();

      await waitForSetup(() => {
        expect(unloadedPanels(panelTitles(ADOPTION_INDEX))).toEqual([]);
      });
    });

    // The label comes from the dashboard YAML; the fixture has no user who did not return.
    it('labels the abandonment row as users who did not return', () => {
      expect(getText(within(findPanel('Abandonment')).getByTestId('bar-list-chart'))).toContain(
        'Did not return',
      );
    });

    it('places projects directly under the group in the no-subgroup row', () => {
      const rows = within(findPanel('Group and project comparison'))
        .getAllByRole('row')
        .slice(1)
        .map(getText);

      expect(rows).toEqual([
        expect.stringMatching(/^Not in a subgroup .*DAP Impact group \/ Dap-alpha/),
        expect.stringMatching(/^Not in a subgroup .*DAP Impact group \/ Dap-beta/),
      ]);
    });
  });
});

describe('DAP Impact dashboard panels when queries fail', () => {
  const OVERVIEW_TITLES = panelTitles(0);

  const expectOnlyFailed = async (failedTitles, state) => {
    const otherTitles = OVERVIEW_TITLES.filter((title) => !failedTitles.includes(title));

    // Waiting for the first mount to settle is boot, so it runs on the setup budget.
    await waitForSetup(() => {
      failedTitles.forEach((title) =>
        expect([title, findFailedPanelStates(findPanel(title))]).toEqual([title, [state]]),
      );
      expect(unloadedPanels(otherTitles)).toEqual([]);
    });
    expectNoFailedPanels(otherTitles);
  };

  it('shows an error on the failing panel and loads the rest', async () => {
    server.use(
      respondToGlqlPanels(['Completed sessions'], () => new HttpResponse(null, { status: 500 })),
    );
    mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: DAP_IMPACT_SEARCH });

    await expectOnlyFailed(['Completed sessions'], 'error');
  });

  it('shows no access on the credits panels when the user cannot read credits', async () => {
    const CREDITS_TITLES = ['Credits consumed', 'Where credits went'];

    server.use(
      respondToGlqlPanels(CREDITS_TITLES, () =>
        HttpResponse.json({
          data: null,
          errors: [
            {
              message: 'You are not authorized to read credits',
              extensions: { code: 'AGGREGATION_NOT_AUTHORIZED' },
            },
          ],
        }),
      ),
    );
    mountAnalyticsDashboard(DAP_IMPACT_SLUG, { search: DAP_IMPACT_SEARCH });

    await expectOnlyFailed(CREDITS_TITLES, 'no-access');
  });
});
