import { isEqual, sortBy } from 'lodash-es';
import { STATUS_OPEN } from '~/issues/constants';
import {
  FILTERED_SEARCH_TERM,
  OPERATOR_IS,
  TOKEN_TYPE_STATE,
} from '~/vue_shared/components/filtered_search_bar/constants';

// Pure comparisons that decide whether the current view diverges from a
// baseline (a saved view's stored config, or the All-items defaults). The
// caller resolves which baseline applies, so these stay route-agnostic.

export const ALL_ITEMS_DEFAULT_FILTER_TOKENS = Object.freeze([
  Object.freeze({
    type: TOKEN_TYPE_STATE,
    value: Object.freeze({
      data: STATUS_OPEN,
      operator: OPERATOR_IS,
    }),
  }),
]);

const normalizeToken = ({ id, ...token }) => {
  const value = { ...token.value };
  if (token.type === FILTERED_SEARCH_TERM) {
    // Normalize the search-term operator so a present-but-undefined
    // operator compares equal to an absent one.
    value.operator = undefined;
  }
  if (Array.isArray(value.data)) {
    value.data = [...value.data].sort();
  }
  return { ...token, value };
};

// Neither token order nor multi-select value order is significant: the filter bar keeps the
// user's order while the server returns its own, so compare both sides as sorted sets.
const normalizeTokens = (tokens) =>
  sortBy(
    tokens
      .filter((token) => (token.type === FILTERED_SEARCH_TERM ? Boolean(token.value?.data) : true))
      .map(normalizeToken),
    (token) => JSON.stringify([token.type, token.value.operator, token.value.data]),
  );

export const filtersChanged = ({ filterTokens, baselineTokens }) =>
  !isEqual(normalizeTokens(filterTokens), normalizeTokens(baselineTokens));

export const sortChanged = ({ sortKey, baselineSortKey }) => sortKey !== baselineSortKey;

export const viewModeChanged = ({ viewMode, baselineViewMode }) => viewMode !== baselineViewMode;

// The display-preference fields that count towards a view diverging from its
// baseline. Selecting them here keeps the comparison robust to any extra keys
// (e.g. viewMode) present on the raw namespace preferences passed in.
const pickTrackedPreferences = (preferences) => ({
  hiddenMetadataKeys: preferences?.hiddenMetadataKeys ?? [],
  collapsedGroups: preferences?.collapsedGroups ?? [],
  visibleGroups: preferences?.visibleGroups ?? null,
  groupOrder: preferences?.groupOrder ?? [],
  showEmptyGroups: preferences?.showEmptyGroups ?? true,
  groupSort: preferences?.groupSort ?? null,
});

export const preferencesChanged = ({ currentPreferences, baselinePreferences }) =>
  !isEqual(pickTrackedPreferences(currentPreferences), pickTrackedPreferences(baselinePreferences));
