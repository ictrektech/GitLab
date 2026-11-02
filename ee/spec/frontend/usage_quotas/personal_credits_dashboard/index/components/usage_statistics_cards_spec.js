import { GlCard, GlSprintf } from '@gitlab/ui';
import timezoneMock from 'timezone-mock';
import UsageStatisticsCards from 'ee/usage_quotas/personal_credits_dashboard/index/components/usage_statistics_cards.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';

const GlCardStub = {
  template: '<div><slot name="header" /> <slot /></div>',
};

describe('UsageStatisticsCards', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;

  const defaultProps = {
    totalUsedCredits: 42.5,
    dailyAverage: 3.2,
    peakDayUsage: 9.1,
    peakDayDate: '2026-07-15',
  };

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(UsageStatisticsCards, {
      propsData: { ...defaultProps, ...props },
      stubs: { GlCard: GlCardStub, GlSprintf },
    });
  };

  const findTotalUsageCard = () => wrapper.findByTestId('range-total-usage-card');
  const findDailyAverageCard = () => wrapper.findByTestId('daily-average-card');
  const findPeakDayUsageCard = () => wrapper.findByTestId('peak-day-usage-card');
  const findAllCards = () => wrapper.findAllComponents(GlCard);

  describe.each(['Australia/Adelaide', 'Europe/London', 'US/Pacific'])(
    '%s timezone',
    (timezone) => {
      beforeAll(() => timezoneMock.register(timezone));
      afterAll(() => timezoneMock.unregister());

      beforeEach(() => {
        createComponent();
      });

      it('renders exactly three cards', () => {
        expect(findAllCards()).toHaveLength(3);
      });

      it('renders the total usage card with the formatted value in credits', () => {
        expect(findTotalUsageCard().text()).toMatchInterpolatedText('Total usage 42.50 credits');
      });

      it('renders the daily average usage card with the formatted value in credits', () => {
        expect(findDailyAverageCard().text()).toMatchInterpolatedText(
          'Daily average usage 3.20 credits',
        );
      });

      it('renders the peak day usage card with the formatted value in credits and the date', () => {
        expect(findPeakDayUsageCard().text()).toMatchInterpolatedText(
          'Peak day usage 9.10 credits on Jul 15',
        );
      });

      describe('when the values are exactly one credit', () => {
        beforeEach(() => {
          createComponent({ props: { totalUsedCredits: 1, dailyAverage: 1, peakDayUsage: 1 } });
        });

        it('renders the singular unit on every card', () => {
          expect(findTotalUsageCard().text()).toMatchInterpolatedText('Total usage 1 credit');
          expect(findDailyAverageCard().text()).toMatchInterpolatedText(
            'Daily average usage 1 credit',
          );
          expect(findPeakDayUsageCard().text()).toMatchInterpolatedText(
            'Peak day usage 1 credit on Jul 15',
          );
        });
      });

      describe('when there is no peak day', () => {
        beforeEach(() => {
          createComponent({ props: { peakDayUsage: 0, peakDayDate: '' } });
        });

        it('renders zero credits without a date', () => {
          expect(findPeakDayUsageCard().text()).toMatchInterpolatedText('Peak day usage 0 credits');
        });
      });
    },
  );
});
