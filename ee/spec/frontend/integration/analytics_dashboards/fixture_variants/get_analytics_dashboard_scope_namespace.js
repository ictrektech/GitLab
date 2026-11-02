import base from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_analytics_dashboard_scope_namespace.query.graphql.json';
import noAnalyticsPermission from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_analytics_dashboard_scope_namespace_no_analytics_permission.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getAnalyticsDashboardScopeNamespace',
  variants: {
    BASE: base,
    NO_ANALYTICS_PERMISSION: noAnalyticsPermission,
  },
});
