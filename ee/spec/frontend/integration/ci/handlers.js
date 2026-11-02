import { join } from 'node:path';
import { HttpResponse } from 'msw';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
  matchFixture,
} from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/ci/pipeline_editor/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

const blobContentFixtureTable = [
  { matches: ({ ref }) => !ref, fixture: () => fixtures.getBlobContentMain },
  { matches: ({ ref }) => ref === 'main', fixture: () => fixtures.getBlobContentMain },
  { matches: ({ ref }) => ref === 'test', fixture: () => fixtures.getBlobContentValid },
  { matches: ({ ref }) => ref === 'despair', fixture: () => fixtures.getBlobContentInvalid },
  { matches: ({ ref }) => ref === 'empty', fixture: () => fixtures.getBlobContentEmpty },
];

const ciLintFixtureTable = [
  {
    matches: ({ ref, dryRun }) => ref === 'test' && !dryRun,
    fixture: () => fixtures.ciLintValid,
  },
  {
    matches: ({ ref, dryRun }) => ref === 'despair' && !dryRun,
    fixture: () => fixtures.ciLintInvalid,
  },
  {
    matches: ({ ref, dryRun }) => ref === 'main' && !dryRun,
    fixture: () => fixtures.ciLintMain,
  },
  {
    matches: ({ ref, dryRun }) => ref === 'empty' && !dryRun,
    fixture: () => fixtures.ciLintTemplate,
  },
  {
    matches: ({ ref, dryRun }) => ref === 'test' && dryRun,
    fixture: () => fixtures.ciLintValidDryRun,
  },
  {
    matches: ({ ref, dryRun }) => ref === 'despair' && dryRun,
    fixture: () => fixtures.ciLintInvalidDryRun,
  },
];

const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  getBlobContent: ({ variables }) =>
    matchFixture(variables, blobContentFixtureTable, {
      guard: () => true,
      label: 'getBlobContent',
    }).fixture(),
  CiLint: ({ variables }) =>
    matchFixture(variables, ciLintFixtureTable, {
      guard: () => true,
      label: 'CiLint',
    }).fixture(),
};

export function handlePipelineEditorOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const pipelineEditorRestEndpoints = [];
