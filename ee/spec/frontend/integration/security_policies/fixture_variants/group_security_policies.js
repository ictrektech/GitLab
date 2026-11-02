import base from 'test_fixtures/graphql/security_policies/integration/group_security_policies.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureErrors, setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';
import { FETCH_ERROR } from '../test_constants';

export default defineFixtureVariants({
  query: 'groupSecurityPolicies',
  variants: {
    BASE: base,
    EMPTY: setFixtureItemsCount({ fixture: base, lookupKey: 'securityPolicies', itemCount: 0 }),
    ERROR: setFixtureErrors(base, [FETCH_ERROR]),
  },
});
