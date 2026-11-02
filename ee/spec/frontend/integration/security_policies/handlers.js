import { join } from 'node:path';
import { HttpResponse } from 'msw';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
} from 'ee_jest/integration/core/fixture_utils';
import policySchema from '../../../../app/validators/json_schemas/security_orchestration_policy.json';
import './fixture_variants/project_security_policies';
import './fixture_variants/group_security_policies';
import './fixture_variants/update_policy';
import './fixture_variants/get_file';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/security_policies/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  // The DAST profile queries name their operations in PascalCase, which the camelCased
  // keys `loadFixturesMap` derives from the fixture filenames cannot reach.
  DastSiteProfiles: () => fixtures.dastSiteProfiles,
  DastScannerProfiles: () => fixtures.dastScannerProfiles,
};

export function handleSecurityPolicyOperation({ operationName }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler());
}

// YAML mode asks for the policy schema to drive validation and autocomplete.
// `getSinglePolicySchema` swallows a failed fetch, so without this the editor silently
// loses both rather than failing a spec. Served from the file the controller renders, so
// a spec asserting on the schema cannot drift from what the backend actually sends.
export const securityPolicyRestEndpoints = [
  {
    method: 'get',
    path: /\/-\/security\/policies\/schema$/,
    name: 'securityPolicySchema',
    response: policySchema,
  },
];
