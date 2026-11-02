import { http, HttpResponse } from 'msw';
import setWindowLocation from 'helpers/set_window_location_helper';
import { initJobDetails } from '~/ci/job_details/index';
import { server } from 'ee_jest/integration/server';
import {
  getText,
  registerBootstrappedApp,
  screen,
  setInputValue,
  waitAndClick,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { setAbilities, setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { JOB_LOG_PATH } from './handlers';
import restJobVariants from './fixture_variants/rest_job';
import restStageVariants from './fixture_variants/rest_stage';
import getJobVariants from './fixture_variants/get_job';
import getJobInputsVariants from './fixture_variants/get_job_inputs';
import playJobWithInputsVariants from './fixture_variants/play_job_with_inputs';

const job = restJobVariants.BASE;
const PROJECT_PATH = 'frontend-fixtures/job-details-project';
const JOB_PATH = job.build_path;

export const PIPELINE_TEST_REPORT_URL = `${job.pipeline.path}/test_report`;
export const TEST_REPORT_SUMMARY_URL = `${JOB_PATH}/test_report_summary.json`;

const DATASET = {
  jobEndpoint: `${JOB_PATH}.json`,
  logEndpoint: `${JOB_PATH}/trace.json`,
  testReportSummaryUrl: '',
  pagePath: JOB_PATH,
  projectPath: PROJECT_PATH,
  artifactHelpUrl: '/help/user/gitlab_com/_index.md#cicd',
  deploymentHelpUrl: '/help/user/project/clusters/deploy_to_cluster.md#troubleshooting',
  runnerSettingsUrl: `/${PROJECT_PATH}/-/runners#js-runners-settings`,
  retryOutdatedJobDocsUrl: '/help/ci/pipelines/settings.md#prevent-outdated-deployment-jobs',
  pipelineTestReportUrl: PIPELINE_TEST_REPORT_URL,
  logViewerPath: `${JOB_PATH}/viewer`,
  canSetPipelineVariables: 'true',
};

export function mountJobDetails({ testReportSummaryUrl = '' } = {}) {
  document.querySelector('[data-testid="job-details-page"]')?.remove();
  setWindowLocation(JOB_PATH);
  // Part of the `Troubleshoot` button, it requires an ability to be setup and read
  setAbilities({ troubleshootJobWithAi: false });

  // PanelActionsPortal renders the header actions (erase, retry, cancel) only when the app
  // root sits inside a `.js-paneled-view` that contains the portal target.
  const page = document.createElement('div');
  page.className = 'js-paneled-view';
  page.dataset.testid = 'job-details-page';
  page.innerHTML = '<div class="js-panel-actions-portal-target"></div><div id="js-job-page"></div>';
  Object.assign(page.querySelector('#js-job-page').dataset, DATASET, { testReportSummaryUrl });
  document.body.appendChild(page);

  return registerBootstrappedApp(initJobDetails());
}

// Simulate Rails behavior
// Jobs with no logs return 204
export const useNoTraceResponse = () => {
  server.use(http.get(JOB_LOG_PATH, () => new HttpResponse(null, { status: 204 })));
};

export const useErasedJob = () => setQueryVariant(restJobVariants).erased();
export const useJobWithoutTrace = () => setQueryVariant(restJobVariants).noTrace();
export const useParallelJob = () => setQueryVariant(restJobVariants).parallel();
export const useFailedJob = () => setQueryVariant(restJobVariants).failed();
export const useFailedStage = () => setQueryVariant(restStageVariants).failed();
export const useRetriedFailedStage = () => setQueryVariant(restStageVariants).failedRetried();
export const useManualJob = () => {
  setQueryVariant(restJobVariants).manual();
  setQueryVariant(getJobVariants).manual();
};
export const usePlayJobError = () => setQueryVariant(playJobWithInputsVariants).withError();
// Every response must describe the same build: the queries share `project.job(id:)` in the
// cache, so a mismatched ID repoints it and the other query refetches.
export const useManualJobWithInputs = () => {
  setQueryVariant(restJobVariants).manualWithInputs();
  setQueryVariant(getJobVariants).manualWithInputs();
  setQueryVariant(getJobInputsVariants).withInputs();
};

export const findJobName = () => screen.queryByTestId('job-name');

export const findJobLog = () => screen.queryByTestId('job-log-content');

export const findLogLine = () => document.querySelector('.js-log-line');

export const findEraseButton = () => screen.queryByTestId('job-log-erase-link');

export const findErasedBlock = () => screen.queryByTestId('job-erased-block');

export const findEmptyState = () => document.querySelector('.gl-empty-state');

export const findJobSidebar = () => screen.queryByTestId('job-sidebar');

export const findTestSummaryLink = () => {
  const row = screen.queryByTestId('test-summary');

  return row ? within(row).queryByTestId('job-sidebar-value-link') : null;
};

export const findStageJobLinks = () =>
  Array.from(document.querySelectorAll('.builds-container .build-job > a'));

const findSearchInput = () =>
  screen.queryByTestId('job-log-search-box')?.querySelector('input') ?? null;

const findSearchButton = () => screen.queryByTestId('search-button');

export const searchJobLog = async (term) => {
  setInputValue(findSearchInput(), term);
  await waitAndClick(findSearchButton);
};

export const findRunJobButton = () => screen.queryByTestId('run-manual-job-btn');

export const findErrorAlert = () => screen.queryByTestId('alert-danger');

// ByText rather than ByRole: the toggle renders after `getJob` resolves, so this gets polled.
export const findVariablesToggle = () => screen.queryByText('Variables')?.closest('button') ?? null;

export const findInputRow = (name) =>
  screen.queryAllByTestId('input-row').find((row) => getText(row).includes(name)) ?? null;

export const setVariable = ({ key, value }) => {
  const [row] = screen.queryAllByTestId('ci-variable-row');

  setInputValue(within(row).queryByTestId('ci-variable-key'), key);
  setInputValue(within(row).queryByTestId('ci-variable-value'), value);
};

export const setInputRowValue = (name, value) => {
  setInputValue(findInputRow(name).querySelector('input[type="text"]'), value);
};
