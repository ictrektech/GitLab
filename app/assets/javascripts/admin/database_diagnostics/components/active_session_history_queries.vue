<script>
import { GlButton, GlTableLite, GlTruncate } from '@gitlab/ui';
import { s__ } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import {
  activeSessionHistoryNumberFields,
  formatActiveSessions,
  formatShareOfLoad,
} from '../utils';

// Keyboard users cannot reach the tooltip, so every query can expand in place. A
// tooltip for longer or multi-line text would cover the table, so those get none.
const TOOLTIP_TEXT_LIMIT = 200;

export default {
  name: 'ActiveSessionHistoryQueries',
  components: { ClipboardButton, GlButton, GlTableLite, GlTruncate },
  props: {
    queries: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {
      expandedQueryIds: [],
    };
  },
  computed: {
    // Load that pg_ash could not tie to a query is a remainder, so it goes last
    // whatever its size.
    sortedQueries() {
      return [
        ...this.queries.filter(({ query_id: queryId }) => queryId !== null),
        ...this.queries.filter(({ query_id: queryId }) => queryId === null),
      ];
    },
  },
  methods: {
    formatActiveSessions,
    formatShareOfLoad,
    isLongQuery({ query_text: queryText }) {
      return queryText.length > TOOLTIP_TEXT_LIMIT || queryText.includes('\n');
    },
    isExpanded({ query_id: queryId }) {
      return this.expandedQueryIds.includes(queryId);
    },
    toggleQueryText({ query_id: queryId }) {
      this.expandedQueryIds = this.expandedQueryIds.includes(queryId)
        ? this.expandedQueryIds.filter((id) => id !== queryId)
        : [...this.expandedQueryIds, queryId];
    },
  },
  fields: [
    { key: 'query', label: s__('DatabaseDiagnostics|Query') },
    ...activeSessionHistoryNumberFields(),
  ],
};
</script>

<template>
  <gl-table-lite :items="sortedQueries" :fields="$options.fields" fixed stacked="md">
    <template #table-colgroup="{ fields: columns }">
      <col v-for="column in columns" :key="column.key" :class="column.columnClass" />
    </template>

    <template #cell(query)="{ item }">
      <span v-if="item.query_id === null" class="gl-text-subtle" data-testid="unattributed">
        {{ s__('DatabaseDiagnostics|Not attributed to a query') }}
      </span>
      <template v-else>
        <span
          v-if="item.query_text && isExpanded(item)"
          class="gl-whitespace-pre-wrap gl-break-words gl-font-monospace"
          data-testid="query-text"
          >{{ item.query_text }}</span
        >
        <gl-truncate
          v-else-if="item.query_text"
          :text="item.query_text"
          :with-tooltip="!isLongQuery(item)"
          class="gl-font-monospace"
          data-testid="query-text"
        />
        <span v-else class="gl-text-subtle">
          {{ s__('DatabaseDiagnostics|Query text not available') }}
        </span>
        <div
          class="gl-flex gl-flex-wrap gl-items-center gl-gap-x-3 gl-text-sm gl-text-subtle"
          data-testid="query-id"
        >
          <span>{{
            sprintf(s__('DatabaseDiagnostics|Query ID: %{queryId}'), { queryId: item.query_id })
          }}</span>
          <template v-if="item.query_text">
            <gl-button
              variant="link"
              size="small"
              :aria-expanded="String(isExpanded(item))"
              data-testid="toggle-query-text"
              @click="toggleQueryText(item)"
            >
              {{
                isExpanded(item)
                  ? s__('DatabaseDiagnostics|Hide full query')
                  : s__('DatabaseDiagnostics|Show full query')
              }}
            </gl-button>
            <clipboard-button
              :text="item.query_text"
              :title="s__('DatabaseDiagnostics|Copy query')"
              category="tertiary"
              size="small"
            />
          </template>
        </div>
      </template>
    </template>

    <template #cell(pct)="{ item }">{{ formatShareOfLoad(item.pct) }}</template>
    <template #cell(avg_aas)="{ item }">{{ formatActiveSessions(item.avg_aas) }}</template>
    <template #cell(peak_aas)="{ item }">{{ formatActiveSessions(item.peak_aas) }}</template>
  </gl-table-lite>
</template>
