import EMPTY_STATE_SVG_URL from '@gitlab/svgs/dist/illustrations/empty-state/empty-pipeline-md.svg?url';
import { GlEmptyState, GlLink, GlSprintf } from '@gitlab/ui';
import EmptyResult from '~/vue_shared/components/empty_result.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { newRunnerPath as mockNewRunnerPath } from 'jest/ci/runner/mock_data';
import RunnerListEmptyState from '~/ci/runner/components/runner_list_empty_state.vue';

describe('RunnerListEmptyState', () => {
  let wrapper;

  const findEmptySearchResult = () => wrapper.findComponent(EmptyResult);
  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findLinks = () => wrapper.findAllComponents(GlLink);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(RunnerListEmptyState, {
      propsData: props,
      stubs: {
        GlEmptyState,
        GlSprintf,
      },
    });
  };

  describe('when search is not filtered', () => {
    describe.each`
      newRunnerPath        | expectedMessage
      ${mockNewRunnerPath} | ${'Create a new runner to get started.'}
      ${null}              | ${'To register new runners, contact your administrator.'}
    `('when newRunnerPath is $newRunnerPath', ({ newRunnerPath, expectedMessage }) => {
      beforeEach(() => {
        createComponent({ props: { newRunnerPath } });
      });

      it('shows title', () => {
        expect(findEmptyState().find('h2').text()).toBe('Get started with runners');
      });

      it('renders an illustration', () => {
        expect(findEmptyState().props('svgPath')).toBe(EMPTY_STATE_SVG_URL);
      });

      it('shows the runner description and next step', () => {
        expect(findEmptyState().find('p').text()).toMatchInterpolatedText(
          `Runners are the agents that run your CI/CD jobs. ${expectedMessage}`,
        );
      });
    });

    describe('with newRunnerPath', () => {
      beforeEach(() => {
        createComponent({ props: { newRunnerPath: mockNewRunnerPath } });
      });

      it('only links to the new runner page', () => {
        expect(findLinks()).toHaveLength(1);
        expect(findLinks().at(0).attributes('href')).toBe(mockNewRunnerPath);
      });
    });

    describe('without newRunnerPath', () => {
      beforeEach(() => {
        createComponent();
      });

      it('has no link', () => {
        expect(findLinks()).toHaveLength(0);
      });
    });
  });

  describe('when search is filtered', () => {
    beforeEach(() => {
      createComponent({ props: { isSearchFiltered: true } });
    });

    it('renders an EmptyResult component instead of the empty state', () => {
      expect(findEmptySearchResult().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
    });
  });
});
