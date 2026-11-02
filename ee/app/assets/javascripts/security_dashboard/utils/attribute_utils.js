import { snakeCase, startCase } from 'lodash-es';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { OPERATORS_OR_NOT } from '~/vue_shared/components/filtered_search_bar/constants';
import { urlQueryToFilter } from '~/vue_shared/components/filtered_search_bar/filtered_search_utils';
import AttributeToken from 'ee/security_configuration/security_attributes/components/shared/attribute_token.vue';

// Prefixed with "attribute~" to avoid clashes with other token types.
// "~" is URL-safe and won't appear in snakeCase output.
export const ATTRIBUTE_TYPE_PREFIX = 'attribute~';

const ATTRIBUTE_TOKEN_DEFAULTS = {
  multiSelect: true,
  unique: true,
  token: AttributeToken,
  operators: OPERATORS_OR_NOT,
};

const toAttributeOption = (attribute) => ({
  ...attribute,
  id: getIdFromGraphQLId(attribute.id).toString(),
  text: attribute.name,
});

const toToken = ({ id, name, securityAttributes }) => ({
  ...ATTRIBUTE_TOKEN_DEFAULTS,
  type: `${ATTRIBUTE_TYPE_PREFIX}${snakeCase(name)}`,
  title: name,
  categoryId: id,
  attributeOptions: securityAttributes.map(toAttributeOption),
});

export const getAttributeCategoryTokens = (securityCategories = []) =>
  securityCategories.filter(({ securityAttributes }) => securityAttributes?.length).map(toToken);

// Placeholders for the attribute types in the URL, so the filter bar can read and apply them
// before the categories load. Disabled so they are not offered as new tokens.
export const getAttributeTokensFromUrl = (queryString) => {
  const params = new URLSearchParams(queryString);

  return Object.keys(urlQueryToFilter(queryString))
    .filter((type) => type.startsWith(ATTRIBUTE_TYPE_PREFIX))
    .sort()
    .map((type) => ({
      ...ATTRIBUTE_TOKEN_DEFAULTS,
      type,
      title: startCase(type.replace(ATTRIBUTE_TYPE_PREFIX, '')),
      isPlaceholder: true,
      disabled: true,
      // Chart links need the known ID-to-category mapping before the option labels load.
      attributeOptions: (params.get(type) ?? params.get(`not[${type}]`) ?? '')
        .split(',')
        .filter(Boolean)
        .map((id) => ({ id })),
    }));
};
