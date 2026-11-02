import { uniqueId } from 'lodash-es';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
  RULE_TYPE_PACKAGE_VERSION,
  DEFAULT_RISK_SEVERITY_THRESHOLD,
} from './constants';

export const buildEmptyRule = () => ({ id: uniqueId('rule_'), type: '' });

export const buildDefaultRuleForType = (type) => {
  const id = uniqueId('rule_');

  switch (type) {
    case RULE_TYPE_LICENSE:
      return { id, type: RULE_TYPE_LICENSE, denied: [] };
    case RULE_TYPE_MALICIOUS:
      return { id, type: RULE_TYPE_MALICIOUS, denied: [{ is_malicious: true }] };
    case RULE_TYPE_RISK_SEVERITY:
      // No severity yet: the row opens on the "Select" placeholder, as in the design.
      return {
        id,
        type: RULE_TYPE_RISK_SEVERITY,
        denied: [{ threshold: DEFAULT_RISK_SEVERITY_THRESHOLD }],
      };
    case RULE_TYPE_PACKAGE_VERSION:
      return { id, type: RULE_TYPE_PACKAGE_VERSION, denied: [{ name: '', version: '' }] };
    default:
      return buildEmptyRule();
  }
};

export const isValidReferenceLink = (value) => /^https?:\/\/[^\r\n]+$/.test(value);

export const getRuleListKey = (rule) => (Array.isArray(rule.allowed) ? 'allowed' : 'denied');

export const getRuleList = (rule) => rule[getRuleListKey(rule)] || [];

export const toggleRuleListKey = (rule, newKey) => {
  const { denied, allowed, ...rest } = rule;
  const list = denied || allowed || [];

  return { ...rest, [newKey]: list };
};

export const namesToItems = (names = []) => names.map((name) => ({ name }));

export const itemsToNames = (items = []) => items.map(({ name }) => name);

export const EXCEPTION_KEY_PURL = 'purl';
export const EXCEPTION_KEY_ID = 'id';

export const exceptionsToLines = (exceptions = []) =>
  exceptions.map((exception) => exception.purl || exception.id).filter(Boolean);

// Which key an entry gets is decided by the field it was typed into, never guessed from
// the text: a half-typed PURL ("pk") would otherwise be filed as a vulnerability id and
// survive as a stray entry the packages field cannot clear.
export const linesToExceptions = (lines, key) => lines.map((line) => ({ [key]: line }));

export const ruleWithExceptions = (rule, exceptions = []) => {
  const updatedRule = { ...rule };

  if (exceptions.length) {
    updatedRule.exceptions = exceptions;
  } else {
    delete updatedRule.exceptions;
  }

  return updatedRule;
};

// For a rule whose UI has a single exceptions field of one kind (purl-only or id-only):
// replaces only the entries of that kind, leaving entries under the other key (e.g.
// hand-edited YAML) untouched rather than dropping or relabelling them.
export const ruleWithExceptionsForKey = (rule, lines, key) => {
  const preserved = (rule.exceptions || []).filter((exception) => !(key in exception));

  return ruleWithExceptions(rule, [...preserved, ...linesToExceptions(lines, key)]);
};
