import { activeSessionHistoryQueries } from 'jest/admin/database_diagnostics/mock_data';
import ActiveSessionHistoryQueries from './active_session_history_queries.vue';

export default {
  title: 'admin/database_diagnostics/components/active_session_history_queries',
  component: ActiveSessionHistoryQueries,
  argTypes: {
    queries: { control: false },
  },
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { ActiveSessionHistoryQueries },
  template: '<active-session-history-queries v-bind="$props" />',
});

// One query has text, one has none in pg_stat_statements, and the load pg_ash
// could not tie to a query goes last.
export const Default = Template.bind({});
Default.args = {
  queries: activeSessionHistoryQueries,
};

// Multi-line text gets no tooltip, so Show full query is the only way to read it.
export const LongQuery = Template.bind({});
LongQuery.args = {
  queries: [
    {
      ...activeSessionHistoryQueries[1],
      query_text:
        'SELECT "issues".*\nFROM "issues"\nWHERE "issues"."project_id" = $1\n  AND "issues"."state_id" = $2\nORDER BY "issues"."created_at" DESC\nLIMIT $3',
    },
  ],
};
