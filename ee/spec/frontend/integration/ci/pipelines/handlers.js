import { join } from 'node:path';
import { HttpResponse } from 'msw';
import {
  createFixturePaginator,
  loadFixturesMap,
  mapStaticOperationHandlers,
} from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/pipeline_findings';
import './fixture_variants/get_pipeline_details';
import './fixture_variants/get_pipeline_header_data';
import './fixture_variants/get_pipeline_jobs';
import './fixture_variants/get_pipeline_permissions';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/ci/pipelines/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

const paginateFindings = createFixturePaginator({ lookupKey: 'securityReportFindings' });

const OPERATION_HANDLERS = {
  ...mapStaticOperationHandlers(fixtures),
  pipelineFindings: ({ variables }) =>
    paginateFindings(getActiveVariant('pipelineFindings') ?? fixtures.pipelineFindings, variables),
};

export function handlePipelineSecurityOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

// Rails redirects job actions to an HTML page, and the graph ignores the response body.
const jobActionEndpoint = (action) => ({
  name: `restJob${action[0].toUpperCase()}${action.slice(1)}`,
  method: 'post',
  path: new RegExp(`/-/jobs/\\d+/${action}\\.json`),
  response: {},
});

export const pipelineSecurityRestEndpoints = [
  ...['retry', 'cancel', 'play', 'unschedule'].map(jobActionEndpoint),
  {
    name: 'restPipelineTestReportSummary',
    method: 'get',
    path: /\/-\/pipelines\/\d+\/tests\/summary\.json/,
    response: fixtures.testReportSummary,
  },
];
