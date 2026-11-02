import { isPlainObject } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import { baseFieldKeyOf } from '../../../utils/chart_data';

// Matched on alias or base key, as `hiddenMetrics` is.
const isFieldNamed = (field, name) => field.key === name || baseFieldKeyOf(field) === name;

const isPercentage = (value) => Number.isFinite(value) && value >= 1 && value <= 100;

/** The width `columnWidths` gives a field, as a percentage of the table, or null. */
export const columnWidthOf = (columnWidths, field) => {
  if (!isPlainObject(columnWidths)) return null;

  const name = Object.keys(columnWidths).find((key) => isFieldNamed(field, key));
  return name === undefined ? null : columnWidths[name];
};

/** The block error for a `columnWidths` value that is not a map of the query's columns. */
export const columnWidthsError = (columnWidths, fields) => {
  if (columnWidths == null) return null;
  if (!isPlainObject(columnWidths) || !Object.values(columnWidths).every(isPercentage)) {
    return s__('Glql|`columnWidths` must map column names to percentages between 1 and 100.');
  }

  const unknown = Object.keys(columnWidths).find(
    (name) => !fields.some((field) => isFieldNamed(field, name)),
  );
  if (unknown === undefined) return null;

  return sprintf(s__('Glql|Unknown column for `columnWidths`: `%{column}`.'), { column: unknown });
};
