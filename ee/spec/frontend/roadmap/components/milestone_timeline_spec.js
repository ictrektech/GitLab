import Vue from 'vue';
import VueApollo from 'vue-apollo';

import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { cloneDate } from '~/lib/utils/datetime_utility';

import MilestoneItem from 'ee/roadmap/components/milestone_item.vue';
import MilestoneTimelineComponent from 'ee/roadmap/components/milestone_timeline.vue';
import { DATE_RANGES, PRESET_TYPES } from 'ee/roadmap/constants';
import { getTimeframeForRangeType } from 'ee/roadmap/utils/roadmap_utils';

import { mockTimeframeInitialDate, mockMilestone2 } from 'ee_jest/roadmap/mock_data';
import { setLocalSettingsInCache } from '../local_cache_helpers';

Vue.use(VueApollo);

const getTimeframe = (timeframeRangeType, presetType) =>
  getTimeframeForRangeType({
    timeframeRangeType,
    presetType,
    initialDate: mockTimeframeInitialDate,
  });

const mockTimeframeMonths = getTimeframe(DATE_RANGES.CURRENT_YEAR, PRESET_TYPES.MONTHS);
const mockTimeframeWeeks = getTimeframe(DATE_RANGES.CURRENT_YEAR, PRESET_TYPES.WEEKS);
const mockTimeframeMonthsThreeYears = getTimeframe(DATE_RANGES.THREE_YEARS, PRESET_TYPES.MONTHS);
const mockTimeframeQuarters = getTimeframe(DATE_RANGES.THREE_YEARS, PRESET_TYPES.QUARTERS);

const daysAfter = (date, days) => {
  const later = cloneDate(date);
  later.setDate(later.getDate() + days);
  return later;
};

const createMilestone = (id, startDate) => ({ ...mockMilestone2, id, startDate });

describe('MilestoneTimelineComponent', () => {
  let wrapper;

  const createWrapper = ({
    presetType = PRESET_TYPES.MONTHS,
    timeframe = mockTimeframeMonths,
    milestones = [mockMilestone2],
    milestonesExpanded = true,
    mountFn = shallowMountExtended,
  } = {}) => {
    const apolloProvider = createMockApollo();
    setLocalSettingsInCache(apolloProvider, { presetType, timeframe });

    wrapper = mountFn(MilestoneTimelineComponent, {
      apolloProvider,
      propsData: {
        timeframe,
        milestones,
        milestonesExpanded,
      },
    });
  };

  const findMilestoneItems = () => wrapper.findAllComponents(MilestoneItem);
  const findStartColumns = () => {
    const items = findMilestoneItems().wrappers;
    return wrapper
      .findAll('.milestone-timeline-cell')
      .wrappers.flatMap((cell, column) =>
        items.filter((item) => cell.element.contains(item.element)).map(() => column),
      );
  };
  const findRows = () => wrapper.findAllByTestId('milestone-rows');

  describe('by month', () => {
    const milestones = [
      createMilestone(1, new Date(2018, 2, 15)),
      createMilestone(2, new Date(2018, 2, 20)),
      createMilestone(3, new Date(2018, 6, 1)),
      { ...createMilestone(4, cloneDate(mockTimeframeMonths[0])), startDateOutOfRange: true },
      createMilestone(5, new Date(2018, 11, 10)),
    ];

    beforeEach(() => {
      createWrapper({ milestones });
    });

    it('renders each milestone once', () => {
      expect(findMilestoneItems()).toHaveLength(milestones.length);
    });

    it('renders each milestone in its start column, from the first to the last', () => {
      expect(findStartColumns()).toEqual([0, 2, 2, 6, 11]);
      expect(findMilestoneItems().wrappers.map((item) => item.props('milestone').id)).toEqual([
        4, 1, 2, 3, 5,
      ]);
    });

    it('places each milestone in its own row', () => {
      const topById = Object.fromEntries(
        findMilestoneItems().wrappers.map((item) => [
          item.props('milestone').id,
          item.attributes('style'),
        ]),
      );

      expect(topById).toEqual({
        1: 'top: 0px;',
        2: 'top: 32px;',
        3: 'top: 64px;',
        4: 'top: 96px;',
        5: 'top: 128px;',
      });
    });

    it('keeps every column as tall as one row per milestone', () => {
      expect(findRows()).toHaveLength(mockTimeframeMonths.length);
      findRows().wrappers.forEach((rows) => {
        expect(rows.attributes('style')).toBe('height: 160px;');
      });
    });
  });

  describe.each([
    {
      description: 'by month over three years',
      presetType: PRESET_TYPES.MONTHS,
      timeframe: mockTimeframeMonthsThreeYears,
      startDates: [new Date(2019, 1, 10)],
      expectedColumns: [31],
    },
    {
      description: 'by week',
      presetType: PRESET_TYPES.WEEKS,
      timeframe: mockTimeframeWeeks,
      startDates: [
        daysAfter(mockTimeframeWeeks[10], 3),
        daysAfter(mockTimeframeWeeks[10], 7),
        daysAfter(mockTimeframeWeeks[20], 6),
      ],
      expectedColumns: [10, 11, 20],
    },
    {
      description: 'by quarter',
      presetType: PRESET_TYPES.QUARTERS,
      timeframe: mockTimeframeQuarters,
      startDates: [
        cloneDate(mockTimeframeQuarters[4].range[1]),
        cloneDate(mockTimeframeQuarters[5].range[0]),
        cloneDate(mockTimeframeQuarters[6].range[2]),
      ],
      expectedColumns: [4, 5, 6],
    },
  ])('$description', ({ presetType, timeframe, startDates, expectedColumns }) => {
    beforeEach(() => {
      createWrapper({
        presetType,
        timeframe,
        milestones: startDates.map((startDate, index) => createMilestone(index + 1, startDate)),
      });
    });

    it('renders each milestone once, in the column it starts in', () => {
      expect(findStartColumns()).toEqual(expectedColumns);
    });
  });

  describe.each([
    {
      presetType: PRESET_TYPES.QUARTERS,
      timeframe: mockTimeframeQuarters,
      startDates: mockTimeframeQuarters.flatMap(({ range }) => [range[0], range[2]]),
    },
    {
      presetType: PRESET_TYPES.MONTHS,
      timeframe: mockTimeframeMonthsThreeYears,
      startDates: mockTimeframeMonthsThreeYears.flatMap((month) => [
        new Date(month.getFullYear(), month.getMonth(), 1),
        new Date(month.getFullYear(), month.getMonth() + 1, 0),
      ]),
    },
    {
      presetType: PRESET_TYPES.WEEKS,
      timeframe: mockTimeframeWeeks,
      startDates: mockTimeframeWeeks.flatMap((week) => [week, daysAfter(week, 6)]),
    },
  ])('with MilestoneItem mounted, by $presetType', ({ presetType, timeframe, startDates }) => {
    beforeEach(() => {
      createWrapper({
        presetType,
        timeframe,
        milestones: startDates.map((startDate, index) =>
          createMilestone(index + 1, cloneDate(startDate)),
        ),
        mountFn: mountExtended,
      });
    });

    it('draws every milestone that starts on the first or last day of a column', () => {
      expect(wrapper.findAllByTestId('milestone-item-wrapper')).toHaveLength(startDates.length);
    });
  });

  describe('when a milestone starts before the first column', () => {
    beforeEach(() => {
      createWrapper({
        milestones: [
          createMilestone(1, new Date(2017, 11, 31)),
          createMilestone(2, new Date(2018, 0, 1)),
        ],
      });
    });

    it('renders only the milestone that starts in the timeframe', () => {
      expect(findMilestoneItems().wrappers.map((item) => item.props('milestone').id)).toEqual([2]);
    });
  });

  describe('when milestones are collapsed', () => {
    beforeEach(() => {
      createWrapper({ milestonesExpanded: false });
    });

    it('renders no milestones and no rows', () => {
      expect(findMilestoneItems()).toHaveLength(0);
      expect(findRows()).toHaveLength(0);
    });
  });
});
