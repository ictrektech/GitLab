import { snakeCase } from 'lodash-es';
import {
  filterToQueryObject,
  urlQueryToFilter,
} from '~/vue_shared/components/filtered_search_bar/filtered_search_utils';
import {
  FILTERED_SEARCH_TERM,
  OPERATOR_OR,
  OPERATOR_GREATER_THAN_OR_EQUAL,
  OPERATOR_LESS_THAN_OR_EQUAL,
} from '~/vue_shared/components/filtered_search_bar/constants';
import { ATTRIBUTE_TYPE_PREFIX } from 'ee/security_dashboard/utils/attribute_utils';

const PARAM_SEARCH = 'search';

const PARAM_PREFIX_NOT = 'not[';
const PARAM_PREFIX_OR = 'or[';
const OPERATOR_PARAM_PREFIXES = [PARAM_PREFIX_NOT, PARAM_PREFIX_OR];

const withoutOperatorPrefix = (key) => {
  const prefix = OPERATOR_PARAM_PREFIXES.find((candidate) => key.startsWith(candidate));

  return prefix ? key.slice(prefix.length) : key;
};

export const isAttributeParam = (key) =>
  withoutOperatorPrefix(key).startsWith(ATTRIBUTE_TYPE_PREFIX);

const PARAM_CHARACTERS_SAFE_TO_DECODE = {
  '%7E': '~',
  '%2C': ',',
  '%5B': '[',
  '%5D': ']',
};

export const withReadableParams = (url) => {
  const parsed = new URL(url);

  parsed.search = parsed.search.replace(
    /%7E|%2C|%5B|%5D/gi,
    (encoded) => PARAM_CHARACTERS_SAFE_TO_DECODE[encoded.toUpperCase()],
  );

  return parsed.href;
};

const isFilterToken = ({ operators }) => Boolean(operators?.length);

const isCountDefinition = ({ attributeOptions, options }) => !attributeOptions && !options;

const paramKeyFor = ({ type }) => (type.startsWith(ATTRIBUTE_TYPE_PREFIX) ? type : snakeCase(type));

const customOperatorsFor = (definitions) =>
  definitions.flatMap((definition) => {
    const applyOnlyToKey = paramKeyFor(definition);

    if (definition.attributeOptions) {
      return [{ operator: OPERATOR_OR, prefix: 'or', applyOnlyToKey }];
    }

    if (isCountDefinition(definition)) {
      return [
        { operator: OPERATOR_GREATER_THAN_OR_EQUAL, prefix: 'gte', applyOnlyToKey },
        { operator: OPERATOR_LESS_THAN_OR_EQUAL, prefix: 'lte', applyOnlyToKey },
      ];
    }

    return [];
  });

const normalizedCount = (value) =>
  /^\d+$/.test(String(value)) ? String(parseInt(value, 10)) : undefined;

const attributeIdsFormat = ({ attributeOptions }) => {
  const allowed = attributeOptions.map(({ id }) => String(id));
  const permitted = (values) => values.map(String).filter((id) => allowed.includes(id));

  return {
    toParam: (data) => {
      const ids = permitted([].concat(data));

      return ids.length ? ids.join(',') : undefined;
    },
    fromParam: (param) => {
      const ids = permitted(param.split(',').filter(Boolean));

      return ids.length ? ids : undefined;
    },
  };
};

const optionValueFormat = ({ options }) => ({
  toParam: (data) => String(data).toLowerCase(),
  fromParam: (param) =>
    options
      .map(({ value }) => String(value))
      .find((value) => value.toLowerCase() === param.toLowerCase()),
});

const operatorPrefixedCountFormat = () => ({
  toParam: normalizedCount,
  fromParam: normalizedCount,
});

const urlFormatFor = (definition) => {
  if (definition.attributeOptions) return attributeIdsFormat(definition);
  if (definition.options) return optionValueFormat(definition);

  return operatorPrefixedCountFormat();
};

export const hasFilterData = (data) =>
  Array.isArray(data) ? data.length > 0 : data !== undefined && data !== null && data !== '';

export const tokensToQueryParams = (filterTokens = [], tokenDefinitions = []) => {
  const definitions = tokenDefinitions.filter(isFilterToken);
  const filters = Object.fromEntries(definitions.map((it) => [paramKeyFor(it), null]));
  const searchTerms = [];

  filterTokens.forEach(({ type, value }) => {
    if (type === FILTERED_SEARCH_TERM) {
      if (value?.data) searchTerms.push({ value: value.data });
      return;
    }

    const definition = definitions.find((candidate) => candidate.type === type);
    if (!definition || !hasFilterData(value?.data)) return;

    const param = urlFormatFor(definition).toParam(value.data);
    if (param === undefined) return;

    filters[paramKeyFor(definition)] = { value: param, operator: value.operator };
  });

  if (searchTerms.length) {
    filters[FILTERED_SEARCH_TERM] = searchTerms;
  }

  return {
    [PARAM_SEARCH]: null,
    ...filterToQueryObject(filters, {
      filteredSearchTermKey: PARAM_SEARCH,
      customOperators: customOperatorsFor(definitions),
    }),
  };
};

export const queryParamsToTokens = (query = {}, tokenDefinitions = []) => {
  const definitions = tokenDefinitions.filter(isFilterToken);
  const filters = urlQueryToFilter(query, {
    filteredSearchTermKey: PARAM_SEARCH,
    customOperators: customOperatorsFor(definitions),
  });

  const tokens = [];

  definitions.forEach((definition) => {
    const filter = filters[paramKeyFor(definition)];
    const { value, operator } = (Array.isArray(filter) ? filter[0] : filter) ?? {};
    if (typeof value !== 'string' || !value) return;

    const data = urlFormatFor(definition).fromParam(value);
    if (data === undefined) return;

    tokens.push({ type: definition.type, value: { data, operator } });
  });

  const [searchTerm] = filters[FILTERED_SEARCH_TERM] ?? [];
  if (searchTerm?.value) {
    tokens.push({ type: FILTERED_SEARCH_TERM, value: { data: searchTerm.value } });
  }

  return tokens;
};
