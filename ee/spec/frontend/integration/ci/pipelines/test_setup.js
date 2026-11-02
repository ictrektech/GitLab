import Vue from 'vue';
import VueRouter from 'vue-router';
import testReportSummary from 'test_fixtures/graphql/ci/pipelines/integration/test_report_summary.json';
import {
  assignRouter,
  findButtonByText,
  registerBootstrappedApp,
  screen,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { createAppOptions } from 'ee/ci/pipeline_details/pipeline_tabs';
import { routes } from 'ee/ci/pipeline_details/routes';
import { createPipelineHeaderApp } from '~/ci/pipeline_details/pipeline_header';
import { apolloProvider } from '~/ci/pipeline_details/pipeline_shared_client';

const PROJECT_FULL_PATH = 'frontend-fixtures/project';
const PIPELINE_IID = '1';
const PIPELINE_PATH = `/${PROJECT_FULL_PATH}/-/pipelines/${PIPELINE_IID}`;
const GRAPHQL_RESOURCE_ETAG = `/api/graphql:pipelines/id/${PIPELINE_IID}`;

const DATASET = {
  blobPath: `/${PROJECT_FULL_PATH}/-/blob/master`,
  exposeSecurityDashboard: 'true',
  failedJobsCount: '1',
  graphqlResourceEtag: GRAPHQL_RESOURCE_ETAG,
  pipelineIid: PIPELINE_IID,
  pipelinePath: PIPELINE_PATH,
  pipelineProjectPath: PROJECT_FULL_PATH,
  projectPath: PROJECT_FULL_PATH,
  sbomReportsErrors: '[]',
  suiteEndpoint: `${PIPELINE_PATH}/tests/:suite_name.json`,
  summaryEndpoint: `${PIPELINE_PATH}/tests/summary.json`,
  testsCount: String(testReportSummary.total.count),
  // Matches the jobs recorded by ee/spec/frontend/fixtures/pipeline_details_integration.rb
  totalJobCount: '7',
  vulnerabilityReportData: JSON.stringify({
    project_full_path: PROJECT_FULL_PATH,
    pipeline_id: PIPELINE_IID,
    pipeline_iid: PIPELINE_IID,
    can_admin_vulnerability: 'true',
    can_view_false_positive: 'false',
    has_vulnerabilities: 'true',
  }),
};

const HEADER_DATASET = {
  fullPath: PROJECT_FULL_PATH,
  pipelineIid: PIPELINE_IID,
  pipelinesPath: `/${PROJECT_FULL_PATH}/-/pipelines`,
};

const mountPipelineTabs = (route) => {
  const router = assignRouter(
    () => new VueRouter({ mode: 'history', base: PIPELINE_PATH, routes }),
    { routerLocation: `${PIPELINE_PATH}${route}` },
  );

  return registerBootstrappedApp(
    new Vue(createAppOptions('#js-pipeline-tabs', apolloProvider, router)),
  );
};

export function mountPipelineSecurityTab() {
  const el = document.createElement('div');
  el.id = 'js-pipeline-tabs';
  Object.assign(el.dataset, DATASET);
  document.body.appendChild(el);

  return mountPipelineTabs('/security');
}

export function mountPipelineDetails({ route = '/' } = {}) {
  document.querySelector('[data-testid="pipeline-details-page"]')?.remove();

  // PanelActionsPortal renders the header actions (retry, cancel, delete) only when the app
  // root sits inside a `.js-paneled-view` that contains the portal target.
  const page = document.createElement('div');
  page.className = 'js-paneled-view';
  page.dataset.testid = 'pipeline-details-page';
  page.innerHTML = `<div class="js-panel-actions-portal-target"></div>
    <div id="js-pipeline-header"></div>
    <div id="js-pipeline-tabs"></div>`;
  Object.assign(page.querySelector('#js-pipeline-header').dataset, HEADER_DATASET);
  Object.assign(page.querySelector('#js-pipeline-tabs').dataset, DATASET);
  document.body.appendChild(page);

  registerBootstrappedApp(
    createPipelineHeaderApp('#js-pipeline-header', apolloProvider, GRAPHQL_RESOURCE_ETAG),
  );

  return mountPipelineTabs(route);
}

export const findPageDescription = () => screen.queryByTestId('page-description');

export const findFindings = () => [...screen.queryAllByTestId('vulnerability')];

export const findNextButton = () => findButtonByText('Next');

export const findHeader = () => screen.queryByTestId('pipeline-header');

export const findHeaderStatus = () => {
  const header = findHeader();
  return header ? within(header).queryByTestId('ci-icon') : null;
};

export const findHeaderBadge = (name) => screen.queryByTestId(`badges-${name}`);

export const findRetryPipelineButton = () => screen.queryByTestId('retry-pipeline');

export const findCancelPipelineButton = () => screen.queryByTestId('cancel-pipeline');

export const findDeletePipelineButton = () => screen.queryByTestId('delete-pipeline');

export const findGraph = () => document.querySelector('.js-pipeline-graph');

export const findGraphJob = (name) => document.getElementById(`ci-badge-${name}`);

export const findGraphJobAction = (name) =>
  findGraphJob(name)?.querySelector('[data-testid="ci-action-button"]') ?? null;

export const findLinkedPipeline = () => screen.queryByTestId('linked-pipeline-container');

export const findLinkedPipelineButton = (label) => {
  const linkedPipeline = findLinkedPipeline();
  return linkedPipeline ? linkedPipeline.querySelector(`button[aria-label="${label}"]`) : null;
};

export const findTabPanel = (name) => screen.queryByTestId(`${name}-tab`);

// The tab test IDs sit on the panels, so reach the nav link through `aria-labelledby`.
export const findTabLink = (name) => {
  const panel = findTabPanel(name);
  return panel ? document.getElementById(panel.getAttribute('aria-labelledby')) : null;
};

export const findJobsTableRow = (jobName) =>
  screen.queryAllByTestId('jobs-table-row').find((row) => row.textContent.includes(jobName)) ??
  null;
