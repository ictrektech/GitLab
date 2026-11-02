import { join } from 'node:path';
import { HttpResponse } from 'msw';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
  matchFixture,
} from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_ci_catalog_resource_versions';
import './fixture_variants/get_ci_catalog_resource_shared_data';
import { LATEST_VERSION, PREVIOUS_VERSION } from './constants';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/ci/catalog/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

const sharedDataFixtureTable = [
  {
    matches: ({ version }) => version === LATEST_VERSION,
    fixture: () => fixtures.getCiCatalogResourceSharedData,
  },
  {
    matches: ({ version }) => version === PREVIOUS_VERSION,
    fixture: () => fixtures.getCiCatalogResourceSharedDataPreviousVersion,
  },
];

const readmeFixtureTable = [
  {
    matches: ({ version }) => version === LATEST_VERSION,
    fixture: () => fixtures.getCiCatalogResourceReadme,
  },
  {
    matches: ({ version }) => version === PREVIOUS_VERSION,
    fixture: () => fixtures.getCiCatalogResourceReadmePreviousVersion,
  },
];

const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  getCiCatalogResourceSharedData: ({ variables }) =>
    getActiveVariant('getCiCatalogResourceSharedData') ??
    matchFixture(variables, sharedDataFixtureTable, {
      guard: () => true,
      label: 'getCiCatalogResourceSharedData',
    }).fixture(),
  getCiCatalogResourceReadme: ({ variables }) =>
    matchFixture(variables, readmeFixtureTable, {
      guard: () => true,
      label: 'getCiCatalogResourceReadme',
    }).fixture(),
};

export function handleCiCatalogOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const ciCatalogRestEndpoints = [];
