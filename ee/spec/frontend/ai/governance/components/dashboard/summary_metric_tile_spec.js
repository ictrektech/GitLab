import { GlPopover } from '@gitlab/ui';
import { GlSparklineChart } from '@gitlab/ui/src/charts';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SummaryMetricTile from 'ee/ai/governance/components/dashboard/summary_metric_tile.vue';

describe('SummaryMetricTile', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(SummaryMetricTile, {
      propsData: { label: 'AI agents', ...props },
    });
  };

  const findChart = () => wrapper.findComponent(GlSparklineChart);
  const findDelta = () => wrapper.findComponentByTestId('summary-metric-delta');
  const findSkeleton = () => wrapper.findByTestId('summary-metric-skeleton');
  const findHelpIcon = () => wrapper.findComponentByTestId('summary-metric-help-icon');
  const findHelpPopover = () => wrapper.findComponent(GlPopover);

  it('renders the label and a placeholder value by default', () => {
    createComponent();

    expect(wrapper.text()).toContain('AI agents');
    expect(wrapper.text()).toContain('—');
  });

  it('shows a skeleton and hides the value/chart while loading', () => {
    createComponent({ loading: true, value: '47', chartData: [['Aug 1', 2]] });

    expect(findSkeleton().exists()).toBe(true);
    expect(wrapper.text()).not.toContain('47');
    expect(findChart().exists()).toBe(false);
  });

  it('does not render the delta when no delta is provided', () => {
    createComponent();

    expect(findDelta().exists()).toBe(false);
  });

  it('renders the value and delta when provided', () => {
    createComponent({ value: '47', delta: '+9 this week' });

    expect(wrapper.text()).toContain('47');
    expect(findDelta().exists()).toBe(true);
    expect(findDelta().text()).toBe('+9 this week');
  });

  it.each`
    deltaDirection | expectedVariant
    ${'up'}        | ${'success'}
    ${'down'}      | ${'danger'}
    ${'neutral'}   | ${'muted'}
  `(
    'renders a $expectedVariant delta badge when direction is $deltaDirection',
    ({ deltaDirection, expectedVariant }) => {
      createComponent({ delta: '+9 this week', deltaDirection });

      expect(findDelta().props('variant')).toBe(expectedVariant);
    },
  );

  it.each`
    deltaDirection | expectedIcon
    ${'up'}        | ${'arrow-up'}
    ${'down'}      | ${'arrow-down'}
  `(
    'shows a $expectedIcon trend icon when direction is $deltaDirection',
    ({ deltaDirection, expectedIcon }) => {
      createComponent({ delta: '+9 this week', deltaDirection });

      expect(findDelta().props('icon')).toBe(expectedIcon);
    },
  );

  it('renders no help icon or popover by default', () => {
    createComponent();

    expect(findHelpIcon().exists()).toBe(false);
    expect(findHelpPopover().exists()).toBe(false);
  });

  it('renders a labelled help icon that targets a popover with the help text', () => {
    createComponent({ helpText: 'Chat is not counted.' });

    expect(findHelpIcon().props('icon')).toBe('information-o');
    expect(findHelpIcon().attributes('aria-label')).toBe('About AI agents');
    expect(findHelpPopover().text()).toBe('Chat is not counted.');
    expect(findHelpPopover().props('title')).toBe('AI agents');
    expect(findHelpPopover().props('target')).toBe(findHelpIcon().attributes('id'));
  });

  it('renders the sparkline only when chart data is present', () => {
    createComponent();
    expect(findChart().exists()).toBe(false);

    createComponent({
      chartData: [
        [1, 2],
        [2, 4],
      ],
    });
    expect(findChart().exists()).toBe(true);
  });
});
