import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/ci/pipeline_triggers/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

// The rows come from the page's `data-triggers` attribute (see `test_setup.js`); the edit
// modal's mutation is the list's only network request.
const OPERATION_HANDLERS = {
  updatePipelineTrigger: () => fixtures.updatePipelineTrigger,
};

export function handlePipelineTriggersOperation({ operationName }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler());
}

export const pipelineTriggersRestEndpoints = [];
