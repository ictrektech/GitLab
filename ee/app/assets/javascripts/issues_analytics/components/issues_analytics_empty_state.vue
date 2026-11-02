<script>
import { GlEmptyState } from '@gitlab/ui';
import { s__ } from '~/locale';
import searchProjectsQuery from '~/vue_shared/components/new_resource_dropdown/graphql/search_projects.query.graphql';
import NewResourceDropdown from '~/vue_shared/components/new_resource_dropdown/new_resource_dropdown.vue';
import EmptyState from '~/work_items/list/components/empty_state.vue';
import { NO_DATA_EMPTY_STATE_TYPE, NO_DATA_WITH_FILTERS_EMPTY_STATE_TYPE } from '../constants';

export default {
  searchProjectsQuery,
  name: 'IssuesAnalyticsEmptyState',
  components: {
    GlEmptyState,
    EmptyState,
    NewResourceDropdown,
  },
  inject: ['showNewIssueDropdown', 'filtersEmptyStateSvgPath', 'fullPath', 'groupId'],
  props: {
    emptyStateType: {
      type: String,
      required: true,
      validator: (type) =>
        [NO_DATA_EMPTY_STATE_TYPE, NO_DATA_WITH_FILTERS_EMPTY_STATE_TYPE].includes(type),
    },
  },
  i18n: {
    title: s__('IssuesAnalytics|Sorry, your filter produced no results'),
    description: s__(
      'IssuesAnalytics|To widen your search, change or remove filters in the filter bar above.',
    ),
  },
  computed: {
    hasNoDataWithFilters() {
      return this.emptyStateType === NO_DATA_WITH_FILTERS_EMPTY_STATE_TYPE;
    },
    newIssueDropdownQueryVariables() {
      return {
        fullPath: this.fullPath,
      };
    },
  },
  methods: {
    extractProjects(data) {
      return data?.group?.projects?.nodes;
    },
  },
};
</script>

<template>
  <gl-empty-state
    v-if="hasNoDataWithFilters"
    :title="$options.i18n.title"
    :description="$options.i18n.description"
    :svg-path="filtersEmptyStateSvgPath"
    :svg-height="150"
  />
  <empty-state v-else>
    <template #new-issue-button>
      <new-resource-dropdown
        v-if="showNewIssueDropdown"
        class="gl-self-center"
        :query="$options.searchProjectsQuery"
        :query-variables="newIssueDropdownQueryVariables"
        :extract-projects="extractProjects"
        :group-id="groupId"
      />
    </template>
  </empty-state>
</template>
