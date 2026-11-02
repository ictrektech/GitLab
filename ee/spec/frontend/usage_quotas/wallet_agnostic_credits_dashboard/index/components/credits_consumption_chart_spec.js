import { DATA_VIZ_AQUA_500 } from '@gitlab/ui/src/tokens/build/js/tokens';
import { GlStackedColumnChart } from '@gitlab/ui/src/charts';
import { GlButton, GlSprintf } from '@gitlab/ui';
import CreditsConsumptionChart from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/index/components/credits_consumption_chart.vue';
import { shallowMountExtended, getInstanceSlots } from 'helpers/vue_test_utils_helper';
import { getSlotText } from 'ee_jest/usage_quotas/usage_billing/components/__helpers__/get_slot_text';
import { mockSubscriptionCreditsUsageData } from '../../mock_data';

describe('CreditsConsumptionChart', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(CreditsConsumptionChart, {
      propsData: {
        startDate: mockSubscriptionCreditsUsageData.data.subscriptionUsage.startDate,
        endDate: mockSubscriptionCreditsUsageData.data.subscriptionUsage.endDate,
        dailyUsage: mockSubscriptionCreditsUsageData.data.subscriptionUsage.dailyUsage,
        totalCredits: mockSubscriptionCreditsUsageData.data.subscriptionUsage.creditsUsed,
        ...propsData,
      },
      stubs: {
        GlButton,
        GlSprintf,
      },
    });
  };

  const findChart = () => wrapper.findComponent(GlStackedColumnChart);

  beforeEach(() => {
    createComponent();
  });

  it('renders the stacked column chart', () => {
    expect(findChart().exists()).toBe(true);
  });

  it('renders the billed credits total', () => {
    expect(wrapper.text()).toContain('Billable: 13.8k credits');
  });

  describe('date range calculation', () => {
    it('generates all dates in the billing period for groupBy', () => {
      createComponent({
        startDate: '2026-02-01',
        endDate: '2026-02-05',
        dailyUsage: [{ creditsUsed: 100, date: '2026-02-03' }],
      });

      expect(findChart().props('groupBy')).toEqual([
        '2026-02-01',
        '2026-02-02',
        '2026-02-03',
        '2026-02-04',
        '2026-02-05',
      ]);
    });
  });

  describe('data series rendering', () => {
    describe('data array building', () => {
      it('fills missing dates with null values', () => {
        createComponent({
          startDate: '2026-02-01',
          endDate: '2026-02-05',
          dailyUsage: [
            { creditsUsed: 100, date: '2026-02-01' },
            { creditsUsed: 200, date: '2026-02-03' },
            { creditsUsed: 300, date: '2026-02-05' },
          ],
        });

        const dailyData = findChart().props('bars')[0].data;

        expect(dailyData).toEqual([
          ['2026-02-01', 100],
          ['2026-02-02', null],
          ['2026-02-03', 200],
          ['2026-02-04', null],
          ['2026-02-05', 300],
        ]);
      });
    });
  });

  describe('non-billable usage', () => {
    const findBars = () => findChart().props('bars');
    const findNonBillableTotal = () => wrapper.findByTestId('non-billable-total');
    const usageFor = (skipReason) => ({
      productId: 'orbit',
      skipReason,
      totalCreditsUsed: 1,
      dailyUsage: [{ creditsUsed: 1, date: '2026-02-01' }],
    });

    describe('when there is no non-billable usage', () => {
      it('renders only the billable usage series', () => {
        expect(findBars().map(({ name }) => name)).toEqual(['Billable usage']);
      });

      it('does not render the non-billable total', () => {
        expect(findNonBillableTotal().exists()).toBe(false);
      });
    });

    describe('when there is non-billable usage', () => {
      beforeEach(() => {
        createComponent({
          startDate: '2026-02-01',
          endDate: '2026-02-03',
          dailyUsage: [{ creditsUsed: 500, date: '2026-02-01' }],
          nonBillableUsage: [
            {
              productId: 'orbit',
              skipReason: 'promo',
              totalCreditsUsed: 30,
              dailyUsage: [
                { creditsUsed: 10, date: '2026-02-01' },
                { creditsUsed: 20, date: '2026-02-03' },
              ],
            },
            {
              productId: 'hosted_runners',
              skipReason: 'promo',
              totalCreditsUsed: 5,
              dailyUsage: [{ creditsUsed: 5, date: '2026-02-01' }],
            },
            {
              productId: 'orbit',
              skipReason: null,
              totalCreditsUsed: 3,
              dailyUsage: [{ creditsUsed: 3, date: '2026-02-02' }],
            },
            {
              productId: 'orbit',
              skipReason: 'some_new_reason',
              totalCreditsUsed: 2,
              dailyUsage: [{ creditsUsed: 2, date: '2026-02-02' }],
            },
          ],
        });
      });

      it('stacks one series per skip reason after the billable usage series', () => {
        expect(findBars().map(({ name, stack }) => [name, stack])).toEqual([
          ['Billable usage', 'usage'],
          ['Non-billable usage (Promotional)', 'usage'],
          ['Non-billable usage (Other)', 'usage'],
        ]);
      });

      it('sums usage across products per date and fills missing dates with null', () => {
        expect(findBars()[1].data).toEqual([
          ['2026-02-01', 15],
          ['2026-02-02', null],
          ['2026-02-03', 20],
        ]);
      });

      it('groups unknown and missing skip reasons under Other', () => {
        expect(findBars()[2].data).toEqual([
          ['2026-02-01', null],
          ['2026-02-02', 5],
          ['2026-02-03', null],
        ]);
      });

      it('builds the palette from the series colors', () => {
        expect(findChart().props('customPalette')).toEqual(
          findBars().map(({ itemStyle }) => itemStyle.color),
        );
      });

      it('renders the non-billable total next to the billed total', () => {
        expect(findNonBillableTotal().text()).toBe('Non-billable: 40 credits');
      });
    });

    describe('when an entry has no daily usage', () => {
      beforeEach(() => {
        createComponent({
          nonBillableUsage: [
            { productId: 'orbit', skipReason: 'beta', totalCreditsUsed: 0, dailyUsage: [] },
          ],
        });
      });

      it('does not render a series for it', () => {
        expect(findBars().map(({ name }) => name)).toEqual(['Billable usage']);
      });
    });

    describe('when every skip reason has usage', () => {
      const allReasons = ['promo', 'beta', 'some_new_reason', null];

      beforeEach(() => {
        createComponent({
          startDate: '2026-02-01',
          endDate: '2026-02-01',
          dailyUsage: [{ creditsUsed: 500, date: '2026-02-01' }],
          nonBillableUsage: allReasons.map(usageFor),
        });
      });

      it('gives each series a distinct color', () => {
        const colors = findBars().map(({ itemStyle }) => itemStyle.color);

        expect(colors).toHaveLength(4);
        expect(new Set(colors).size).toBe(colors.length);
      });
    });

    describe('when only one skip reason has usage', () => {
      beforeEach(() => {
        createComponent({
          startDate: '2026-02-01',
          endDate: '2026-02-01',
          nonBillableUsage: [usageFor('beta')],
        });
      });

      it('keeps the color of that reason', () => {
        expect(findBars()[1]).toMatchObject({
          name: 'Non-billable usage (Beta)',
          itemStyle: { color: DATA_VIZ_AQUA_500 },
        });
      });
    });
  });

  describe('x-axis label formatter', () => {
    it('formats ISO date strings as short month and day', () => {
      const { formatter } = findChart().props('option').xAxis.axisLabel;

      expect(formatter('2026-02-03')).toBe('Feb 3');
    });
  });

  describe('tooltip-value slot', () => {
    let slotFn;

    beforeEach(() => {
      slotFn = getInstanceSlots(wrapper.findComponent(GlStackedColumnChart).vm)['tooltip-value'];
    });

    it('formats a regular number', () => {
      const slotContent = slotFn({ value: [null, 1000] });

      expect(getSlotText(slotContent)).toContain('1k');
    });

    it('formats zero as a visible value', () => {
      const slotContent = slotFn({ value: [null, 0] });

      expect(getSlotText(slotContent)).toContain('0');
    });

    it('renders a dash for null values', () => {
      const slotContent = slotFn({ value: [null, null] });

      expect(getSlotText(slotContent)).toContain('—');
    });
  });
});
