import base from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_analytics_dashboard_duo_agent_platform_top_level_groups.query.graphql.json';
import noneQualifying from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_analytics_dashboard_duo_agent_platform_top_level_groups_none_qualifying.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getAnalyticsDashboardDuoAgentPlatformTopLevelGroups',
  variants: {
    BASE: base,
    NONE_QUALIFYING: noneQualifying,
  },
});
