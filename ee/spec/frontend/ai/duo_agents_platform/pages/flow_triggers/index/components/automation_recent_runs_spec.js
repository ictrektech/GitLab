import { GlAlert, GlBadge, GlKeysetPagination, GlSkeletonLoader, GlTableLite } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import ViewSessionButton from 'ee/ai/shared/widgets/view_session_button.vue';
import AutomationRecentRuns from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_recent_runs.vue';
import getAutomationRecentRuns from 'ee/ai/duo_agents_platform/graphql/queries/get_automation_recent_runs.query.graphql';
import { DUO_AGENT_PLATFORM_POLLING_INTERVAL } from 'ee/ai/duo_agents_platform/constants';
import { mockAutomationRecentRunsResponse, mockAutomationSessionFactory } from '../../mocks';

Vue.use(VueApollo);
jest.mock('~/sentry/sentry_browser_wrapper');

describe('AutomationRecentRuns', () => {
  let wrapper;

  const automationId = 'gid://gitlab/Ai::FlowTrigger/1';
  const finishedRun = mockAutomationSessionFactory();
  const runningRun = mockAutomationSessionFactory({ status: 'RUNNING' });
  const queryHandler = jest.fn();

  const createComponent = () => {
    wrapper = mountExtended(AutomationRecentRuns, {
      apolloProvider: createMockApollo([[getAutomationRecentRuns, queryHandler]]),
      propsData: { automationId },
      provide: { projectPath: 'my-group/my-project' },
      stubs: { ViewSessionButton: true },
    });
  };

  const findRows = () => wrapper.findComponent(GlTableLite).findAll('tbody tr');
  const findCells = (row) => findRows().at(row).findAll('td');

  it('renders a skeleton loader while fetching', () => {
    queryHandler.mockResolvedValue(mockAutomationRecentRunsResponse());
    createComponent();

    expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(true);
    expect(wrapper.findComponent(GlTableLite).exists()).toBe(false);
  });

  describe('with runs', () => {
    beforeEach(async () => {
      queryHandler.mockResolvedValue(mockAutomationRecentRunsResponse([finishedRun]));
      createComponent();
      await waitForPromises();
    });

    it('requests the first page of runs of the automation', () => {
      expect(queryHandler).toHaveBeenCalledWith({
        projectPath: 'my-group/my-project',
        id: automationId,
        first: 20,
        after: null,
        last: null,
        before: null,
      });
    });

    it('renders the start time and the session button', () => {
      expect(findCells(0).at(1).findComponent(TimeAgoTooltip).props('time')).toBe(
        finishedRun.createdAt,
      );
      expect(findCells(0).at(3).findComponent(ViewSessionButton).props('sessionId')).toBe(101);
    });
  });

  it.each`
    status                           | text                | variant      | icon                  | duration
    ${'CREATED'}                     | ${'Pending'}        | ${'neutral'} | ${'status-waiting'}   | ${'\u2014'}
    ${'RUNNING'}                     | ${'Running'}        | ${'info'}    | ${'status-running'}   | ${'\u2014'}
    ${'TOOL_CALL_APPROVAL_REQUIRED'} | ${'Awaiting input'} | ${'warning'} | ${'status-alert'}     | ${'\u2014'}
    ${'FINISHED'}                    | ${'Succeeded'}      | ${'success'} | ${'status-success'}   | ${'1m 30s'}
    ${'IDLE'}                        | ${'Succeeded'}      | ${'success'} | ${'status-success'}   | ${'\u2014'}
    ${'FAILED'}                      | ${'Failed'}         | ${'danger'}  | ${'status-failed'}    | ${'1m 30s'}
    ${'STOPPED'}                     | ${'Canceled'}       | ${'neutral'} | ${'status-cancelled'} | ${'1m 30s'}
  `(
    'renders $text and a duration of $duration for a $status session',
    async ({ status, text, variant, icon, duration }) => {
      queryHandler.mockResolvedValue(
        mockAutomationRecentRunsResponse([mockAutomationSessionFactory({ status })]),
      );
      createComponent();
      await waitForPromises();

      const badge = findCells(0).at(0).findComponent(GlBadge);

      expect(badge.props()).toMatchObject({ variant, icon });
      expect(badge.text()).toBe(text);
      expect(findCells(0).at(2).text()).toBe(duration);
    },
  );

  it('renders the empty state when the automation has no runs', async () => {
    queryHandler.mockResolvedValue(mockAutomationRecentRunsResponse([]));
    createComponent();
    await waitForPromises();

    expect(wrapper.text()).toContain('No runs yet.');
    expect(wrapper.findComponent(GlTableLite).exists()).toBe(false);
  });

  it('renders an alert and reports the error when the query fails', async () => {
    const error = new Error('GraphQL error');
    queryHandler.mockRejectedValue(error);
    createComponent();
    await waitForPromises();

    expect(wrapper.findComponent(GlAlert).text()).toBe('Failed to load recent runs.');
    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });

  describe('pagination', () => {
    const findPagination = () => wrapper.findComponent(GlKeysetPagination);

    beforeEach(async () => {
      queryHandler.mockResolvedValue(
        mockAutomationRecentRunsResponse([finishedRun], {
          hasNextPage: true,
          hasPreviousPage: true,
        }),
      );
      createComponent();
      await waitForPromises();
    });

    it('requests the next page after the end cursor', async () => {
      findPagination().vm.$emit('next');
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ first: 20, after: 'end', last: null, before: null }),
      );
    });

    it('requests the previous page before the start cursor', async () => {
      findPagination().vm.$emit('prev');
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ first: null, after: null, last: 20, before: 'start' }),
      );
    });

    it.each(['next', 'prev'])('scrolls to the heading on %s', (event) => {
      const scrollIntoView = jest.spyOn(wrapper.find('h3').element, 'scrollIntoView');

      findPagination().vm.$emit(event);

      expect(scrollIntoView).toHaveBeenCalledWith({ block: 'start' });
    });
  });

  describe('polling', () => {
    const advancePollInterval = async () => {
      jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
      await waitForPromises();
    };

    it('polls the current page while a session is pending', async () => {
      queryHandler.mockResolvedValue(
        mockAutomationRecentRunsResponse([mockAutomationSessionFactory({ status: 'CREATED' })], {
          hasNextPage: true,
        }),
      );
      createComponent();
      await waitForPromises();
      wrapper.findComponent(GlKeysetPagination).vm.$emit('next');
      await waitForPromises();
      jest.advanceTimersByTime(DUO_AGENT_PLATFORM_POLLING_INTERVAL - 1);
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledTimes(2);

      await advancePollInterval();

      expect(queryHandler).toHaveBeenCalledTimes(3);
      expect(queryHandler).toHaveBeenLastCalledWith(expect.objectContaining({ after: 'end' }));
    });

    it('keeps the runs and shows the alert until a poll succeeds', async () => {
      queryHandler
        .mockResolvedValueOnce(mockAutomationRecentRunsResponse([runningRun]))
        .mockRejectedValueOnce(new Error('GraphQL error'))
        .mockResolvedValue(mockAutomationRecentRunsResponse([runningRun]));
      createComponent();
      await waitForPromises();
      await advancePollInterval();

      expect(wrapper.findComponent(GlAlert).exists()).toBe(true);
      expect(findRows()).toHaveLength(1);

      await advancePollInterval();

      expect(wrapper.findComponent(GlAlert).exists()).toBe(false);
    });

    it('stops polling when no run is pending or running', async () => {
      queryHandler
        .mockResolvedValueOnce(mockAutomationRecentRunsResponse([runningRun]))
        .mockResolvedValue(
          mockAutomationRecentRunsResponse([{ ...runningRun, status: 'INPUT_REQUIRED' }]),
        );
      createComponent();
      await waitForPromises();
      await advancePollInterval();
      await advancePollInterval();

      expect(queryHandler).toHaveBeenCalledTimes(2);
    });
  });
});
