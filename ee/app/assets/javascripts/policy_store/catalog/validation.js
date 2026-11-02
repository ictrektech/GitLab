import { isEqual } from 'lodash-es';
import { sprintf, s__ } from '~/locale';
import { toNounSeriesText } from '~/lib/utils/grammar';
import { FIELD_TYPE_SETTING_EXPECTATIONS } from '../components/editor/constants';
import { blank, completeExpectation, touchedExpectation, visibleFields } from './helpers';
import { promisableOptions } from './settings';

/**
 * The first meaningful statement of a program, with `#` comments stripped —
 * the same reading the store's transpiler applies to Rego. Shared with the
 * catalog guard specs so "first statement" has a single definition.
 *
 * @param {string} value - The program source.
 * @returns {string|undefined}
 */
export const firstStatement = (value) =>
  String(value ?? '')
    .split('\n')
    .map((line) => line.replace(/#.*/, '').trim())
    .find(Boolean);

const fieldLabel = (entry, key) =>
  (entry.fields ?? []).find((field) => field.key === key)?.label ?? key;

const visibleKeys = (entry, config, keys) => {
  const shown = new Set(visibleFields(entry.fields ?? [], config).map((field) => field.key));

  return keys.filter((key) => shown.has(key));
};

// sprintf must not escape: the sentences render through `{{ }}`, so escaping
// here would show entities for translated labels like "Noms d'environnement".
const requiredMessage = (entry, field) =>
  sprintf(
    s__('PolicyStore|%{rule} is missing %{field}.'),
    { rule: entry.label, field: field.label },
    false,
  );

const firstStatementMessage = (entry, field) =>
  sprintf(
    s__('PolicyStore|%{field} in %{rule} must open with %{statement}.'),
    { rule: entry.label, field: field.label, statement: field.firstStatement },
    false,
  );

const oneOfMessage = (entry, keys) =>
  sprintf(
    s__('PolicyStore|%{rule} needs at least one of: %{fields}.'),
    {
      rule: entry.label,
      fields: toNounSeriesText(
        keys.map((key) => fieldLabel(entry, key)),
        { onlyCommas: true },
      ),
    },
    false,
  );

const settingLabel = (field, setting) => field.settings?.[setting]?.name ?? setting;

// Naming the setting matters most on a boolean, where an unanswered row and a row answered
// `false` look identical on screen.
const incompleteExpectationMessage = (entry, field, row) =>
  row.setting
    ? sprintf(
        s__('PolicyStore|%{rule}: %{setting} needs a required value.'),
        { rule: entry.label, setting: settingLabel(field, row.setting) },
        false,
      )
    : sprintf(
        s__('PolicyStore|%{rule}: every selected setting needs a required value.'),
        { rule: entry.label },
        false,
      );

const unknownSettingMessage = (entry, setting) =>
  sprintf(
    s__('PolicyStore|%{rule}: %{setting} is not a setting a policy can govern.'),
    { rule: entry.label, setting },
    false,
  );

const unpromisableExpectationMessage = (entry, field, row) =>
  sprintf(
    s__('PolicyStore|%{rule}: %{setting} is set to a value a policy cannot require.'),
    { rule: entry.label, setting: settingLabel(field, row.setting) },
    false,
  );

const duplicateExpectationMessage = (entry, field, setting) =>
  sprintf(
    s__('PolicyStore|%{rule}: %{setting} is pinned more than once.'),
    { rule: entry.label, setting: settingLabel(field, setting) },
    false,
  );

const expectationBlockers = (entry, field, value) => {
  const rows = Array.isArray(value) ? value : [];

  // One complaint per field per save, like every other field type: the checks below run in
  // the order an author can act on them, rather than reporting every row at once.
  //
  // A half-filled row gets the more precise complaint. "is missing Project settings" on a
  // form the author already started would point them at the wrong fix.
  const incomplete = rows.find((row) => touchedExpectation(row) && !completeExpectation(row));

  if (incomplete) return [incompleteExpectationMessage(entry, field, incomplete)];

  const complete = rows.filter(completeExpectation);

  if (!complete.length) {
    return field.required ? [requiredMessage(entry, field)] : [];
  }

  // A policy written through the API, or one the catalog has narrowed since it was saved,
  // can hold a setting or a value the catalog does not offer. The value control shows no
  // answer in that case, so without a blocker the author would re-save a rule the
  // transpiler refuses with nothing on screen to act on.
  const unknown = complete.find((row) => !field.settings?.[row.setting]);

  if (unknown) return [unknownSettingMessage(entry, unknown.setting)];

  // A setting whose type enumerates nothing offers no options, so no value can be promised.
  // Compared by value, not identity: the control selects an option by its JSON encoding, so
  // identity here would block a non-scalar value the author can see selected on screen.
  const unpromisable = complete.find(
    (row) =>
      !(promisableOptions(field.settings[row.setting]) ?? []).some(({ id }) =>
        isEqual(id, row.expected),
      ),
  );

  if (unpromisable) return [unpromisableExpectationMessage(entry, field, unpromisable)];

  // Each row persists as its own rule, so the same setting twice is a policy that cannot
  // be satisfied rather than a redundant one.
  const settings = complete.map(({ setting }) => setting);
  const duplicate = settings.find((setting, index) => settings.indexOf(setting) !== index);

  if (duplicate) return [duplicateExpectationMessage(entry, field, duplicate)];

  return [];
};

// One reachable alternative is not a choice: "needs at least one of: Names" reads as a
// list of one, and repeats what the required check already said when that field is also
// required. Fall back to the plain missing-field sentence, or to nothing.
const oneOfBlockers = (entry, keys) => {
  if (keys.length > 1) return [oneOfMessage(entry, keys)];

  const field = (entry.fields ?? []).find(({ key }) => key === keys[0]);

  return field && !field.required ? [requiredMessage(entry, field)] : [];
};

// Each blocker names the field it came from, so the same sentence can be read twice: once
// in the save button's list of what is missing, once under the control that caused it.
const fieldBlockers = (entry, config) =>
  visibleFields(entry.fields ?? [], config).flatMap((field) => {
    const value = config[field.key];

    if (field.type === FIELD_TYPE_SETTING_EXPECTATIONS) {
      return expectationBlockers(entry, field, value).map((message) => ({
        key: field.key,
        message,
      }));
    }

    if (field.required && blank(value)) {
      return [{ key: field.key, message: requiredMessage(entry, field) }];
    }

    if (field.firstStatement && !blank(value) && firstStatement(value) !== field.firstStatement) {
      return [{ key: field.key, message: firstStatementMessage(entry, field) }];
    }

    return [];
  });

/**
 * Save blockers for an action whose configuration lives in a rule rather than
 * in its own fields, declared as `requiresRule` on the action entry. The field
 * checks below cannot see across building blocks, so a policy holding such an
 * action without its rule would otherwise pass as complete while naming none of
 * what the action is supposed to write.
 *
 * @param {Object} catalogs - `{ actions, rules }`, the latter only for the rule's label.
 * @param {string[]} actionIds - The selected action ids.
 * @param {string[]} ruleIds - The selected rule ids.
 * @returns {string[]}
 */
export const actionRuleBlockers = ({ actions = [], rules = [] }, actionIds, ruleIds) =>
  actionIds.flatMap((id) => {
    const entry = actions.find((candidate) => candidate.id === id);
    const required = entry?.requiresRule;

    if (!required || ruleIds.includes(required)) return [];

    const rule = rules.find((candidate) => candidate.id === required);

    return [
      sprintf(
        s__('PolicyStore|%{action} needs the %{rule} rule to supply its configuration.'),
        { action: entry.label, rule: rule?.label ?? required },
        false,
      ),
    ];
  });

/**
 * Save blockers for the selected rules: human sentences naming what the
 * catalog declares as needed but the config does not satisfy. Declarations:
 * `required: true` on a field, `firstStatement` on a code field, and an
 * entry-level `requireOneOf` key set. The store refuses these shapes, so the
 * wizard blocks the submit instead of sending a known failure. A rule the
 * catalog does not know produces no blockers.
 *
 * @param {Array} catalog - RULES-shaped catalog entries.
 * @param {string[]} ruleIds - The selected rule ids.
 * @param {Object} ruleConfigs - Config objects keyed by rule id.
 * @returns {string[]}
 */
export const ruleConfigBlockers = (catalog, ruleIds, ruleConfigs = {}) =>
  ruleIds.flatMap((id) => {
    const entry = catalog.find((candidate) => candidate.id === id);

    if (!entry) return [];

    const config = ruleConfigs[id] ?? {};
    const blockers = fieldBlockers(entry, config).map(({ message }) => message);
    // Only the reachable keys: a requireOneOf naming fields the current config
    // hides would otherwise demand an answer with no control to give it.
    const reachable = visibleKeys(entry, config, entry.requireOneOf ?? []);

    if (reachable.length && reachable.every((key) => blank(config[key]))) {
      blockers.push(...oneOfBlockers(entry, reachable));
    }

    return blockers;
  });

/**
 * The same field-level blockers as `ruleConfigBlockers`, keyed by entry and field so a
 * control can render the one sentence that is about it. `requireOneOf` violations are
 * deliberately absent: they name a set of fields, so no single control owns them, and
 * they stay in the save button's list only. The consequence is that `environment`, whose
 * only blocker is a `requireOneOf`, gets no inline feedback at all — the save button
 * blocks on a sentence with nowhere to land. That is a known gap, not a bug here.
 *
 * @param {Array} catalog - Catalog entries, any kind.
 * @param {string[]} ids - The selected entry ids.
 * @param {Object} configs - Config objects keyed by entry id.
 * @returns {Object} `{ [entryId]: { [fieldKey]: message } }`, entries without blockers omitted.
 */
export const entryFieldBlockers = (catalog, ids, configs = {}) =>
  ids.reduce((acc, id) => {
    const entry = catalog.find((candidate) => candidate.id === id);
    const blockers = entry ? fieldBlockers(entry, configs[id] ?? {}) : [];

    if (!blockers.length) return acc;

    return {
      ...acc,
      [id]: Object.fromEntries(blockers.map(({ key, message }) => [key, message])),
    };
  }, {});
