// EE re-exports the FOSS dashboards constants and overrides the
// `DATA_TABLE_METRICS` registry with the union that includes pipeline
// analytics and AI impact metrics.
//
// `export *` followed by a named re-export of the same symbol is the
// idiomatic way to shadow a single export from a wildcard re-export, but
// the `import/export` lint rule doesn't model that semantic.
/* eslint-disable import-x/export */
export * from '~/explore/analytics_dashboards/metrics/constants';
export { DATA_TABLE_METRICS } from './ai_impact/constants';
/* eslint-enable import-x/export */

export const AI_IMPACT_TABLE_TRACKING_PROPERTY = 'ai_impact_table';
export const VSD_COMPARISON_TABLE_TRACKING_PROPERTY = 'vsd_comparison_table';
