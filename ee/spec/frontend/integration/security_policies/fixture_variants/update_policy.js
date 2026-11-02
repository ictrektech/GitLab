import base from 'test_fixtures/graphql/security_policies/integration/update_policy.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';
import {
  ACTION_VALIDATION_ERROR_FIELD,
  SYNTHETIC_SAVE_ERROR,
  SYNTHETIC_SECONDARY_SAVE_ERROR,
  SYNTHETIC_VALIDATION_ERROR_FIELD,
} from '../test_constants';

const withSaveErrors = (fixture) =>
  setFixtureData(fixture, 'errors', [SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR]);

const withValidationErrorOn = (field) =>
  setFixtureData(withSaveErrors(base), 'validationErrors', [
    {
      field,
      message: SYNTHETIC_SAVE_ERROR,
      title: SYNTHETIC_SAVE_ERROR,
      // `action_section.vue` matches an error to an action by this index.
      index: 0,
      __typename: 'SecurityPolicyValidationError',
    },
  ]);

// The mutation reports a rejected commit through the payload's own `errors`, not the
// top-level GraphQL `errors`, so this overrides the payload.
export default defineFixtureVariants({
  query: 'updatePolicy',
  variants: {
    BASE: base,
    // Plain key rather than a `path`, so a renamed field fails loudly instead of silently.
    ERROR: withSaveErrors(base),
    // The field is the discriminator of rule mode's error branch.
    VALIDATION_ERROR: withValidationErrorOn(SYNTHETIC_VALIDATION_ERROR_FIELD),
    ACTION_VALIDATION_ERROR: withValidationErrorOn(ACTION_VALIDATION_ERROR_FIELD),
  },
});
