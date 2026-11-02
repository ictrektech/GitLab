import { GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StatsBarItem from 'ee/policy_store/components/list/stats_bar_item.vue';

describe('StatsBarItem', () => {
  let wrapper;

  const createComponent = (propsData) => {
    wrapper = shallowMountExtended(StatsBarItem, { propsData });
  };

  const findValue = () => wrapper.findByTestId('stats-bar-item-value');
  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);

  it('renders the label', () => {
    createComponent({ label: 'Active policies', value: 7 });

    expect(wrapper.text()).toContain('Active policies');
  });

  it('renders the value formatted with locale separators', () => {
    createComponent({ label: 'Evaluations (last 7 days)', value: 1233 });

    expect(findValue().text()).toBe((1233).toLocaleString());
  });

  // The server answers limit + 1 for a capped count; the exact number past the
  // cap is unknown, so the tile says so rather than showing the sentinel.
  describe('with a limit', () => {
    it('renders a value past the limit as the limit with a plus', () => {
      createComponent({ label: 'Evaluations (last 7 days)', value: 1001, limit: 1000 });

      expect(findValue().text()).toBe(`${(1000).toLocaleString()}+`);
    });

    it('renders a value at the limit as is', () => {
      createComponent({ label: 'Evaluations (last 7 days)', value: 1000, limit: 1000 });

      expect(findValue().text()).toBe((1000).toLocaleString());
    });
  });

  // A read that failed is not a zero, so it must not render as one.
  it('renders a placeholder when the value is unknown', () => {
    createComponent({ label: 'Evaluations (last 7 days)', value: null });

    expect(findValue().text()).toContain('—');
  });

  // The dash alone is meaningless to a screen reader.
  it('names the placeholder for assistive technology', () => {
    createComponent({ label: 'Evaluations (last 7 days)', value: null });

    expect(findValue().find('[aria-hidden="true"]').text()).toBe('—');
    expect(findValue().find('.gl-sr-only').text()).toBe('Not available');
  });

  it('renders a skeleton instead of a value while loading', () => {
    createComponent({ label: 'Evaluations (last 7 days)', loading: true });

    expect(findSkeleton().exists()).toBe(true);
    expect(findValue().exists()).toBe(false);
  });
});
