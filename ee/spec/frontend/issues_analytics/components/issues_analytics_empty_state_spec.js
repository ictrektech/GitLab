import { GlEmptyState } from '@gitlab/ui';
import IssuesAnalyticsEmptyState from 'ee/issues_analytics/components/issues_analytics_empty_state.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import searchProjectsQuery from '~/vue_shared/components/new_resource_dropdown/graphql/search_projects.query.graphql';
import NewResourceDropdown from '~/vue_shared/components/new_resource_dropdown/new_resource_dropdown.vue';
import EmptyState from '~/work_items/list/components/empty_state.vue';

describe('IssuesAnalyticsEmptyState', () => {
  let wrapper;

  const svgHeight = 150;
  const mockNoDataWithFiltersSvgPath = 'no-data-with-filters.svg';
  const mockNoDataWithFiltersEmptyState = {
    title: 'Sorry, your filter produced no results',
    description: 'To widen your search, change or remove filters in the filter bar above.',
    svgPath: mockNoDataWithFiltersSvgPath,
    svgHeight,
  };
  const mockFullPath = 'gitlab-org/gitlab';
  const mockGroupId = '1';
  const defaultProvide = {
    showNewIssueDropdown: true,
    filtersEmptyStateSvgPath: mockNoDataWithFiltersSvgPath,
    fullPath: mockFullPath,
    groupId: mockGroupId,
  };

  const createComponent = ({ props = {}, provide = defaultProvide } = {}) => {
    wrapper = shallowMountExtended(IssuesAnalyticsEmptyState, {
      propsData: {
        ...props,
      },
      provide,
    });
  };

  const findGlEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findEmptyState = () => wrapper.findComponent(EmptyState);
  const findNewResourceDropdown = () => wrapper.findComponent(NewResourceDropdown);

  describe('No data with filters', () => {
    beforeEach(() => {
      createComponent({ props: { emptyStateType: 'noDataWithFilters' } });
    });

    it('should render the correct empty state type', () => {
      expect(findGlEmptyState().props()).toMatchObject(mockNoDataWithFiltersEmptyState);
    });

    it('should not render the EmptyState component', () => {
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('No data', () => {
    beforeEach(() => {
      createComponent({ props: { emptyStateType: 'noData' } });
    });

    it('should render the empty state without any issues', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('should not render the generic empty state component', () => {
      expect(findGlEmptyState().exists()).toBe(false);
    });

    it('renders the new resource dropdown with the correct props', () => {
      expect(findNewResourceDropdown().props()).toMatchObject({
        query: searchProjectsQuery,
        queryVariables: { fullPath: mockFullPath },
        groupId: mockGroupId,
      });
    });

    describe('when showNewIssueDropdown is false', () => {
      beforeEach(() => {
        createComponent({
          props: { emptyStateType: 'noData' },
          provide: { ...defaultProvide, showNewIssueDropdown: false },
        });
      });

      it('does not render the new resource dropdown', () => {
        expect(findNewResourceDropdown().exists()).toBe(false);
      });
    });
  });
});
