<script>
import { GlButton, GlButtonGroup, GlFilteredSearchToken, GlTooltipDirective } from '@gitlab/ui';
import { isEqual, isNil, omitBy } from 'lodash-es';
import { __, s__ } from '~/locale';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import {
  FILTERED_SEARCH_TERM,
  OPERATORS_IS,
} from '~/vue_shared/components/filtered_search_bar/constants';
import {
  prepareTokens,
  processFilters,
} from '~/vue_shared/components/filtered_search_bar/filtered_search_utils';
import {
  EVENT_TYPE_OPTIONS,
  KIND_EVENT,
  KIND_SCHEDULED,
  LAST_RUN_OPTIONS,
  SORT_OPTIONS,
  STATUS_OFF,
  STATUS_ON,
} from '../constants';

const filtersToTokens = ({ status, event, last_run: lastRun, search }) =>
  prepareTokens({
    status: status && { value: status, operator: '=' },
    event: event && { value: event, operator: '=' },
    'last-run': lastRun && { value: lastRun, operator: '=' },
    [FILTERED_SEARCH_TERM]: search && { value: search },
  });

const tokensToFilters = (tokens) => {
  const {
    status: [status] = [],
    event: [event] = [],
    'last-run': [lastRun] = [],
    [FILTERED_SEARCH_TERM]: searchTerms = [],
  } = processFilters(tokens);

  const search = searchTerms
    .map(({ value }) => value)
    .join(' ')
    .trim();

  return {
    status: status?.value,
    event: event?.value,
    last_run: lastRun?.value,
    search: search || undefined,
  };
};

export default {
  name: 'AutomationsFilteredSearch',
  components: {
    FilteredSearchBar,
    GlButton,
    GlButtonGroup,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    kind: {
      type: String,
      required: true,
    },
    filters: {
      type: Object,
      required: true,
    },
    sort: {
      type: String,
      required: true,
    },
  },
  computed: {
    initialFilterValue() {
      return filtersToTokens(this.filters);
    },
    tokens() {
      return this.kind === KIND_EVENT
        ? [this.$options.statusToken, this.$options.eventToken, this.$options.lastRunToken]
        : [this.$options.statusToken, this.$options.lastRunToken];
    },
  },
  methods: {
    updateRouteQuery(changes) {
      const query = omitBy({ ...this.$route.query, ...changes }, isNil);

      if (!isEqual(query, this.$route.query)) {
        this.$router.push({ query });
      }
    },
    selectKind(kind) {
      if (kind === this.kind) return;

      this.updateRouteQuery({ kind, event: null });
    },
    handleFilter(tokens) {
      this.updateRouteQuery(tokensToFilters(tokens));
    },
    handleSort(sort) {
      this.updateRouteQuery({ sort });
    },
  },
  statusToken: {
    type: 'status',
    title: __('Status'),
    icon: 'power',
    token: GlFilteredSearchToken,
    operators: OPERATORS_IS,
    unique: true,
    options: [
      { value: STATUS_ON, title: __('On') },
      { value: STATUS_OFF, title: __('Off') },
    ],
  },
  eventToken: {
    type: 'event',
    title: s__('DuoAgentsPlatform|Event'),
    icon: 'trigger-source',
    token: GlFilteredSearchToken,
    operators: OPERATORS_IS,
    unique: true,
    options: EVENT_TYPE_OPTIONS.map(({ value, text }) => ({ value, title: text })),
  },
  lastRunToken: {
    type: 'last-run',
    title: s__('DuoAgentsPlatform|Last run'),
    icon: 'status',
    token: GlFilteredSearchToken,
    operators: OPERATORS_IS,
    unique: true,
    options: LAST_RUN_OPTIONS.map(({ value, title }) => ({ value, title })),
  },
  SORT_OPTIONS,
  kindOptions: [
    { value: KIND_SCHEDULED, text: s__('DuoAgentsPlatform|Scheduled (beta)'), icon: 'clock' },
    { value: KIND_EVENT, text: s__('DuoAgentsPlatform|Event based'), icon: 'trigger-source' },
  ],
};
</script>

<template>
  <div
    class="gl-border-b gl-top-2 gl-z-3 gl-flex gl-items-center gl-gap-3 gl-bg-default gl-py-3 @md/panel:gl-sticky"
  >
    <gl-button-group class="gl-shrink-0">
      <gl-button
        v-for="option in $options.kindOptions"
        :key="option.value"
        v-gl-tooltip
        :title="option.text"
        :aria-label="option.text"
        :aria-pressed="String(kind === option.value)"
        :selected="kind === option.value"
        :icon="option.icon"
        :data-testid="`kind-${option.value}`"
        @click="selectKind(option.value)"
      />
    </gl-button-group>
    <filtered-search-bar
      namespace="duo-agents-platform-automations"
      :tokens="tokens"
      :search-input-placeholder="s__('DuoAgentsPlatform|Search automations')"
      :sort-options="$options.SORT_OPTIONS"
      :initial-filter-value="initialFilterValue"
      :initial-sort-by="sort"
      sync-filter-and-sort
      terms-as-tokens
      class="gl-min-w-0 gl-grow gl-p-0"
      @on-filter="handleFilter"
      @on-sort="handleSort"
    />
  </div>
</template>
