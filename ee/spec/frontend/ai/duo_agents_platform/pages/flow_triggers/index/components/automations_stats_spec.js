import { GlCard, GlSkeletonLoader } from '@gitlab/ui';
import { GlSingleStat, GlSparklineChart } from '@gitlab/ui/src/charts';
import VueApollo from 'vue-apollo';
import Vue from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import { createAlert } from '~/alert';
import AutomationsStats from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automations_stats.vue';
import getAiFlowTriggerRunStats from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_trigger_run_stats.query.graphql';
import { mockAiFlowTriggerRunStatsResponse } from '../../mocks';

Vue.use(VueApollo);
jest.mock('~/alert');

describe('AutomationsStats', () => {
  useFakeDate('2026-10-13T12:00:00Z');

  let wrapper;

  const queryHandler = jest.fn();

  const findCards = () => wrapper.findAllComponents(GlCard);
  const findSkeletonLoaders = () => wrapper.findAllComponents(GlSkeletonLoader);
  const findSingleStats = () => wrapper.findAllComponents(GlSingleStat);
  const findSparkline = () => wrapper.findComponent(GlSparklineChart);

  const createComponent = () => {
    wrapper = shallowMountExtended(AutomationsStats, {
      apolloProvider: createMockApollo([[getAiFlowTriggerRunStats, queryHandler]]),
      provide: { projectPath: 'myProject' },
    });
  };

  beforeEach(() => {
    queryHandler.mockResolvedValue(mockAiFlowTriggerRunStatsResponse());
  });

  it('renders a skeleton loader for each card while fetching', () => {
    createComponent();

    expect(findSkeletonLoaders()).toHaveLength(3);
    expect(findSingleStats()).toHaveLength(0);
  });

  it('renders the total runs, the success rate and the run volume', async () => {
    createComponent();
    await waitForPromises();

    expect(queryHandler).toHaveBeenCalledWith({ projectPath: 'myProject' });
    expect(findSingleStats().at(0).props()).toMatchObject({
      title: 'Total runs',
      value: 1234,
      useDelimiters: true,
      description: 'Last 30 days',
    });
    expect(findSingleStats().at(1).props()).toMatchObject({
      title: 'Success rate',
      value: 75,
      unit: '%',
      description: 'Last 30 days',
    });
    expect(findSparkline().props('data').at(-1)).toEqual(['Oct 13', 4]);
    expect(findSparkline().props('tooltipLabel')).toBe('Runs');
  });

  it('renders an em dash without a unit when no run has finished or failed', async () => {
    queryHandler.mockResolvedValue(
      mockAiFlowTriggerRunStatsResponse({ finishedRuns: 0, failedRuns: 0 }),
    );
    createComponent();
    await waitForPromises();

    expect(findSingleStats().at(1).props()).toMatchObject({ value: '\u2014', unit: null });
  });

  it('creates an alert and renders nothing when the query fails', async () => {
    queryHandler.mockRejectedValue(new Error());
    createComponent();
    await waitForPromises();

    expect(createAlert).toHaveBeenCalledWith({
      message: 'Failed to fetch run statistics.',
      captureError: true,
      error: expect.any(Error),
    });
    expect(findCards()).toHaveLength(0);
  });
});
