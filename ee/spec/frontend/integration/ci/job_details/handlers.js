import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_job';
import './fixture_variants/get_job_inputs';
import './fixture_variants/play_job_with_inputs';
import restJobVariants from './fixture_variants/rest_job';
import restStageVariants from './fixture_variants/rest_stage';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/ci/job_details/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const JOB_LOG_PATH = /\/-\/jobs\/\d+\/trace\.json/;

const OPERATION_HANDLERS = {
  getJob: () => getActiveVariant('getJob') ?? fixtures.getJob,
  getJobInputs: () => getActiveVariant('getJobInputs') ?? fixtures.getJobInputs,
  playJobWithInputs: () => getActiveVariant('playJobWithInputs') ?? fixtures.playJobWithInputs,
};

export function handleJobDetailsOperation({ operationName }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler());
}

export const jobDetailsRestEndpoints = [
  {
    name: 'restJob',
    method: 'get',
    path: /\/-\/jobs\/\d+\.json/,
    variants: restJobVariants,
  },
  {
    name: 'restJobLog',
    method: 'get',
    path: JOB_LOG_PATH,
    response: fixtures.trace,
  },
  {
    name: 'restTestReportSummary',
    method: 'get',
    path: /\/-\/jobs\/\d+\/test_report_summary\.json/,
    response: fixtures.testReportSummary,
  },
  {
    name: 'restStage',
    method: 'get',
    path: /\/-\/pipelines\/\d+\/stage\.json/,
    variants: restStageVariants,
  },
];
