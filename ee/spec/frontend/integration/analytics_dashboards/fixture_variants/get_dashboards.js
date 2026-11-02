import base from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_dashboards.query.graphql.json';
import featureFlagDisabled from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_dashboards_feature_flag_disabled.query.graphql.json';
import notInGroup from 'test_fixtures/graphql/explore/analytics_dashboards/integration/get_dashboards_not_in_group.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getDashboards',
  variants: {
    BASE: base,
    FEATURE_FLAG_DISABLED: featureFlagDisabled,
    NOT_IN_GROUP: notInGroup,
  },
});
