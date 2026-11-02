import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { useFakeDate } from 'helpers/fake_date';
import ExtendedDashboardPanel from '~/vue_shared/components/customizable_dashboard/extended_dashboard_panel.vue';
import MttrOverTimePanel from 'ee/security_dashboard/components/shared/mttr_over_time_panel.vue';
import MttrOverTimeChart from 'ee/security_dashboard/components/shared/charts/mttr_over_time_chart.vue';
import PanelSeverityFilter from 'ee/security_dashboard/components/shared/panel_severity_filter.vue';
import PanelGroupBy from 'ee/security_dashboard/components/shared/panel_group_by.vue';
import projectMttrOverTime from 'ee/security_dashboard/graphql/queries/project_mttr_over_time.query.graphql';
import groupMttrOverTime from 'ee/security_dashboard/graphql/queries/group_mttr_over_time.query.graphql';
import organizationMttrOverTime from 'ee/security_dashboard/graphql/queries/organization_mttr_over_time.query.graphql';
import * as panelStateUrlSync from 'ee/security_dashboard/utils/panel_state_url_sync';

Vue.use(VueApollo);

describe('MttrOverTimePanel', () => {
  // A Wednesday, so the Monday–Sunday snapping of the 12-week window is unambiguous.
  const today = '2022-07-06';
  // Monday of the first of 12 weeks, and Sunday of the current week.
  const expectedStartDate = '2022-04-18';
  const expectedEndDate = '2022-07-10';

  useFakeDate(today);

  let wrapper;

  const mockBuckets = [
    {
      __typename: 'MttrOverTimeBucket',
      startDate: expectedStartDate,
      endDate: '2022-04-24',
      sumDays: 100,
      count: 5,
      mttr: 20,
      bySeverity: [],
      byReportType: [],
    },
  ];

  const namespaceConfigs = {
    project: {
      namespace: 'project',
      typename: 'Project',
      fullPath: 'project-1',
      query: projectMttrOverTime,
      filters: {
        reportType: ['SAST'],
        trackedRefIds: ['gid://gitlab/Security::ProjectTrackedContext/1'],
      },
      expectedFilters: {
        reportType: ['SAST'],
        trackedRefIds: ['gid://gitlab/Security::ProjectTrackedContext/1'],
      },
    },
    group: {
      namespace: 'group',
      typename: 'Group',
      fullPath: 'group/subgroup',
      query: groupMttrOverTime,
      filters: {
        projectId: ['gid://gitlab/Project/123'],
        reportType: ['SAST'],
        securityAttributesFilters: [{ operator: 'IS_ONE_OF', attributes: ['gid://gitlab/A/1'] }],
      },
      expectedFilters: {
        projectId: ['gid://gitlab/Project/123'],
        reportType: ['SAST'],
        securityAttributesFilters: [{ operator: 'IS_ONE_OF', attributes: ['gid://gitlab/A/1'] }],
      },
    },
    organization: {
      namespace: 'organization',
      typename: 'Organization',
      fullPath: null,
      query: organizationMttrOverTime,
      filters: {
        projectId: ['gid://gitlab/Project/123'],
        reportType: ['SAST'],
      },
      expectedFilters: {
        projectId: ['gid://gitlab/Project/123'],
        reportType: ['SAST'],
      },
    },
  };

  const serverResponse = (config, buckets) => ({
    data: {
      namespace: {
        __typename: config.typename,
        id: `gid://gitlab/${config.typename}/1`,
        securityMetrics: { __typename: 'SecurityMetrics', mttrOverTime: buckets },
      },
    },
  });

  const createComponent = ({
    namespace = 'project',
    serverHandler,
    buckets = mockBuckets,
  } = {}) => {
    const config = namespaceConfigs[namespace];
    const handler = serverHandler || jest.fn().mockResolvedValue(serverResponse(config, buckets));

    const apolloProvider = createMockApollo([[config.query, handler]]);

    wrapper = shallowMountExtended(MttrOverTimePanel, {
      apolloProvider,
      propsData: {
        namespace: config.namespace,
        filters: config.filters,
      },
      provide: {
        fullPath: config.fullPath,
      },
    });

    return { handler, config };
  };

  const findExtendedDashboardPanel = () => wrapper.findComponent(ExtendedDashboardPanel);
  const findSeverityFilter = () => wrapper.findComponent(PanelSeverityFilter);
  const findGroupBy = () => wrapper.findComponent(PanelGroupBy);
  const findChart = () => wrapper.findComponent(MttrOverTimeChart);
  const findEmptyState = () => wrapper.findByTestId('mttr-over-time-empty-state');

  afterEach(() => {
    setWindowLocation('');
  });

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the panel with the correct title and tooltip', () => {
      expect(findExtendedDashboardPanel().props('title')).toBe('MTTR over time');
      expect(findExtendedDashboardPanel().props('tooltip')).toEqual({
        description:
          'Mean time to remediation (MTTR) for vulnerabilities, shown as a weekly trend from Monday to Sunday. A vulnerability is remediated when it is resolved or no longer detected. The trend excludes dismissed vulnerabilities and vulnerabilities detected more than 90 days before the start of each week. Data for the most recent week might be incomplete.',
      });
    });

    it('renders the severity filter and the group by control with the "All" option', () => {
      expect(findSeverityFilter().exists()).toBe(true);
      expect(findGroupBy().exists()).toBe(true);
      expect(findGroupBy().props('showAll')).toBe(true);
      expect(findGroupBy().props('value')).toBe('all');
    });
  });

  describe('data fetching', () => {
    it('shows the loading state until the query resolves', async () => {
      createComponent();

      expect(findExtendedDashboardPanel().props('loading')).toBe(true);

      await waitForPromises();

      expect(findExtendedDashboardPanel().props('loading')).toBe(false);
    });

    it('hides the empty state once buckets are returned', async () => {
      createComponent();
      await waitForPromises();

      expect(findEmptyState().exists()).toBe(false);
    });

    it('shows the empty state when no buckets are returned', async () => {
      createComponent({ buckets: [] });
      await waitForPromises();

      expect(findEmptyState().text()).toBe('No results found');
    });

    it('shows the error state when the query fails', async () => {
      createComponent({ serverHandler: jest.fn().mockRejectedValue(new Error('failed')) });
      await waitForPromises();

      expect(findExtendedDashboardPanel().props('showAlertState')).toBe(true);
      expect(findEmptyState().text()).toBe('Something went wrong. Please try again.');
    });

    describe.each(Object.keys(namespaceConfigs))('when namespace is "%s"', (namespace) => {
      it('queries mttrOverTime with the snapped Monday–Sunday week range', async () => {
        const { handler } = createComponent({ namespace });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(
          expect.objectContaining({
            startDate: expectedStartDate,
            endDate: expectedEndDate,
            severity: [],
          }),
        );
      });

      it('passes the page-level filters to the securityMetrics query', async () => {
        const { handler, config } = createComponent({ namespace });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining(config.expectedFilters));
      });

      it('requests neither breakdown while grouping by "all"', async () => {
        const { handler } = createComponent({ namespace });
        await waitForPromises();

        expect(handler).toHaveBeenCalledWith(
          expect.objectContaining({ includeBySeverity: false, includeByReportType: false }),
        );
      });
    });
  });

  describe('chart', () => {
    it('does not render the chart until buckets are returned', () => {
      createComponent();

      expect(findChart().exists()).toBe(false);
    });

    it('renders the chart with the series derived from the buckets once data loads', async () => {
      createComponent();
      await waitForPromises();

      expect(findChart().exists()).toBe(true);
      expect(findChart().props('mttrSeries')).toEqual([
        { id: 'all', name: 'MTTR', data: [[expectedStartDate, 20]] },
      ]);
      expect(findChart().props('countSeries')).toEqual({
        id: 'count',
        name: 'Remediations (count)',
        data: [[expectedStartDate, 5]],
      });
    });

    it('rebuilds the series when the group by changes', async () => {
      createComponent();
      await waitForPromises();

      await findGroupBy().vm.$emit('input', 'severity');

      // The default buckets carry no per-severity data, so grouping by severity yields no lines.
      expect(findChart().props('mttrSeries')).toEqual([]);
    });
  });

  describe('filters', () => {
    it('re-queries with the new severity when the severity filter changes', async () => {
      const { handler } = createComponent();
      await waitForPromises();

      await findSeverityFilter().vm.$emit('input', ['CRITICAL', 'HIGH']);
      await waitForPromises();

      expect(handler).toHaveBeenLastCalledWith(
        expect.objectContaining({ severity: ['CRITICAL', 'HIGH'] }),
      );
    });

    it.each`
      groupBy         | includeBySeverity | includeByReportType
      ${'all'}        | ${false}          | ${false}
      ${'severity'}   | ${true}           | ${false}
      ${'reportType'} | ${false}          | ${true}
    `(
      'requests only the $groupBy breakdown when the group by is $groupBy',
      async ({ groupBy, includeBySeverity, includeByReportType }) => {
        const { handler } = createComponent();
        await waitForPromises();

        await findGroupBy().vm.$emit('input', groupBy);
        await waitForPromises();

        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ includeBySeverity, includeByReportType }),
        );
      },
    );
  });

  describe('URL state', () => {
    it('initializes severity and group by from the URL', () => {
      setWindowLocation('?mttrOverTime.severity=HIGH%2CLOW&mttrOverTime.groupBy=severity');
      createComponent();

      expect(findSeverityFilter().props('value')).toEqual(['HIGH', 'LOW']);
      expect(findGroupBy().props('value')).toBe('severity');
    });

    it('writes severity to the URL when it changes', async () => {
      jest.spyOn(panelStateUrlSync, 'writeToUrl');
      createComponent();

      await findSeverityFilter().vm.$emit('input', ['CRITICAL', 'MEDIUM']);

      expect(panelStateUrlSync.writeToUrl).toHaveBeenCalledWith({
        panelId: 'mttrOverTime',
        paramName: 'severity',
        value: ['CRITICAL', 'MEDIUM'],
        defaultValue: [],
      });
    });

    it('writes the group by to the URL when it changes', async () => {
      jest.spyOn(panelStateUrlSync, 'writeToUrl');
      createComponent();

      await findGroupBy().vm.$emit('input', 'reportType');

      expect(panelStateUrlSync.writeToUrl).toHaveBeenCalledWith({
        panelId: 'mttrOverTime',
        paramName: 'groupBy',
        value: 'reportType',
        defaultValue: 'all',
      });
    });
  });
});
