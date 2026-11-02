<script>
import { s__ } from '~/locale';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import {
  FILTERED_SEARCH_TERM,
  OPERATORS_IS_NOT_OR,
} from '~/vue_shared/components/filtered_search_bar/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_SECURITY_ATTRIBUTE } from 'ee/graphql_shared/constants';
import { CRITICAL, HIGH, MEDIUM, LOW, INFO, UNKNOWN } from 'ee/vulnerabilities/constants';
import getSecurityCategoriesAndAttributes from 'ee/security_configuration/graphql/group_security_categories_and_attributes.query.graphql';
import { getAttributeHeaderToken } from 'ee/security_configuration/security_attributes/components/shared/attribute_utils';
import {
  ATTRIBUTE_TYPE_PREFIX,
  getAttributeCategoryTokens,
} from 'ee/security_dashboard/utils/attribute_utils';
import {
  ANALYZER_KEYS,
  SEVERITY_FILTER_OPERATOR_TO_CONST,
  STATUS_KEY,
  STATUS_FILTER_TO_VARIABLES,
} from '../constants';
import {
  hasFilterData,
  isAttributeParam,
  queryParamsToTokens,
  tokensToQueryParams,
} from '../filter_url_sync';
import { visibleToolCoverageTokens } from './tool_coverage_tokens';
import { vulnerabilityCountTokens } from './vulnerability_count_tokens';
import { statusTokens } from './status_tokens';

const SEVERITY_KEYS = [CRITICAL, HIGH, MEDIUM, LOW, INFO, UNKNOWN];

export default {
  name: 'InventoryDashboardFilteredSearchBar',
  components: {
    FilteredSearchBar,
  },
  props: {
    namespace: {
      type: String,
      required: true,
    },
    showStatusFilter: {
      type: Boolean,
      required: false,
      default: false,
    },
    urlQuery: {
      type: Object,
      required: false,
      default: () => ({}),
    },
  },
  emits: ['filter-subgroups-and-projects', 'filters-initialized', 'url-params-changed'],
  data() {
    return {
      initialSortBy: 'updated_at_desc',
      securityCategories: [],
      categoriesLoaded: false,
    };
  },
  apollo: {
    securityCategories: {
      query: getSecurityCategoriesAndAttributes,
      variables() {
        return {
          fullPath: this.namespace,
        };
      },
      update: (data) => data?.group?.securityCategories,
      result() {
        this.categoriesLoaded = true;
      },
      error() {
        this.categoriesLoaded = true;
      },
    },
  },
  computed: {
    searchTokens() {
      return [
        ...visibleToolCoverageTokens(),
        ...(this.showStatusFilter ? statusTokens : []),
        getAttributeHeaderToken(
          this.securityCategories,
          s__('SecurityAttributes|Security attributes'),
        ),
        ...getAttributeCategoryTokens(this.securityCategories).map((token) => ({
          ...token,
          operators: OPERATORS_IS_NOT_OR,
        })),
        ...vulnerabilityCountTokens,
      ];
    },
    initialFilterValue() {
      return queryParamsToTokens(this.urlQuery, this.searchTokens);
    },
    hasAttributeParams() {
      return Object.keys(this.urlQuery).some(isAttributeParam);
    },
    canRestoreFromUrl() {
      return this.categoriesLoaded || !this.hasAttributeParams;
    },
    restorableFilterValue() {
      return this.canRestoreFromUrl ? this.initialFilterValue : null;
    },
  },
  watch: {
    restorableFilterValue: { immediate: true, handler: 'emitInitializedFilters' },
  },
  methods: {
    emitInitializedFilters(filters) {
      if (!filters) return;

      this.$emit('filters-initialized', this.buildFilterParams(filters));
    },
    buildFilterParams(filters = []) {
      const filterParams = {
        vulnerabilityCountFilters: [],
        securityAnalyzerFilters: [],
        attributeFilters: [],
      };
      const plainText = [];

      filters.forEach((filter) => {
        if (!hasFilterData(filter.value.data)) return;

        if (filter.type === FILTERED_SEARCH_TERM) {
          plainText.push(filter.value.data);
        } else if (ANALYZER_KEYS.includes(filter.type)) {
          filterParams.securityAnalyzerFilters.push({
            analyzerType: filter.type,
            status: filter.value.data,
          });
        } else if (SEVERITY_KEYS.includes(filter.type)) {
          filterParams.vulnerabilityCountFilters.push({
            severity: filter.type.toUpperCase(),
            operator: SEVERITY_FILTER_OPERATOR_TO_CONST[filter.value.operator],
            count: parseInt(filter.value.data, 10) || 0,
          });
        } else if (filter.type.startsWith(ATTRIBUTE_TYPE_PREFIX)) {
          filterParams.attributeFilters.push({
            operator: filter.value.operator === '!=' ? 'IS_NOT_ONE_OF' : 'IS_ONE_OF',
            attributes: filter.value.data.map((id) =>
              convertToGraphQLId(TYPENAME_SECURITY_ATTRIBUTE, id),
            ),
          });
        } else if (filter.type === STATUS_KEY && STATUS_FILTER_TO_VARIABLES[filter.value.data]) {
          Object.assign(filterParams, STATUS_FILTER_TO_VARIABLES[filter.value.data]);
        }
      });

      if (plainText.length) {
        filterParams.search = plainText.join(' ');
      }

      return filterParams;
    },
    onFilter(filters = []) {
      this.$emit('url-params-changed', tokensToQueryParams(filters, this.searchTokens));
      this.$emit('filter-subgroups-and-projects', this.buildFilterParams(filters));
    },
  },
};
</script>

<template>
  <filtered-search-bar
    v-if="canRestoreFromUrl"
    class="gl-pr-3"
    v-bind="$attrs"
    :namespace="namespace"
    :initial-filter-value="initialFilterValue"
    :tokens="searchTokens"
    :initial-sort-by="initialSortBy"
    :search-input-placeholder="s__('SecurityInventoryFilter|Search projects…')"
    :search-text-option-label="s__('SecurityInventoryFilter|Search for project name')"
    terms-as-tokens
    sync-filter-and-sort
    @on-filter="onFilter"
  />
</template>
