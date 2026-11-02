import { GlAlert, GlSkeletonLoader } from '@gitlab/ui';
import { GlSparklineChart } from '@gitlab/ui/src/charts';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import AutomationRunStats from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_run_stats.vue';
import getAutomationRunStats from 'ee/ai/duo_agents_platform/graphql/queries/get_automation_run_stats.query.graphql';
import { mockAutomationRunStatsResponse } from '../../mocks';

Vue.use(VueApollo);
jest.mock('~/sentry/sentry_browser_wrapper');

describe('AutomationRunStats', () => {
  useFakeDate('2026-10-13T12:00:00Z');

  let wrapper;

  const automationId = 'gid://gitlab/Ai::FlowTrigger/1';
  const queryHandler = jest.fn();

  const createComponent = () => {
    wrapper = shallowMountExtended(AutomationRunStats, {
      apolloProvider: createMockApollo([[getAutomationRunStats, queryHandler]]),
      propsData: { automationId },
      provide: { projectPath: 'my-group/my-project' },
    });
  };

  const findTotalRuns = () => wrapper.findByTestId('automation-total-runs');
  const findSuccessRate = () => wrapper.findByTestId('automation-success-rate');
  const findMedianDuration = () => wrapper.findByTestId('automation-median-duration');
  const findSparkline = () => wrapper.findComponent(GlSparklineChart);

  it('renders a skeleton loader while fetching', () => {
    queryHandler.mockResolvedValue(mockAutomationRunStatsResponse());
    createComponent();

    expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(true);
    expect(findTotalRuns().exists()).toBe(false);
  });

  it('renders the run statistics and the run volume of the automation', async () => {
    queryHandler.mockResolvedValue(mockAutomationRunStatsResponse());
    createComponent();
    await waitForPromises();

    expect(queryHandler).toHaveBeenCalledWith({
      projectPath: 'my-group/my-project',
      id: automationId,
    });
    expect(findTotalRuns().text()).toBe('1,234');
    expect(findSuccessRate().text()).toBe('75%');
    expect(findMedianDuration().text()).toBe('1m 30s');
    expect(findSparkline().props('data').at(-1)).toEqual(['Oct 13', 4]);
  });

  it('renders em dashes and the run volume when no run has ended', async () => {
    queryHandler.mockResolvedValue(
      mockAutomationRunStatsResponse({
        totalRuns: 4,
        finishedRuns: 0,
        failedRuns: 0,
        medianDurationSeconds: null,
      }),
    );
    createComponent();
    await waitForPromises();

    expect(findSuccessRate().text()).toBe('\u2014');
    expect(findMedianDuration().text()).toBe('\u2014');
    expect(findSparkline().exists()).toBe(true);
  });

  it('does not render the run volume when the automation never ran', async () => {
    queryHandler.mockResolvedValue(
      mockAutomationRunStatsResponse({ totalRuns: 0, dailyVolume: [] }),
    );
    createComponent();
    await waitForPromises();

    expect(findSparkline().exists()).toBe(false);
  });

  it('renders nothing when the automation is not found', async () => {
    queryHandler.mockResolvedValue({
      data: { project: { id: 'gid://gitlab/Project/1000000', aiFlowTriggers: { nodes: [] } } },
    });
    createComponent();
    await waitForPromises();

    expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(false);
    expect(findTotalRuns().exists()).toBe(false);
  });

  it('renders an alert and reports the error when the query fails', async () => {
    const error = new Error('GraphQL error');
    queryHandler.mockRejectedValue(error);
    createComponent();
    await waitForPromises();

    expect(wrapper.findComponent(GlAlert).text()).toBe('Failed to fetch run statistics.');
    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });
});
