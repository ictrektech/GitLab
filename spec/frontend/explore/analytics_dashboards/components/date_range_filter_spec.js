import { GlBadge, GlCollapsibleListbox, GlDaterangePicker, GlFormGroup, GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import DateRangeFilter from '~/explore/analytics_dashboards/components/date_range_filter.vue';
import {
  DEFAULT_DATE_RANGE_OPTIONS,
  DATE_RANGE_OPTIONS,
  TODAY,
  DEFAULT_SELECTED_DATE_RANGE_OPTION,
} from '~/explore/analytics_dashboards/components/constants';
import { dateRangeOptionToFilter } from '~/explore/analytics_dashboards/components/utils';

describe('DateRangeFilter', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;

  const AVAILABLE_OPTIONS = DEFAULT_DATE_RANGE_OPTIONS.map((key) => DATE_RANGE_OPTIONS[key]);
  const dateRangeOption = AVAILABLE_OPTIONS.find((option) => !option.showDateRangePicker);
  const customRangeOption = AVAILABLE_OPTIONS.find((option) => option.showDateRangePicker);

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(DateRangeFilter, {
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      stubs: { GlFormGroup },
      propsData: {
        ...props,
      },
    });
  };

  const findDateRangePicker = () => wrapper.findComponent(GlDaterangePicker);
  const findCollapsibleListBox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findHelpIcon = () => findFormGroup().findComponent(GlIcon);
  const findDateRangeText = () => wrapper.findByTestId('date-range-text');
  const findLimitBadge = () => wrapper.findComponent(GlBadge);

  describe('default behaviour', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders a dropdown with the value set to the default selected option', () => {
      expect(findCollapsibleListBox().props().selected).toBe(
        DATE_RANGE_OPTIONS[DEFAULT_SELECTED_DATE_RANGE_OPTION].key,
      );
    });

    it('renders a dropdown item for each option', () => {
      AVAILABLE_OPTIONS.forEach((option, idx) => {
        expect(findCollapsibleListBox().props('items').at(idx).text).toBe(option.text);
      });
    });

    it('emits the selected date range when a dropdown item with a date range is clicked', () => {
      findCollapsibleListBox().vm.$emit('select', dateRangeOption.key);

      expect(wrapper.emitted('change')).toStrictEqual([[dateRangeOptionToFilter(dateRangeOption)]]);
    });

    it('labels the dropdown "Date range"', () => {
      expect(findFormGroup().text()).toContain('Date range');
    });

    it('shows the selected range as text', () => {
      expect(findDateRangeText().text()).toBe(
        new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeZone: 'UTC' }).formatRange(
          DATE_RANGE_OPTIONS[DEFAULT_SELECTED_DATE_RANGE_OPTION].startDate,
          DATE_RANGE_OPTIONS[DEFAULT_SELECTED_DATE_RANGE_OPTION].endDate,
        ),
      );
    });

    it('does not show the date range limit badge', () => {
      expect(findLimitBadge().exists()).toBe(false);
    });

    it('shows an icon next to the label with a tooltip explaining dates are in UTC', () => {
      const helpIcon = findHelpIcon();
      const tooltip = getBinding(helpIcon.element, 'gl-tooltip');

      expect(helpIcon.props('name')).toBe('information-o');
      expect(helpIcon.attributes('title')).toBe(
        'Dates and times are displayed in the UTC timezone.',
      );
      expect(tooltip).toBeDefined();
    });

    it('does not have the class "gl-flex-col"', () => {
      expect(wrapper.classes()).not.toContain('gl-flex-col');
    });
  });

  describe('with a default option', () => {
    beforeEach(() => {
      createWrapper({ defaultOption: customRangeOption.key });
    });

    it('selects the provided default option', () => {
      expect(findCollapsibleListBox().props().selected).toBe(customRangeOption.key);
    });
  });

  describe('options', () => {
    it('overrides the default options', () => {
      const options = ['7d', 'today'];
      createWrapper({ options });

      const res = findCollapsibleListBox()
        .props('items')
        .map(({ value }) => value);

      expect(res).toEqual(options);
    });

    it('filters out invalid options', () => {
      createWrapper({ options: [...DEFAULT_DATE_RANGE_OPTIONS, '25d'] });

      expect(
        findCollapsibleListBox()
          .props('items')
          .map(({ value }) => value),
      ).not.toContain('25d');
    });
  });

  describe('date range picker', () => {
    describe('by default', () => {
      const { startDate, endDate } = DATE_RANGE_OPTIONS[DEFAULT_SELECTED_DATE_RANGE_OPTION];

      beforeEach(() => {
        createWrapper({ startDate, endDate });
      });

      it('adds the class "gl-flex-col" when a custom date range is selected', async () => {
        await findCollapsibleListBox().vm.$emit('select', customRangeOption.key);

        expect(wrapper.classes()).toContain('gl-flex-col');
      });

      it('does not emit a new date range when the option shows the date range picker', async () => {
        await findCollapsibleListBox().vm.$emit('select', customRangeOption.key);

        expect(wrapper.emitted('change')).toBeUndefined();
      });

      it('shows the date range picker with the provided date range when the option enables it', async () => {
        expect(findDateRangePicker().exists()).toBe(false);

        await findCollapsibleListBox().vm.$emit('select', customRangeOption.key);

        expect(findDateRangePicker().props()).toMatchObject({
          toLabel: 'To',
          fromLabel: 'From',
          tooltip: '',
          defaultMaxDate: TODAY,
          maxDateRange: 0,
          value: {
            startDate,
            endDate,
          },
          defaultStartDate: startDate,
          defaultEndDate: endDate,
        });
      });

      describe('once a custom range is selected', () => {
        const customRange = {
          startDate: new Date(Date.UTC(2026, 0, 5)),
          endDate: new Date(Date.UTC(2026, 2, 31)),
        };

        beforeEach(async () => {
          await findCollapsibleListBox().vm.$emit('select', customRangeOption.key);
        });

        it('emits the range the picker sets', () => {
          findDateRangePicker().vm.$emit('input', customRange);

          expect(wrapper.emitted('change')).toStrictEqual([
            [{ ...customRange, dateRangeOption: 'custom' }],
          ]);
        });

        // The picker emits each bound as it is picked, and a panel would fill the missing one
        // with a default, querying a window nobody asked for.
        it.each([
          ['start', { ...customRange, startDate: null }],
          ['end', { ...customRange, endDate: null }],
        ])('does not emit a range that is still missing its %s', (_, halfFilledRange) => {
          findDateRangePicker().vm.$emit('input', halfFilledRange);

          expect(wrapper.emitted('change')).toBeUndefined();
        });
      });
    });

    describe('with a custom range selected', () => {
      // The picker works in local time, so the custom range arrives at local midnight.
      const startDate = new Date(2026, 0, 1);
      const endDate = new Date(2026, 1, 1);

      beforeEach(async () => {
        createWrapper({ startDate, endDate });
        await findCollapsibleListBox().vm.$emit('select', customRangeOption.key);
      });

      it('shows the custom range as text, keeping the calendar days the picker shows', () => {
        expect(findDateRangeText().text()).toBe('Jan 1\u2009–\u2009Feb 1, 2026');
      });

      it('does not show the limit badge when there is no limit', () => {
        expect(findLimitBadge().exists()).toBe(false);
      });
    });

    describe.each([
      { dateRangeLimit: 1, expectedText: 'Limited to 1 day' },
      { dateRangeLimit: 12, expectedText: 'Limited to 12 days' },
      { dateRangeLimit: 180, expectedText: 'Limited to 180 days' },
    ])('when given a date range limit of $dateRangeLimit', ({ dateRangeLimit, expectedText }) => {
      beforeEach(() => {
        createWrapper({ dateRangeLimit });
      });

      it('does not show the limit badge for a preset range', () => {
        expect(findLimitBadge().exists()).toBe(false);
      });

      describe('when a custom range is selected', () => {
        beforeEach(async () => {
          await findCollapsibleListBox().vm.$emit('select', customRangeOption.key);
        });

        it('applies the limit to the date range picker', () => {
          expect(findDateRangePicker().props('maxDateRange')).toBe(dateRangeLimit);
        });

        it('shows the limit in a badge', () => {
          expect(findLimitBadge().text()).toBe(expectedText);
        });

        it('keeps the tooltip to the UTC note', () => {
          expect(findHelpIcon().attributes('title')).toBe(
            'Dates and times are displayed in the UTC timezone.',
          );
        });
      });
    });
  });
});
