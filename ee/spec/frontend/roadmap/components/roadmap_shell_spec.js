import Vue from 'vue';
import VueApollo from 'vue-apollo';

import { createAlert, VARIANT_WARNING } from '~/alert';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';

import RoadmapShell from 'ee/roadmap/components/roadmap_shell.vue';
import MilestonesListSection from 'ee/roadmap/components/milestones_list_section.vue';
import { DATE_RANGES, PRESET_TYPES } from 'ee/roadmap/constants';
import eventHub from 'ee/roadmap/event_hub';
import { cacheConfig } from 'ee/roadmap/graphql';
import { getTimeframeForRangeType } from 'ee/roadmap/utils/roadmap_utils';

import groupMilestonesQuery from 'ee/roadmap/queries/group_milestones.query.graphql';

import {
  mockEpic,
  mockTimeframeInitialDate,
  mockGroupMilestonesQueryResponse,
  mockGroupMilestonesQueryResponseWithInvalidDates,
  mockGroupMilestonesQueryResponsePage1,
  mockGroupMilestonesQueryResponsePage2,
  mockSubgroupMilestoneNode,
  createMockGroupMilestonesQueryResponse,
} from 'ee_jest/roadmap/mock_data';
import { setLocalSettingsInCache, updateLocalSettingsInCache } from '../local_cache_helpers';

jest.mock('~/alert');

Vue.use(VueApollo);

const mockTimeframeMonths = getTimeframeForRangeType({
  timeframeRangeType: DATE_RANGES.CURRENT_YEAR,
  presetType: PRESET_TYPES.MONTHS,
  initialDate: mockTimeframeInitialDate,
});

const mockTimeframeWeeks = getTimeframeForRangeType({
  timeframeRangeType: DATE_RANGES.CURRENT_YEAR,
  presetType: PRESET_TYPES.WEEKS,
  initialDate: mockTimeframeInitialDate,
});

const groupMilestonesQueryHandler = jest.fn().mockResolvedValue(mockGroupMilestonesQueryResponse);

const MAX_PAGES_SERVED = 60;

const serveMilestonesPage = ({ after }, { pageSize = 1, pageCount = MAX_PAGES_SERVED } = {}) => {
  const page = after ? Number(after) + 1 : 1;
  const nodes = Array.from({ length: pageSize }, (_, index) => ({
    ...mockSubgroupMilestoneNode,
    id: `gid://gitlab/Milestone/${page * 1000 + index}`,
  }));
  return Promise.resolve(
    createMockGroupMilestonesQueryResponse(nodes, {
      hasNextPage: page < pageCount,
      endCursor: String(page),
    }),
  );
};

describe('RoadmapShell', () => {
  let wrapper;
  let apolloProvider;

  const findRoadmapShellWrapper = () => wrapper.findByTestId('roadmap-shell');
  const findMilestonesListSection = () => wrapper.findComponent(MilestonesListSection);
  const findMilestoneIds = () =>
    findMilestonesListSection()
      .props('milestones')
      .map(({ id }) => id);

  const mountComponent = ({ epics = [mockEpic] } = {}) => {
    wrapper = shallowMountExtended(RoadmapShell, {
      attachTo: document.body,
      propsData: {
        epics,
        epicsFetchNextPageInProgress: false,
        hasNextPage: false,
      },
      provide: {
        fullPath: 'gitlab-org',
        epicIid: null,
      },
      apolloProvider,
    });
  };

  const createComponent = ({
    epics = [mockEpic],
    timeframe = mockTimeframeMonths,
    isShowingMilestones = false,
  } = {}) => {
    apolloProvider = createMockApollo(
      [[groupMilestonesQuery, groupMilestonesQueryHandler]],
      {},
      cacheConfig,
    );
    setLocalSettingsInCache(apolloProvider, {
      timeframeRangeType: DATE_RANGES.CURRENT_YEAR,
      presetType: PRESET_TYPES.MONTHS,
      timeframe,
      isShowingMilestones,
    });

    mountComponent({ epics });
  };

  it('sets container styles on component mount', async () => {
    createComponent();
    await waitForPromises();

    expect(findRoadmapShellWrapper().attributes('style')).toBe('height: calc(100vh - 0px);');
  });

  it('emits `epics-list-scrolled` event via event hub on scroll', () => {
    jest.spyOn(eventHub, '$emit').mockImplementation();

    createComponent();
    findRoadmapShellWrapper().trigger('scroll');

    expect(eventHub.$emit).toHaveBeenCalledWith('epics-list-scrolled', {
      clientHeight: 0,
      scrollHeight: 0,
      scrollLeft: 0,
      scrollTop: 0,
    });
  });

  it('does not call milestones query if milestones are not shown', () => {
    createComponent();

    expect(groupMilestonesQueryHandler).not.toHaveBeenCalled();
  });

  describe('when milestones are shown', () => {
    it('calls the groupMilestonesQuery with the correct timeframe', async () => {
      createComponent({ isShowingMilestones: true });
      await waitForPromises();

      expect(groupMilestonesQueryHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          timeframe: {
            end: '2018-12-31',
            start: '2018-01-01',
          },
        }),
      );
    });

    describe('when milestones query is successful', () => {
      it('renders the MilestonesListSection component', async () => {
        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        expect(findMilestonesListSection().exists()).toBe(true);
      });

      it('passes the correct number of milestones to the MilestonesListSection component', async () => {
        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        expect(findMilestonesListSection().props('milestones')).toHaveLength(2);
      });

      it('filters away a milestone with invalid dates', async () => {
        groupMilestonesQueryHandler.mockResolvedValue(
          mockGroupMilestonesQueryResponseWithInvalidDates,
        );

        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        expect(findMilestonesListSection().props('milestones')).toHaveLength(1);
      });
    });

    describe('when milestones query is unsuccessful', () => {
      beforeEach(async () => {
        groupMilestonesQueryHandler.mockRejectedValue('Houston, we have a problem');

        createComponent({ isShowingMilestones: true });
        await waitForPromises();
      });

      it('does not render the MilestonesListSection component', () => {
        expect(findMilestonesListSection().exists()).toBe(false);
      });

      it('creates an alert', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong while fetching milestones',
        });
      });
    });

    describe('when milestones span more than one page', () => {
      beforeEach(async () => {
        groupMilestonesQueryHandler
          .mockResolvedValueOnce(mockGroupMilestonesQueryResponsePage1)
          .mockResolvedValueOnce(mockGroupMilestonesQueryResponsePage2);

        createComponent({ isShowingMilestones: true });
        await waitForPromises();
      });

      it('requests the next page with the end cursor of the previous page', () => {
        expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(2);
        expect(groupMilestonesQueryHandler).toHaveBeenNthCalledWith(
          1,
          expect.not.objectContaining({ after: expect.anything() }),
        );
        expect(groupMilestonesQueryHandler).toHaveBeenNthCalledWith(
          2,
          expect.objectContaining({ first: 100, after: 'milestones-page-1-end' }),
        );
      });

      it('passes the milestones from every page to the MilestonesListSection component', () => {
        expect(
          findMilestonesListSection()
            .props('milestones')
            .map(({ title }) => title),
        ).toEqual([
          'Sprint - Tempore voluptatibus et aut consequatur similique animi dolores veritatis.',
          'Milestone 2',
          mockSubgroupMilestoneNode.title,
        ]);
      });

      describe('when the query variables change', () => {
        beforeEach(async () => {
          groupMilestonesQueryHandler
            .mockResolvedValueOnce(mockGroupMilestonesQueryResponsePage1)
            .mockResolvedValueOnce(mockGroupMilestonesQueryResponsePage2);

          updateLocalSettingsInCache(apolloProvider, {
            presetType: PRESET_TYPES.WEEKS,
            timeframe: mockTimeframeWeeks,
          });
          await waitForPromises();
        });

        it('requests the next page of the new range, whatever its end cursor', () => {
          expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(4);
          expect(groupMilestonesQueryHandler).toHaveBeenLastCalledWith(
            expect.objectContaining({ after: 'milestones-page-1-end' }),
          );
        });
      });
    });

    describe('when fetching a later page fails', () => {
      beforeEach(async () => {
        groupMilestonesQueryHandler
          .mockResolvedValueOnce(mockGroupMilestonesQueryResponsePage1)
          .mockRejectedValueOnce(new Error('Houston, we have a problem'));

        createComponent({ isShowingMilestones: true });
        await waitForPromises();
      });

      it('creates an alert once and keeps the milestones already fetched', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong while fetching milestones',
        });
        expect(findMilestonesListSection().props('milestones')).toHaveLength(2);
      });
    });

    describe('when the next page keeps coming', () => {
      const dismiss = jest.fn();

      beforeEach(async () => {
        createAlert.mockReturnValue({ dismiss });
        groupMilestonesQueryHandler.mockImplementation(serveMilestonesPage);

        createComponent({ isShowingMilestones: true });
        await waitForPromises();
      });

      it('requests each page with the end cursor of the page before it', () => {
        expect(groupMilestonesQueryHandler.mock.calls.map(([{ after }]) => after)).toEqual([
          undefined,
          ...Array.from({ length: 19 }, (_, index) => String(index + 1)),
        ]);
        expect(new Set(findMilestoneIds()).size).toBe(20);
      });

      it('stops after 20 requests and creates a warning alert', () => {
        expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(20);
        expect(findMilestonesListSection().props('milestones')).toHaveLength(20);
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Maximum number of milestones loaded (2,000)',
          variant: VARIANT_WARNING,
        });
      });

      describe('when the query variables change', () => {
        beforeEach(async () => {
          updateLocalSettingsInCache(apolloProvider, {
            presetType: PRESET_TYPES.WEEKS,
            timeframe: mockTimeframeWeeks,
          });
          await waitForPromises();
        });

        it('starts counting again', () => {
          expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(40);
        });
      });

      describe('when a setting outside the query variables changes', () => {
        beforeEach(async () => {
          updateLocalSettingsInCache(apolloProvider, { bufferSize: 42 });
          await waitForPromises();
        });

        it('keeps the alert', () => {
          expect(dismiss).not.toHaveBeenCalled();
        });
      });

      describe('when milestones are hidden', () => {
        beforeEach(async () => {
          updateLocalSettingsInCache(apolloProvider, { isShowingMilestones: false });
          await waitForPromises();
        });

        it('dismisses the alert', () => {
          expect(dismiss).toHaveBeenCalledTimes(1);
        });
      });

      describe('when the roadmap is unmounted', () => {
        beforeEach(() => {
          wrapper.destroy();
        });

        it('dismisses the alert', () => {
          expect(dismiss).toHaveBeenCalledTimes(1);
        });
      });
    });

    describe('when the 20th page is the last', () => {
      beforeEach(async () => {
        groupMilestonesQueryHandler.mockImplementation((variables) =>
          serveMilestonesPage(variables, { pageCount: 20 }),
        );

        createComponent({ isShowingMilestones: true });
        await waitForPromises();
      });

      it('loads every page and creates no alert', () => {
        expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(20);
        expect(findMilestonesListSection().props('milestones')).toHaveLength(20);
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when milestones are hidden and shown again while a page is loading', () => {
      let fetchMoreSpy;

      beforeEach(async () => {
        const heldPages = [];
        groupMilestonesQueryHandler.mockImplementation((variables) => {
          const page = serveMilestonesPage(variables, { pageSize: 100 });
          if (variables.after === '1') {
            return new Promise((resolve) => {
              heldPages.push(() => resolve(page));
            });
          }
          return page;
        });

        createComponent({ isShowingMilestones: true });
        fetchMoreSpy = jest.spyOn(wrapper.vm.$apollo.queries.milestones, 'fetchMore');
        await waitForPromises();

        updateLocalSettingsInCache(apolloProvider, { isShowingMilestones: false });
        await waitForPromises();
        updateLocalSettingsInCache(apolloProvider, { isShowingMilestones: true });
        await waitForPromises();

        heldPages.forEach((release) => release());
        await waitForPromises();
      });

      it('requests the page that was loading once', () => {
        expect(
          fetchMoreSpy.mock.calls.filter(([{ variables }]) => variables.after === '1'),
        ).toHaveLength(1);
      });

      it('shows each milestone once', () => {
        const ids = findMilestoneIds();

        expect(new Set(ids).size).toBe(ids.length);
      });

      it('does not count the page shown again as a request', () => {
        expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(20);
      });

      it('loads 2,000 milestones before it creates the alert', () => {
        expect(findMilestonesListSection().props('milestones')).toHaveLength(2000);
        expect(createAlert).toHaveBeenCalledTimes(1);
      });
    });

    describe('when the milestone title filter changes and changes back while a page is loading', () => {
      let fetchMoreSpy;

      beforeEach(async () => {
        const heldPages = [];
        groupMilestonesQueryHandler.mockImplementation((variables) => {
          const page = serveMilestonesPage(variables, { pageCount: 3 });
          if (variables.after === '1' && !variables.searchTitle) {
            return new Promise((resolve) => {
              heldPages.push(() => resolve(page));
            });
          }
          return page;
        });

        createComponent({ isShowingMilestones: true });
        fetchMoreSpy = jest.spyOn(wrapper.vm.$apollo.queries.milestones, 'fetchMore');
        await waitForPromises();

        updateLocalSettingsInCache(apolloProvider, { filterParams: { milestoneTitle: 'Sprint' } });
        await waitForPromises();
        updateLocalSettingsInCache(apolloProvider, { filterParams: {} });
        await waitForPromises();

        heldPages.forEach((release) => release());
        await waitForPromises();
      });

      it('requests each page of each filter once', () => {
        expect(fetchMoreSpy.mock.calls.map(([{ variables }]) => variables.after)).toEqual([
          '1',
          '1',
          '2',
          '2',
        ]);
        expect(
          groupMilestonesQueryHandler.mock.calls.map(([{ searchTitle, after }]) => [
            searchTitle,
            after,
          ]),
        ).toEqual([
          [undefined, undefined],
          [undefined, '1'],
          ['Sprint', undefined],
          ['Sprint', '1'],
          ['Sprint', '2'],
          [undefined, '2'],
        ]);
      });

      it('shows each milestone once', () => {
        const ids = findMilestoneIds();

        expect(ids).toHaveLength(3);
        expect(new Set(ids).size).toBe(3);
      });
    });

    describe('when the shell is remounted while a milestones page is loading', () => {
      beforeEach(async () => {
        const heldPages = [];
        groupMilestonesQueryHandler.mockImplementation((variables) => {
          const page = serveMilestonesPage(variables, { pageCount: 3 });
          if (variables.after === '1') {
            return new Promise((resolve) => {
              heldPages.push(() => resolve(page));
            });
          }
          return page;
        });

        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        wrapper.destroy();
        mountComponent();
        await waitForPromises();

        heldPages.forEach((release) => release());
        await waitForPromises();
      });

      it('shows each milestone once', () => {
        const ids = findMilestoneIds();

        expect(ids).toHaveLength(3);
        expect(new Set(ids).size).toBe(3);
      });
    });

    describe('when the milestone title filter changes back to a filter whose page failed', () => {
      beforeEach(async () => {
        groupMilestonesQueryHandler.mockImplementation((variables) => {
          if (variables.after === '1' && !variables.searchTitle) {
            return Promise.reject(new Error('Houston, we have a problem'));
          }
          return serveMilestonesPage(variables, { pageCount: 3 });
        });

        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        updateLocalSettingsInCache(apolloProvider, { filterParams: { milestoneTitle: 'Sprint' } });
        await waitForPromises();
        updateLocalSettingsInCache(apolloProvider, { filterParams: {} });
        await waitForPromises();
      });

      it('does not request the failed page again', () => {
        expect(
          groupMilestonesQueryHandler.mock.calls.filter(
            ([{ searchTitle, after }]) => !searchTitle && after === '1',
          ),
        ).toHaveLength(1);
      });

      it('creates the alert again', () => {
        expect(createAlert).toHaveBeenCalledTimes(2);
        expect(createAlert).toHaveBeenNthCalledWith(2, {
          message: 'Something went wrong while fetching milestones',
        });
      });
    });

    describe('when a loading page of another filter has the cursor of the failed page', () => {
      beforeEach(async () => {
        const heldPages = [];
        groupMilestonesQueryHandler.mockImplementation((variables) => {
          if (variables.after === '1' && !variables.searchTitle) {
            return Promise.reject(new Error('Houston, we have a problem'));
          }
          const page = serveMilestonesPage(variables, { pageCount: 3 });
          if (variables.after === '1') {
            return new Promise((resolve) => {
              heldPages.push(() => resolve(page));
            });
          }
          return page;
        });

        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        updateLocalSettingsInCache(apolloProvider, { filterParams: { milestoneTitle: 'Sprint' } });
        await waitForPromises();
        updateLocalSettingsInCache(apolloProvider, { filterParams: { milestoneTitle: 'Release' } });
        await waitForPromises();
        updateLocalSettingsInCache(apolloProvider, { filterParams: { milestoneTitle: 'Sprint' } });
        await waitForPromises();

        heldPages.forEach((release) => release());
        await waitForPromises();
      });

      it('creates the alert for the failed page only', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
      });
    });

    describe('when the query variables change after the cap and the new range loads completely', () => {
      const dismiss = jest.fn();

      beforeEach(async () => {
        createAlert.mockReturnValue({ dismiss });
        groupMilestonesQueryHandler.mockImplementation(serveMilestonesPage);

        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        groupMilestonesQueryHandler.mockResolvedValue(mockGroupMilestonesQueryResponse);
        updateLocalSettingsInCache(apolloProvider, {
          presetType: PRESET_TYPES.WEEKS,
          timeframe: mockTimeframeWeeks,
        });
        await waitForPromises();
      });

      it('dismisses the alert', () => {
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(dismiss).toHaveBeenCalledTimes(1);
      });
    });

    describe('when a setting outside the query variables changes mid-pagination', () => {
      beforeEach(async () => {
        groupMilestonesQueryHandler.mockImplementation((variables) => {
          if (variables.after === '5') {
            updateLocalSettingsInCache(apolloProvider, { bufferSize: 42 });
          }
          return serveMilestonesPage(variables);
        });

        createComponent({ isShowingMilestones: true });
        await waitForPromises();
      });

      it('keeps counting', () => {
        expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(20);
      });
    });

    describe('when a range that reached the cap is shown again', () => {
      const dismiss = jest.fn();

      beforeEach(async () => {
        createAlert.mockReturnValue({ dismiss });
        groupMilestonesQueryHandler.mockImplementation(async (variables) => {
          const response = await serveMilestonesPage(variables, { pageSize: 100 });
          response.data.group.milestones.nodes[0].startDate = '2018-12-26';
          return response;
        });

        createComponent({ isShowingMilestones: true });
        await waitForPromises();

        updateLocalSettingsInCache(apolloProvider, {
          presetType: PRESET_TYPES.WEEKS,
          timeframe: mockTimeframeWeeks,
        });
        await waitForPromises();

        updateLocalSettingsInCache(apolloProvider, {
          presetType: PRESET_TYPES.MONTHS,
          timeframe: mockTimeframeMonths,
        });
        await waitForPromises();
      });

      it('does not request more pages', () => {
        expect(groupMilestonesQueryHandler).toHaveBeenCalledTimes(40);
      });

      it('keeps the valid milestones already loaded and creates an alert', () => {
        expect(findMilestonesListSection().props('milestones')).toHaveLength(1980);
        expect(createAlert).toHaveBeenLastCalledWith({
          message: 'Maximum number of milestones loaded (2,000)',
          variant: VARIANT_WARNING,
        });
      });

      it('dismisses the alerts of the earlier ranges only', () => {
        expect(createAlert).toHaveBeenCalledTimes(3);
        expect(dismiss).toHaveBeenCalledTimes(2);
      });
    });
  });
});
