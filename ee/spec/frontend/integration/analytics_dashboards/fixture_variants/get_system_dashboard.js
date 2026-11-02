import base from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_system_dashboard.query.graphql.json';
import featureFlagDisabled from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_system_dashboard_feature_flag_disabled.query.graphql.json';
import inGroup from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_system_dashboard_in_group.query.graphql.json';
import notInGroup from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_system_dashboard_not_in_group.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureErrors } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getSystemDashboard',
  variants: {
    BASE: base,
    FEATURE_FLAG_DISABLED: featureFlagDisabled,
    IN_GROUP: inGroup,
    NOT_IN_GROUP: notInGroup,
    ERROR: setFixtureErrors(base, ['Internal server error']),
  },
});
