import { colorFromDarkPalette, colorFromDefaultPalette } from '@gitlab/ui/src/utils/charts/theme';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import { __ } from '~/locale';
import { DONUT_OTHER_NAME } from './constants';

const byValueThenName = (a, b) => b.value - a.value || a.name.localeCompare(b.name);

const sumValues = (slices) => slices.reduce((total, { value }) => total + value, 0);

/**
 * Drops empty slices, orders the rest by value descending with a name
 * tie-break (or keeps the input order when `preserveOrder` is set), then folds
 * everything past `maxSlices` into a single "Other" slice so the parts still
 * sum to the whole.
 *
 * @param {Array<{ name: string, label?: string, value: number }>} slices
 * @param {number} maxSlices Number of individually coloured slices to keep.
 * @param {{ preserveOrder?: boolean }} options
 * @returns {Array<{ name: string, label: string, value: number }>}
 */
export const foldSlices = (slices, maxSlices, { preserveOrder = false } = {}) => {
  const kept = slices
    .filter(({ value }) => Number.isFinite(value) && value > 0)
    .map(({ name, label, value }) => ({ name, label: label || name, value }));
  const ranked = preserveOrder ? kept : kept.sort(byValueThenName);

  if (ranked.length <= maxSlices) {
    return ranked;
  }

  return [
    ...ranked.slice(0, maxSlices),
    {
      name: DONUT_OTHER_NAME,
      label: __('Other'),
      value: sumValues(ranked.slice(maxSlices)),
    },
  ];
};

/**
 * Integer percentages that add up to exactly 100 (largest remainder), so a
 * legend never reads 99% or 101%.
 *
 * @param {number[]} values
 * @returns {number[]}
 */
export const integerPercentages = (values) => {
  const total = values.reduce((sum, value) => sum + value, 0);

  if (total <= 0) {
    return values.map(() => 0);
  }

  const exact = values.map((value) => (value / total) * 100);
  const floors = exact.map(Math.floor);
  const leftover = 100 - floors.reduce((sum, value) => sum + value, 0);

  const roundedUp = new Set(
    exact
      .map((value, index) => ({ index, remainder: value - Math.floor(value) }))
      .sort((a, b) => b.remainder - a.remainder || a.index - b.index)
      .slice(0, leftover)
      .map(({ index }) => index),
  );

  return floors.map((value, index) => (roundedUp.has(index) ? value + 1 : value));
};

/**
 * Maps every slice name to a colour from the GitLab categorical data palette.
 * Explicit `sliceColors` win; the rest take palette entries in fixed order over
 * alphabetically sorted names, never by value or rank, so re-ranking the data
 * cannot repaint the chart. Only an explicit map keeps a colour when the set of
 * names itself changes, so pass `sliceColors` for any dimension with a known
 * value set.
 *
 * @param {string[]} names
 * @param {Object<string, string>} sliceColors
 * @returns {Object<string, string>}
 */
export const sliceColorMap = (names, sliceColors = {}) => {
  const paletteColor = darkModeEnabled() ? colorFromDarkPalette : colorFromDefaultPalette;
  const unmapped = names.filter((name) => !sliceColors[name]).sort((a, b) => a.localeCompare(b));

  return names.reduce(
    (colors, name) => ({
      ...colors,
      [name]: sliceColors[name] ?? paletteColor(unmapped.indexOf(name)),
    }),
    {},
  );
};
