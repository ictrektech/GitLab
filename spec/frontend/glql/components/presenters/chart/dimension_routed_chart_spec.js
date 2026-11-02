import { GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DimensionRoutedChart from '~/glql/components/presenters/chart/dimension_routed_chart.vue';

const DIM_A = { key: 'a', label: 'A', name: 'a', type: 'dimension' };
const DIM_B = { key: 'b', label: 'B', name: 'b', type: 'dimension' };
const DIM_C = { key: 'c', label: 'C', name: 'c', type: 'dimension' };
const METRIC_X = { key: 'x', label: 'X', name: 'x', type: 'metric' };
const METRIC_Y = { key: 'y', label: 'Y', name: 'y', type: 'metric' };

describe('DimensionRoutedChart', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(DimensionRoutedChart, {
      propsData: {
        displayType: 'someChart',
        fields: [DIM_A, METRIC_X],
        ...props,
      },
      scopedSlots: {
        'one-dimension': `
          <div data-testid="one-dimension">
            {{ props.dimension.label }}|{{ props.metrics.map((m) => m.label).join(',') }}|{{ props.stacked }}
            <span data-testid="page-data">{{ props.pageData.nodes.map((n) => n.a).join(',') }}</span>
            <span data-testid="one-dimension-page">{{ props.page }}</span>
          </div>`,
        'two-dimensions': `
          <div data-testid="two-dimensions">
            {{ props.dimensions.map((d) => d.label).join(',') }}|{{ props.metric.label }}
            <span data-testid="page">{{ props.page }}</span>
          </div>`,
      },
    });
  };

  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findOneDimensionSlot = () => wrapper.findByTestId('one-dimension');
  const findTwoDimensionsSlot = () => wrapper.findByTestId('two-dimensions');
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findPageCounter = () => wrapper.findByTestId('page-counter');
  const findPageData = () => wrapper.findByTestId('page-data').text();
  const findPage = () => wrapper.findByTestId('page').text();
  const findOneDimensionPage = () => wrapper.findByTestId('one-dimension-page').text();

  describe('loading state', () => {
    beforeEach(() => {
      createComponent({ loading: true });
    });

    it('renders the skeleton loader', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('does not render any slot', () => {
      expect(findOneDimensionSlot().exists()).toBe(false);
      expect(findTwoDimensionsSlot().exists()).toBe(false);
    });
  });

  describe('routing', () => {
    it('renders the one-dimension slot for 1 dimension, exposing dimension and metrics', () => {
      createComponent({ fields: [DIM_A, METRIC_X, METRIC_Y] });

      expect(findOneDimensionSlot().text()).toContain('A|X,Y|false');
      expect(findTwoDimensionsSlot().exists()).toBe(false);
    });

    it('exposes stacked to the one-dimension slot when displayConfig sets it', () => {
      createComponent({ displayConfig: { stacked: true } });

      expect(findOneDimensionSlot().text()).toContain('A|X|true');
    });

    it('renders the two-dimensions slot for 2 dimensions, exposing dimensions and the metric', () => {
      createComponent({ fields: [DIM_A, DIM_B, METRIC_X] });

      expect(findTwoDimensionsSlot().text()).toContain('A,B|X');
      expect(findOneDimensionSlot().exists()).toBe(false);
    });
  });

  describe('validation', () => {
    const findEmittedErrorMessage = () => wrapper.emitted('error')?.[0]?.[0]?.message;

    it('emits error and renders no slot when there are no dimensions', () => {
      createComponent({ fields: [METRIC_X] });

      expect(findEmittedErrorMessage()).toBe('someChart requires at least one dimension');
      expect(findOneDimensionSlot().exists()).toBe(false);
      expect(findTwoDimensionsSlot().exists()).toBe(false);
    });

    it('emits error when there are more than maxDimensions dimensions', () => {
      createComponent({ fields: [DIM_A, DIM_B, DIM_C, METRIC_X] });

      expect(findEmittedErrorMessage()).toBe('someChart supports a maximum of 2 dimensions');
    });

    it('emits the singular message when maxDimensions is 1', () => {
      createComponent({ fields: [DIM_A, DIM_B, METRIC_X], maxDimensions: 1 });

      expect(findEmittedErrorMessage()).toBe('someChart supports exactly one dimension');
      expect(findTwoDimensionsSlot().exists()).toBe(false);
    });

    it('emits error when there are no metrics', () => {
      createComponent({ fields: [DIM_A] });

      expect(findEmittedErrorMessage()).toBe('someChart requires at least one metric');
    });

    it('passes the metric bounds to validation', () => {
      createComponent({ fields: [DIM_A, METRIC_X], minMetrics: 2, maxMetrics: 2 });

      expect(findEmittedErrorMessage()).toBe('someChart requires exactly 2 metrics');
      expect(findOneDimensionSlot().exists()).toBe(false);
    });

    it('emits error when there are 2 dimensions and more than one metric', () => {
      createComponent({ fields: [DIM_A, DIM_B, METRIC_X, METRIC_Y] });

      expect(findEmittedErrorMessage()).toBe(
        'someChart with 2 dimensions supports only a single metric',
      );
    });

    it('does not emit error and renders no slot before fields are populated', () => {
      createComponent({ fields: [] });

      expect(wrapper.emitted('error')).toBeUndefined();
      expect(findOneDimensionSlot().exists()).toBe(false);
      expect(findTwoDimensionsSlot().exists()).toBe(false);
    });
  });

  describe('paging', () => {
    const ONE_DIMENSION_DATA = { nodes: ['a0', 'a1', 'a2', 'a3', 'a4'].map((a) => ({ a, x: 1 })) };
    const TWO_DIMENSIONS_DATA = {
      nodes: [
        { a: 'a0', b: 'b0', x: 1 },
        { a: 'a0', b: 'b1', x: 1 },
        { a: 'a1', b: 'b0', x: 1 },
      ],
    };

    it('shows every row and no controls without a page size', () => {
      createComponent({ data: ONE_DIMENSION_DATA });

      expect(findPageData()).toBe('a0,a1,a2,a3,a4');
      expect(findPagination().exists()).toBe(false);
      expect(findPageCounter().exists()).toBe(false);
    });

    it('pages one-dimension rows forward and back', async () => {
      createComponent({ data: ONE_DIMENSION_DATA, pageSize: 2 });

      expect(findPageData()).toBe('a0,a1');
      expect(findPageCounter().text()).toBe('Page 1 of 3');
      expect(findPagination().props()).toMatchObject({
        hasPreviousPage: false,
        hasNextPage: true,
      });

      findPagination().vm.$emit('next');
      findPagination().vm.$emit('next');
      await nextTick();

      expect(findPageData()).toBe('a4');
      expect(findPageCounter().text()).toBe('Page 3 of 3');
      expect(findPagination().props()).toMatchObject({
        hasPreviousPage: true,
        hasNextPage: false,
      });

      findPagination().vm.$emit('prev');
      await nextTick();

      expect(findPageData()).toBe('a2,a3');
    });

    // `null` and a literal 'Unknown' share a label, but they are still two rows to page through.
    it('counts one-dimension pages by row, even when rows share a label', async () => {
      createComponent({
        data: {
          nodes: [
            { a: null, x: 1 },
            { a: 'Unknown', x: 1 },
            { a: 'a2', x: 1 },
          ],
        },
        pageSize: 2,
      });

      expect(findPagination().props('hasNextPage')).toBe(true);

      findPagination().vm.$emit('next');
      await nextTick();

      expect(findPageData()).toBe('a2');
    });

    it('hands the page to the one-dimension slot too', async () => {
      createComponent({ data: ONE_DIMENSION_DATA, pageSize: 2 });

      expect(findOneDimensionPage()).toBe('0');

      findPagination().vm.$emit('next');
      await nextTick();

      expect(findOneDimensionPage()).toBe('1');
    });

    it('counts two-dimension pages by first-dimension value and hands over the page', async () => {
      createComponent({ fields: [DIM_A, DIM_B, METRIC_X], data: TWO_DIMENSIONS_DATA, pageSize: 1 });

      expect(findPage()).toBe('0');
      expect(findPagination().props('hasNextPage')).toBe(true);

      findPagination().vm.$emit('next');
      await nextTick();

      expect(findPage()).toBe('1');
      expect(findPageCounter().text()).toBe('Page 2 of 2');
      expect(findPagination().props('hasNextPage')).toBe(false);
    });

    it('renders no controls when every value fits on one page', () => {
      createComponent({ data: ONE_DIMENSION_DATA, pageSize: 5 });

      expect(findPagination().exists()).toBe(false);
      expect(findPageCounter().exists()).toBe(false);
    });

    it('renders no controls while loading', () => {
      createComponent({ data: ONE_DIMENSION_DATA, pageSize: 2, loading: true });

      expect(findPagination().exists()).toBe(false);
    });

    it('goes back to the first page when the data changes', async () => {
      createComponent({ data: ONE_DIMENSION_DATA, pageSize: 2 });

      findPagination().vm.$emit('next');
      await nextTick();
      await wrapper.setProps({ data: { nodes: [...ONE_DIMENSION_DATA.nodes] } });

      expect(findPageData()).toBe('a0,a1');
    });
  });
});
