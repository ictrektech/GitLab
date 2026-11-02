<script>
import { createAlert } from '~/alert';
import { MINIMUM_SEARCH_LENGTH } from '~/graphql_shared/constants';
import { s__, sprintf } from '~/locale';
import { DEBOUNCE_DELAY } from '~/vue_shared/components/filtered_search_bar/constants';
import GranularNamespaceSelector from '~/vue_shared/access_tokens/components/granular_namespace_selector.vue';
import groupHierarchySearchQuery from '../graphql/group_hierarchy_search.query.graphql';

export default {
  name: 'GroupHierarchyNamespaceSelector',
  components: {
    GranularNamespaceSelector,
  },
  props: {
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
    groupFullPath: {
      type: String,
      required: true,
    },
    groupName: {
      type: String,
      required: true,
    },
    error: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
  apollo: {
    hierarchy: {
      query: groupHierarchySearchQuery,
      variables() {
        return {
          fullPath: this.groupFullPath,
          search: this.searchTerm,
        };
      },
      skip() {
        const { length } = this.searchTerm;
        return length > 0 && length < MINIMUM_SEARCH_LENGTH;
      },
      update(data) {
        const group = data?.group;

        if (!group) {
          return { groups: [], projects: [] };
        }

        const { descendantGroups, projects, ...root } = group;

        // The owning group is a valid boundary too, but is not among its own descendants
        return {
          groups: [...(this.matchesSearch(root) ? [root] : []), ...(descendantGroups?.nodes || [])],
          projects: projects?.nodes || [],
        };
      },
      error(error) {
        createAlert({
          message: this.$options.i18n.fetchError,
          captureError: true,
          error,
        });
      },
      debounce: DEBOUNCE_DELAY,
    },
  },
  data() {
    return {
      hierarchy: { groups: [], projects: [] },
      searchTerm: '',
    };
  },
  computed: {
    isLoading() {
      return Boolean(this.$apollo.queries.hierarchy.loading);
    },
    title() {
      return sprintf(this.$options.i18n.title, { group: this.groupName });
    },
  },
  methods: {
    matchesSearch({ name, fullPath }) {
      const term = this.searchTerm.trim().toLowerCase();

      return !term || `${name} ${fullPath}`.toLowerCase().includes(term);
    },
  },
  i18n: {
    title: s__('OAuthApplication|Groups and projects in %{group}'),
    fetchError: s__('OAuthApplication|Error loading groups and projects. Please refresh page.'),
  },
};
</script>

<template>
  <granular-namespace-selector
    :value="value"
    :groups="hierarchy.groups"
    :projects="hierarchy.projects"
    :is-loading="isLoading"
    :error="error"
    :title="title"
    @input="$emit('input', $event)"
    @search="searchTerm = $event"
  />
</template>
