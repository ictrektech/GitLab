import { dimensionMetricValidationError } from '~/glql/utils/chart_validation';

const DIM_A = { key: 'a', label: 'A', name: 'a', type: 'dimension' };
const DIM_B = { key: 'b', label: 'B', name: 'b', type: 'dimension' };
const DIM_C = { key: 'c', label: 'C', name: 'c', type: 'dimension' };
const METRIC_X = { key: 'x', label: 'X', name: 'x', type: 'metric' };
const METRIC_Y = { key: 'y', label: 'Y', name: 'y', type: 'metric' };

describe('dimensionMetricValidationError', () => {
  it('requires at least one dimension', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'barChart',
        dimensions: [],
        metrics: [METRIC_X],
      }),
    ).toBe('barChart requires at least one dimension');
  });

  it('requires a minimum number of dimensions when one is set', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'heatMap',
        dimensions: [DIM_A],
        metrics: [METRIC_X],
        minDimensions: 2,
      }),
    ).toBe('heatMap requires 2 dimensions');
  });

  it('states the real requirement when no dimensions are given at all', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'heatMap',
        dimensions: [],
        metrics: [METRIC_X],
        minDimensions: 2,
      }),
    ).toBe('heatMap requires 2 dimensions');
  });

  it('still requires one dimension when asked for fewer', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'barChart',
        dimensions: [],
        metrics: [METRIC_X],
        minDimensions: 0,
      }),
    ).toBe('barChart requires at least one dimension');
  });

  it('accepts exactly the minimum number of dimensions', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'heatMap',
        dimensions: [DIM_A, DIM_B],
        metrics: [METRIC_X],
        minDimensions: 2,
      }),
    ).toBe(null);
  });

  it('caps dimensions at the default maximum of 2', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'columnChart',
        dimensions: [DIM_A, DIM_B, DIM_C],
        metrics: [METRIC_X],
      }),
    ).toBe('columnChart supports a maximum of 2 dimensions');
  });

  it('uses a singular message when capping dimensions at a maximum of 1', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'lineChart',
        dimensions: [DIM_A, DIM_B],
        metrics: [METRIC_X],
        maxDimensions: 1,
      }),
    ).toBe('lineChart supports exactly one dimension');
  });

  it('caps dimensions at a custom maximum', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'someChart',
        dimensions: [DIM_A, DIM_B, DIM_C],
        metrics: [METRIC_X],
        maxDimensions: 2,
      }),
    ).toBe('someChart supports a maximum of 2 dimensions');
  });

  it('requires at least one metric', () => {
    expect(
      dimensionMetricValidationError({ displayType: 'barChart', dimensions: [DIM_A], metrics: [] }),
    ).toBe('barChart requires at least one metric');
  });

  it('restricts to a single metric once the dimension maximum is reached', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'barChart',
        dimensions: [DIM_A, DIM_B],
        metrics: [METRIC_X, METRIC_Y],
      }),
    ).toBe('barChart with 2 dimensions supports only a single metric');
  });

  it('allows multiple metrics below the dimension maximum', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'barChart',
        dimensions: [DIM_A],
        metrics: [METRIC_X, METRIC_Y],
      }),
    ).toBeNull();
  });

  it('returns null for a valid combination at the dimension maximum', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'barChart',
        dimensions: [DIM_A, DIM_B],
        metrics: [METRIC_X],
      }),
    ).toBeNull();
  });

  it('does not apply the single-metric restriction when maxDimensions is 1', () => {
    expect(
      dimensionMetricValidationError({
        displayType: 'lineChart',
        dimensions: [DIM_A],
        metrics: [METRIC_X, METRIC_Y],
        maxDimensions: 1,
      }),
    ).toBeNull();
  });

  describe('with a metric range', () => {
    const METRIC_Z = { key: 'z', label: 'Z', name: 'z', type: 'metric' };
    const validate = (metrics, range) =>
      dimensionMetricValidationError({
        displayType: 'someChart',
        dimensions: [DIM_A],
        metrics,
        maxDimensions: 1,
        ...range,
      });

    it.each([[[]], [[METRIC_X]], [[METRIC_X, METRIC_Y, METRIC_Z]]])(
      'requires the exact count when the bounds match, given %j',
      (metrics) => {
        expect(validate(metrics, { minMetrics: 2, maxMetrics: 2 })).toBe(
          'someChart requires exactly 2 metrics',
        );
      },
    );

    it('uses the singular for a count of one', () => {
      expect(validate([METRIC_X, METRIC_Y], { minMetrics: 1, maxMetrics: 1 })).toBe(
        'someChart requires exactly 1 metric',
      );
    });

    it('accepts the exact count', () => {
      expect(validate([METRIC_X, METRIC_Y], { minMetrics: 2, maxMetrics: 2 })).toBeNull();
    });

    it('requires the minimum', () => {
      expect(validate([METRIC_X], { minMetrics: 2 })).toBe('someChart requires at least 2 metrics');
    });

    it('caps at the maximum', () => {
      expect(validate([METRIC_X, METRIC_Y, METRIC_Z], { maxMetrics: 2 })).toBe(
        'someChart supports a maximum of 2 metrics',
      );
    });
  });
});
