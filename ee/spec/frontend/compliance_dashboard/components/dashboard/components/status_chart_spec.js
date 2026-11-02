import { shallowMount } from '@vue/test-utils';
import { GlBarChart } from '@gitlab/ui/src/charts';
import { GL_STATUS_NEUTRAL_ICON_COLOR } from '@gitlab/ui/src/tokens/build/js/tokens';

import { GL_LIGHT } from '~/constants';
import StatusChart from 'ee/compliance_dashboard/components/dashboard/components/status_chart.vue';

describe('Compliance dashboard status chart', () => {
  let wrapper;
  const pushMock = jest.fn();
  const data = {
    passed: 10,
    failed: 15,
    pending: 25,
    notApplicable: 5,
  };

  function createComponent(props) {
    wrapper = shallowMount(StatusChart, {
      propsData: {
        colorScheme: GL_LIGHT,
        path: 'dummy',
        data,
        ...props,
      },
      mocks: {
        $router: {
          push: pushMock,
        },
      },
    });
  }

  it('Calls push when chart is clicked', () => {
    createComponent();
    const chart = wrapper.getComponent(GlBarChart);
    chart.vm.$emit('chart-item-clicked');
    expect(pushMock).toHaveBeenCalledWith({ name: wrapper.props('path') });
  });

  it('Passes correct config to underlying bar chart', () => {
    createComponent();
    const chartProps = wrapper.getComponent(GlBarChart).props();
    expect(chartProps.data.items.map((x) => x.value[0])).toStrictEqual([
      data.passed,
      data.pending,
      data.failed,
      data.notApplicable,
    ]);
    expect(chartProps.data.items.map((x) => x.value[1])).toStrictEqual([
      'Passed',
      'Pending',
      'Failed',
      'Not applicable',
    ]);
  });

  it('uses neutral color for not applicable bar', () => {
    createComponent();
    const { items } = wrapper.getComponent(GlBarChart).props('data');
    expect(items[3].itemStyle.color).toBe(GL_STATUS_NEUTRAL_ICON_COLOR);
  });

  it.each([undefined, null])('defaults not applicable to 0 when it is %s', (notApplicable) => {
    createComponent({ data: { passed: 1, failed: 2, pending: 3, notApplicable } });
    const { items } = wrapper.getComponent(GlBarChart).props('data');
    expect(items[3].value[0]).toBe(0);
  });
});
