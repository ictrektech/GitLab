import { safeLoad } from 'js-yaml';
import { shallowMount } from '@vue/test-utils';
import AnalyzeWithDuoButton from 'ee/explore/analytics_dashboards/components/analyze_with_duo_button.vue';
import OpenAgenticChatButton from 'ee/ai/shared/widgets/open_agentic_chat_button.vue';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { registerExternalContextProvider } from 'ee/ai/duo_agentic_chat/context/external_context_store';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('ee/ai/duo_agentic_chat/context/external_context_store', () => ({
  ...jest.requireActual('ee/ai/duo_agentic_chat/context/external_context_store'),
  registerExternalContextProvider: jest.fn(),
}));

describe('AnalyzeWithDuoButton', () => {
  let wrapper;
  let disposeProvider;

  const glqlPanel = (title, glql) => ({ title, visualization: { data: { query: { glql } } } });

  const defaultProps = {
    filters: {
      groups: ['group/dev'],
      projects: [],
      dateRangeOption: 'custom',
      startDate: new Date(Date.UTC(2026, 7, 11)),
      endDate: new Date(Date.UTC(2026, 8, 10)),
    },
    panels: [
      glqlPanel(
        'Total users',
        'mode: analytics\nquery: type = AiUsageEvent and timestamp >= "%{startDate}" and timestamp <= "%{endDate}"\n',
      ),
      { title: 'A section', section: { title: 'Users' } },
      { title: 'Legacy panel', visualization: 'stored_visualization_slug' },
    ],
    configPrompts: ['How is %{namespace} adopting Duo?', 'List the top projects.'],
  };

  const createComponent = (props = defaultProps) => {
    wrapper = shallowMount(AnalyzeWithDuoButton, {
      propsData: props,
    });
  };

  const findChatButton = () => wrapper.findComponent(OpenAgenticChatButton);
  const providerRegistration = () => {
    const [[category, getContent]] = registerExternalContextProvider.mock.calls;
    return { category, getContent };
  };

  beforeEach(() => {
    window.gon = { current_user_id: 7 };
    disposeProvider = jest.fn();
    registerExternalContextProvider.mockReturnValue(disposeProvider);
  });

  it('renders the agentic chat button labelled "Analyze with Duo"', () => {
    createComponent();

    expect(findChatButton().props('buttonText')).toBe('Analyze with Duo');
  });

  it('preselects the Data Analyst agent', () => {
    createComponent();

    expect(findChatButton().props('agent')).toEqual({ name: 'Data Analyst' });
  });

  it('uses the tanuki-ai icon', () => {
    createComponent();

    expect(findChatButton().props('icon')).toBe('tanuki-ai');
  });

  it('uses the primary confirm button style', () => {
    createComponent();

    expect(findChatButton().props('buttonOptions')).toEqual({ variant: 'confirm' });
  });

  it('binds the session to the current user', () => {
    createComponent();

    expect(findChatButton().props('resourceId')).toBe('gid://gitlab/User/7');
  });

  it('sets a welcome message about analyzing the dashboard data', () => {
    createComponent();

    expect(findChatButton().props('welcomeMessage')).toBe(
      'Ask me about the data on this dashboard.',
    );
  });

  describe('predefined prompts', () => {
    it('interpolates the namespace full path into the config-defined prompts', () => {
      createComponent();

      expect(findChatButton().props('predefinedPrompts')).toEqual([
        'How is group/dev adopting Duo?',
        'List the top projects.',
      ]);
    });

    it('passes the raw templates as tracking labels so no namespace is tracked', () => {
      createComponent();

      expect(findChatButton().props('predefinedPromptTrackingLabels')).toEqual([
        'How is %{namespace} adopting Duo?',
        'List the top projects.',
      ]);
    });

    it('does not escape HTML-sensitive characters in the plain-text prompts', () => {
      createComponent({
        ...defaultProps,
        filters: { ...defaultProps.filters, groups: ['r&d/core'] },
        configPrompts: ['Who are the top users in %{namespace}?'],
      });

      expect(findChatButton().props('predefinedPrompts')[0]).toBe(
        'Who are the top users in r&d/core?',
      );
    });

    it('lists every selected scope in the prompts', () => {
      createComponent({
        ...defaultProps,
        filters: { ...defaultProps.filters, groups: ['group/dev'], projects: ['group/ops/api'] },
      });

      expect(findChatButton().props('predefinedPrompts')[0]).toBe(
        'How is group/dev, group/ops/api adopting Duo?',
      );
    });
  });

  describe('dashboard context provider', () => {
    it('registers a dashboard_context provider and disposes it on destroy', () => {
      createComponent();

      expect(providerRegistration().category).toBe('dashboard_context');

      wrapper.destroy();

      expect(disposeProvider).toHaveBeenCalled();
    });

    it('resolves the current scope, date ranges and panel queries at read time', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.dashboard_scope).toEqual({ groups: ['group/dev'], projects: [] });
      expect(content.date_range).toEqual({
        option: 'custom',
        start_date: '2026-08-11',
        end_date: '2026-09-10',
        previous: {
          start_date: '2026-07-11',
          end_date: '2026-08-10',
        },
      });
      expect(content.panels).toEqual([
        {
          title: 'Total users',
          glql: 'mode: analytics\nquery: type = AiUsageEvent and timestamp >= "2026-08-11" and timestamp <= "2026-09-10" and group = "group/dev"\n',
        },
      ]);
    });

    it.each`
      form        | glql
      ${'inline'} | ${'query: type = DuoWorkflow and created >= "%{startDate}"\n'}
      ${'quoted'} | ${'query: "type = DuoWorkflow and created >= \\"%{startDate}\\""\n'}
      ${'folded'} | ${'query: >\n  type = DuoWorkflow\n  and created >= "%{startDate}"\n'}
    `('scopes a $form panel query', ({ glql }) => {
      createComponent({ ...defaultProps, panels: [glqlPanel('Sessions', glql)] });

      expect(safeLoad(providerRegistration().getContent().panels[0].glql).query).toBe(
        'type = DuoWorkflow and created >= "2026-08-11" and group = "group/dev"',
      );
    });

    it('keeps the rest of the panel block as it was', () => {
      createComponent({
        ...defaultProps,
        panels: [
          glqlPanel(
            'Sessions',
            'display: stat\nmode: analytics\nquery: type = DuoWorkflow\nmetrics: usersCount\n',
          ),
        ],
      });

      expect(providerRegistration().getContent().panels[0].glql).toBe(
        'display: stat\nmode: analytics\nquery: type = DuoWorkflow and group = "group/dev"\nmetrics: usersCount\n',
      );
    });

    it("writes the date range into a dateField panel's query, ahead of the scope", () => {
      createComponent({
        ...defaultProps,
        panels: [
          {
            title: 'Reviews requested',
            visualization: {
              data: {
                query: {
                  glql: 'mode: analytics\nquery: type = AiUsageEvent and event = "request_review"\n',
                  dateField: 'timestamp',
                },
              },
            },
          },
        ],
      });

      expect(providerRegistration().getContent().panels[0].glql).toBe(
        'mode: analytics\nquery: type = AiUsageEvent and event = "request_review" and timestamp >= "2026-08-11" and timestamp <= "2026-09-10" and group = "group/dev"\n',
      );
    });

    describe.each`
      form             | glql
      ${'frontmatter'} | ${'---\nmode: analytics\n---\ntype = DuoWorkflow'}
      ${'bare query'}  | ${'type = DuoWorkflow'}
    `('with a $form panel the scope cannot be added to', ({ glql }) => {
      beforeEach(() => {
        createComponent({
          ...defaultProps,
          panels: [
            glqlPanel('Total users', defaultProps.panels[0].visualization.data.query.glql),
            glqlPanel('Sessions', glql),
          ],
        });
      });

      it('still renders the button', () => {
        expect(findChatButton().exists()).toBe(true);
      });

      it('shares the other panels without it', () => {
        expect(
          providerRegistration()
            .getContent()
            .panels.map(({ title }) => title),
        ).toEqual(['Total users']);
      });

      it('reports the error to Sentry with the panel title', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
          extra: { panel: 'Sessions' },
        });
      });
    });

    it('fills the same placeholders the dashboard fills before a panel runs', () => {
      createComponent({
        ...defaultProps,
        panels: [
          glqlPanel(
            'New vs returning',
            'query: type = DuoWorkflow and created >= "%{previousStartDate}"\ndimensions: created(%{dynamicGranularity}), created(granularity="%{rangeDays}d")\n',
          ),
        ],
      });

      expect(safeLoad(providerRegistration().getContent().panels[0].glql)).toEqual({
        query: 'type = DuoWorkflow and created >= "2026-07-11" and group = "group/dev"',
        dimensions: 'created(daily), created(granularity="31d")',
      });
    });

    it("shares each panel's tooltip description", () => {
      createComponent({
        ...defaultProps,
        panels: [
          {
            ...glqlPanel('Active projects', 'query: type = DuoWorkflow\n'),
            tooltip: { description: 'Sessions not scoped to a project are not counted.' },
          },
        ],
      });

      expect(providerRegistration().getContent().panels[0].description).toBe(
        'Sessions not scoped to a project are not counted.',
      );
    });

    it('instructs the agent to say when the data is not available', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.additional_instructions).toContain(
        'If none of your tools can return the data the question needs, say that it is not available.',
      );
      expect(content.additional_instructions).toContain(
        'If a result is cut off by a row limit, say that the list is incomplete.',
      );
    });

    it('instructs the agent how to query the previous period and report numbers', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.additional_instructions).toContain(
        'To compare a total with the previous period, run the same panel query again with the dates in `date_range.previous`.',
      );
      expect(content.additional_instructions).toContain(
        'compare each date bucket with the one before it, so they need a date dimension',
      );
      expect(content.additional_instructions).toContain(
        'If a query returns an error, fix it and run it again, or say that the number is not available.',
      );
      expect(content.additional_instructions).toContain(
        'Only report numbers that a query in this conversation returned, or that you calculated from them',
      );
    });

    it('instructs the agent how to rank and check results', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.additional_instructions).toContain(
        'When ranking by a field, leave out rows with no value for it unless the user asks for them',
      );
      expect(content.additional_instructions).toContain(
        'If the question states something about the data, check it against the data first',
      );
      expect(content.additional_instructions).toContain(
        'Sort ranked results the way the question asks',
      );
      expect(content.additional_instructions).toContain(
        'To count items such as projects or users, use a count metric',
      );
    });

    it('instructs the agent to prefer the panel queries', () => {
      createComponent();

      const content = providerRegistration().getContent();

      expect(content.additional_instructions).toContain(
        'Use the panel queries above as your primary data source',
      );
      expect(content.additional_instructions).toContain(
        "reuse that panel's filters verbatim, change only the aggregation, and mention which panel query you used",
      );
    });

    it.each`
      scope                                | groups                       | projects                              | clause
      ${'a single group'}                  | ${['group/dev']}             | ${[]}                                 | ${'group = "group/dev"'}
      ${'a single project'}                | ${[]}                        | ${['group/ops/api']}                  | ${'project = "group/ops/api"'}
      ${'several groups'}                  | ${['group/dev', 'group/qa']} | ${[]}                                 | ${'group in ("group/dev", "group/qa")'}
      ${'several projects from one group'} | ${[]}                        | ${['group/ops/api', 'group/ops/web']} | ${'project in ("group/ops/api", "group/ops/web")'}
      ${'a group and a project'}           | ${['group/dev']}             | ${['group/ops/api']}                  | ${'group in ("group/dev") and project in ("group/ops/api")'}
    `('scopes the panel queries to $scope', ({ groups, projects, clause }) => {
      createComponent({
        ...defaultProps,
        filters: { ...defaultProps.filters, groups, projects },
      });

      expect(safeLoad(providerRegistration().getContent().panels[0].glql).query).toBe(
        `type = AiUsageEvent and timestamp >= "2026-08-11" and timestamp <= "2026-09-10" and ${clause}`,
      );
    });

    it('shares every selected group and project as the scope', () => {
      createComponent({
        ...defaultProps,
        filters: {
          ...defaultProps.filters,
          groups: ['group/dev', 'group/qa'],
          projects: ['group/ops/api'],
        },
      });

      expect(providerRegistration().getContent().dashboard_scope).toEqual({
        groups: ['group/dev', 'group/qa'],
        projects: ['group/ops/api'],
      });
    });

    it('contributes nothing while the button is hidden', () => {
      createComponent({ ...defaultProps, filters: { ...defaultProps.filters, groups: [] } });

      expect(providerRegistration().getContent()).toBe(null);
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it.each`
      scope                    | groups           | projects             | label
      ${'groups'}              | ${['group/dev']} | ${[]}                | ${'group'}
      ${'projects'}            | ${[]}            | ${['group/ops/api']} | ${'project'}
      ${'groups and projects'} | ${['group/dev']} | ${['group/ops/api']} | ${'mixed'}
    `('labels a click on $scope as $label', ({ groups, projects, label }) => {
      createComponent({ ...defaultProps, filters: { ...defaultProps.filters, groups, projects } });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findChatButton().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_analyze_with_duo_on_analytics_dashboard',
        { label, value: 1 },
        undefined,
      );
    });
  });

  describe.each`
    scenario                                 | overrides
    ${'no namespace is selected'}            | ${{ filters: { groups: [], projects: [] } }}
    ${'the dashboard has no GLQL panels'}    | ${{ panels: [{ title: 'Metric panel', visualization: 'ai_impact_over_time' }] }}
    ${'the dashboard configures no prompts'} | ${{ configPrompts: [] }}
  `('when $scenario', ({ overrides }) => {
    it('renders nothing', () => {
      createComponent({ ...defaultProps, ...overrides });

      expect(findChatButton().exists()).toBe(false);
    });
  });

  describe('when there is no signed-in user', () => {
    it('renders nothing instead of throwing', () => {
      window.gon = {};

      createComponent();

      expect(findChatButton().exists()).toBe(false);
    });
  });
});
