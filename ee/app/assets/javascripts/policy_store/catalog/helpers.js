import { isEmpty, isObject } from 'lodash-es';
import {
  FIELD_TYPE_CODE,
  FIELD_TYPE_FREEZE_WINDOWS,
  FIELD_TYPE_SETTING_EXPECTATIONS,
} from '../components/editor/constants';
import { labelForValue, promisableOptions } from './settings';

/**
 * Whether a value counts as no answer. `false` and `0` are answers; an empty string, and
 * anything lodash reads as an empty object — `[]`, `{}`, an empty `Map` — are not.
 *
 * @param {*} value - Any config value.
 * @returns {boolean}
 */
export const blank = (value) => {
  if (typeof value === 'string') return value.trim() === '';
  if (isObject(value)) return isEmpty(value);

  return value === undefined || value === null;
};

/**
 * True when an expectations row names a setting and a required value. Validation, the
 * serializer and the read-only summary all share it, so "complete enough to show as
 * filled in", "complete enough to persist" and "complete enough to display" stay one
 * definition.
 *
 * @param {Object} row - One `{ setting, expected }` row.
 * @returns {boolean}
 */
export const completeExpectation = (row) => Boolean(row?.setting) && !blank(row?.expected);

/**
 * True when an expectations row holds any answer at all, complete or not. Half of a row
 * is still the author having started it, which is what separates "you left this blank"
 * from "you left this half-filled".
 *
 * @param {Object} row - One `{ setting, expected }` row.
 * @returns {boolean}
 */
export const touchedExpectation = (row) => Boolean(row?.setting) || !blank(row?.expected);

/**
 * Whether an edit counts as the author having engaged with the field. Any edit does,
 * except on an expectations field: there, adding or removing an empty row is structure
 * rather than content, and counting it would draw the control red the moment the author
 * opens a row to type into.
 *
 * @param {Object} field - The catalog field definition.
 * @param {*} value - The field's value after the edit.
 * @returns {boolean}
 */
export const edited = (field, value) =>
  field?.type !== FIELD_TYPE_SETTING_EXPECTATIONS || (value ?? []).some(touchedExpectation);

/**
 * The fields a config should render, honouring an optional
 * `showIf: { key, in: [...] }` naming a sibling and the values that reveal this field.
 * A hidden field is not rendered, validated, displayed or kept. Matching is by identity,
 * so the sibling must be scalar-valued and not itself conditional; catalog_spec rejects both.
 *
 * @param {Array} fields - A catalog entry's field definitions.
 * @param {Object} config - The entry's current config, keyed by field key.
 * @returns {Array}
 */
export const visibleFields = (fields = [], config = {}) =>
  fields.filter(({ showIf }) => !showIf || showIf.in.includes(config[showIf.key]));

/**
 * The keys `visibleFields` hides for this config. The editor drops these when a field goes
 * hidden, but a value that arrived already hidden survives until some control is touched —
 * so the serializer applies them again on the way out.
 *
 * Only add a `showIf` to a field introduced in the same release: on one with persisted
 * values the next save silently drops whatever the condition hides, so an existing field
 * needs a migration instead.
 *
 * @param {Array} fields - A catalog entry's field definitions.
 * @param {Object} config - The entry's current config, keyed by field key.
 * @returns {string[]}
 */
export const hiddenFieldKeys = (fields = [], config = {}) => {
  const shown = new Set(visibleFields(fields, config).map(({ key }) => key));

  return fields.map(({ key }) => key).filter((key) => !shown.has(key));
};

const configEntryLabel = (field, entry) => {
  if (field.type === FIELD_TYPE_SETTING_EXPECTATIONS) {
    // A half-filled row is not content yet; showing `x = null` would read as an answer.
    if (!completeExpectation(entry)) return '';

    const setting = field.settings?.[entry.setting];
    // A value the catalog no longer offers is still written the way the setting's values
    // are written: a raw `false` here would read as a bug to anyone opening a saved policy.
    const value =
      promisableOptions(setting)?.find((option) => option.id === entry.expected)?.label ??
      labelForValue(entry.expected);

    return `${setting?.name ?? entry.setting} = ${value}`;
  }

  if (field.type === FIELD_TYPE_FREEZE_WINDOWS) {
    // Not ', ': that separator already divides one window from the next, so a
    // multi-tier window would blur into the window after it.
    const tiers = (entry.tiers || [])
      .map((tier) => field.options?.find((option) => option.id === tier)?.label ?? tier)
      .join(' / ');
    const bounds = [entry.starts_at, entry.ends_at].filter(Boolean).join(' → ');

    return [entry.name, tiers, bounds].filter(Boolean).join(' · ');
  }

  return field.options?.find((option) => option.id === entry)?.label ?? String(entry);
};

const configValueFor = (field, value) => {
  const values = Array.isArray(value) ? value : [value];
  const labelled = values
    .filter((entry) => entry !== undefined && entry !== null && entry !== '')
    .map((entry) => configEntryLabel(field, entry))
    .filter(Boolean);

  return labelled.join(', ');
};

/**
 * Resolves an entry's persisted config into displayable items through the
 * catalog's field definitions, mirroring what the editor's form shows.
 */
export const configItemsFor = (entry, config = {}) =>
  visibleFields(entry.fields || [], config)
    .map((field) => ({
      key: field.key,
      label: field.label,
      code: field.type === FIELD_TYPE_CODE,
      value: configValueFor(field, config[field.key]),
    }))
    .filter(({ value }) => value !== '');

// A persisted id the catalog no longer knows still resolves to its raw id
// rather than disappearing from read-only summaries.
export const resolveCatalogEntry = (catalog, id, config = {}) => {
  const entry = catalog.find((candidate) => candidate.id === id) ?? {
    id,
    label: id,
    description: '',
    icon: 'question-o',
  };

  return { ...entry, configItems: configItemsFor(entry, config) };
};
