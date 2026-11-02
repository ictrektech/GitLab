import { shallowMount } from '@vue/test-utils';
import StatsBar from 'ee/policy_store/components/list/stats_bar.vue';
import StatsBarItem from 'ee/policy_store/components/list/stats_bar_item.vue';

describe('StatsBar', () => {
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMount(StatsBar, { propsData });
  };

  const findItems = () => wrapper.findAllComponents(StatsBarItem);

  it('renders an item for the active policies count', () => {
    createComponent({ activePolicies: 7 });

    expect(findItems().at(0).props()).toMatchObject({ label: 'Active policies', value: 7 });
  });

  it('renders an item for the recent evaluations count', () => {
    createComponent({ recentEvaluations: 1233, recentEvaluationsLoading: true });

    expect(findItems().at(1).props()).toMatchObject({
      label: 'Evaluations (last 7 days)',
      value: 1233,
      loading: true,
      limit: 1000,
    });
  });

  // A project's policy store records no evaluations of its own, so the stat
  // would always read zero there.
  it('renders only the active policies item when evaluations are hidden', () => {
    createComponent({ activePolicies: 7, showRecentEvaluations: false });

    expect(findItems()).toHaveLength(1);
    expect(findItems().at(0).props('label')).toBe('Active policies');
  });

  it('defaults the evaluations count to unknown rather than zero', () => {
    createComponent();

    expect(findItems().at(0).props('value')).toBe(0);
    expect(findItems().at(1).props('value')).toBe(null);
    expect(findItems().at(1).props('loading')).toBe(false);
  });
});
