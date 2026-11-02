<script>
import { defineComponent } from 'vue';
import { GlAlert, GlButton, GlEmptyState } from '@gitlab/ui';
import { formatNumber, n__, sprintf } from '~/locale';
import QueryResultsTable from 'ee/orbit/components/query_results_table.vue';
import { downloadCsv } from 'ee/orbit/utils/csv_export';

export default defineComponent({
  name: 'QueryResults',
  components: { GlAlert, GlButton, GlEmptyState, QueryResultsTable },
  props: {
    rows: {
      type: Array,
      required: true,
    },
    durationMs: {
      type: Number,
      required: true,
    },
    hasMoreRows: {
      type: Boolean,
      required: true,
    },
    canAskDuo: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['ask-duo-why', 'check-schema'],
  computed: {
    hasRows() {
      return this.rows.length > 0;
    },
    summary() {
      return sprintf(
        n__('Orbit|%{count} row · %{ms} ms', 'Orbit|%{count} rows · %{ms} ms', this.rows.length),
        {
          count: formatNumber(this.rows.length),
          ms: formatNumber(this.durationMs),
        },
      );
    },
  },
  methods: {
    exportCsv() {
      downloadCsv(this.rows);
    },
  },
});
</script>

<template>
  <section class="gl-flex gl-flex-col gl-gap-3" data-testid="query-results">
    <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
      <div class="gl-flex gl-items-baseline gl-gap-3">
        <h2 class="gl-heading-4 gl-mb-0">{{ s__('Orbit|Results') }}</h2>
        <span class="gl-text-sm gl-text-subtle" data-testid="query-results-summary">
          {{ summary }}
        </span>
      </div>
      <gl-button v-if="hasRows" size="small" icon="export" @click="exportCsv">
        {{ s__('Orbit|Export CSV') }}
      </gl-button>
    </div>

    <template v-if="hasRows">
      <gl-alert
        v-if="hasMoreRows"
        variant="info"
        :dismissible="false"
        data-testid="query-row-limit"
      >
        {{
          s__(
            'Orbit|More rows match this query. Raise the LIMIT, or use SKIP to get the next page.',
          )
        }}
      </gl-alert>
      <query-results-table :rows="rows" />
    </template>

    <gl-empty-state
      v-else
      compact
      :title="s__('Orbit|No rows match this query')"
      :description="s__('Orbit|The query ran. Nothing in the data you can see matches it.')"
    >
      <template #actions>
        <gl-button v-if="canAskDuo" icon="tanuki-ai" @click="$emit('ask-duo-why')">
          {{ s__('Orbit|Ask GitLab Duo why') }}
        </gl-button>
        <gl-button category="tertiary" icon="book" @click="$emit('check-schema')">
          {{ s__('Orbit|Check the schema') }}
        </gl-button>
      </template>
    </gl-empty-state>
  </section>
</template>
