import { __, n__, sprintf } from '~/locale';

// Shared by chart display types that plot between `minDimensions` and
// `maxDimensions` dimensions against between `minMetrics` and `maxMetrics` metrics. Reaching the
// dimension maximum only leaves room for a single metric (a second dimension folds into stacked
// segments). Other display types (e.g. stat's "no dimensions, exactly one metric") have
// a different shape and validate on their own.
export const dimensionMetricValidationError = ({
  displayType,
  dimensions,
  metrics,
  minDimensions = 1,
  maxDimensions = 2,
  minMetrics = 1,
  maxMetrics = Infinity,
}) => {
  // At least one dimension is always required, whatever a caller asks for.
  const required = Math.max(minDimensions, 1);
  if (dimensions.length < required) {
    return required <= 1
      ? sprintf(__('%{displayType} requires at least one dimension'), { displayType })
      : sprintf(__('%{displayType} requires %{minDimensions} dimensions'), {
          displayType,
          minDimensions: required,
        });
  }
  if (dimensions.length > maxDimensions) {
    if (maxDimensions === 1) {
      return sprintf(__('%{displayType} supports exactly one dimension'), { displayType });
    }
    return sprintf(__('%{displayType} supports a maximum of %{maxDimensions} dimensions'), {
      displayType,
      maxDimensions,
    });
  }
  // A fixed metric count (diverging bar's two halves) gets one message for either side of it.
  if (minMetrics === maxMetrics && metrics.length !== minMetrics) {
    return sprintf(
      n__(
        '%{displayType} requires exactly %{metricCount} metric',
        '%{displayType} requires exactly %{metricCount} metrics',
        minMetrics,
      ),
      { displayType, metricCount: minMetrics },
    );
  }
  if (metrics.length === 0) {
    return sprintf(__('%{displayType} requires at least one metric'), { displayType });
  }
  if (metrics.length < minMetrics) {
    return sprintf(
      n__(
        '%{displayType} requires at least %{minMetrics} metric',
        '%{displayType} requires at least %{minMetrics} metrics',
        minMetrics,
      ),
      { displayType, minMetrics },
    );
  }
  if (metrics.length > maxMetrics) {
    return sprintf(
      n__(
        '%{displayType} supports a maximum of %{maxMetrics} metric',
        '%{displayType} supports a maximum of %{maxMetrics} metrics',
        maxMetrics,
      ),
      { displayType, maxMetrics },
    );
  }
  if (maxDimensions > 1 && dimensions.length === maxDimensions && metrics.length > 1) {
    return sprintf(
      __('%{displayType} with %{maxDimensions} dimensions supports only a single metric'),
      { displayType, maxDimensions },
    );
  }
  return null;
};
