import { createAppOptions } from '~/ci/pipeline_editor/options';
import { fullMount, getText } from 'ee_jest/integration/helpers/test_helpers';

export const PROJECT_FULL_PATH = 'frontend-fixtures/project';

const DATASET = {
  ciConfigPath: '.gitlab-ci.yml',
  ciExamplesHelpPagePath: '/help/ci/examples',
  ciHelpPagePath: '/help/ci',
  ciLintPath: '/-/ci/lint',
  ciTroubleshootingPath: '/help/ci/troubleshooting',
  defaultBranch: 'main',
  identityVerificationPath: '/identity_verification',
  identityVerificationRequired: 'false',
  includesHelpPagePath: '/help/ci/includes',
  needsHelpPagePath: '/help/ci/needs',
  newMergeRequestPath: '/-/merge_requests/new',
  newPipelinePath: '/-/pipelines/new',
  pipelineEtag: 'pipeline-etag',
  projectFullPath: PROJECT_FULL_PATH,
  simulatePipelineHelpPagePath: '/help/ci/simulate',
  totalBranches: '5',
  usesExternalConfig: 'false',
  ymlHelpPagePath: '/help/ci/yaml',
};

export function mountPipelineEditor({ branch = 'main' } = {}) {
  const el = document.createElement('div');
  Object.assign(el.dataset, DATASET, { initialBranchName: branch });

  const { component, apolloProvider, provide } = createAppOptions(el);
  const wrapper = fullMount(component, { apolloProvider, provide });

  return { apolloProvider, wrapper };
}

export const findTab = (name) =>
  [...document.querySelectorAll('[role="tab"], a')].find((element) => getText(element) === name) ??
  null;

export const findTabPanel = (testId) => document.querySelector(`[data-testid="${testId}"]`);

export const findValidationMessage = () =>
  document.querySelector('[data-testid="validation-message"]');

export const findSourceEditor = () =>
  document.querySelector('[data-testid="source-editor-container"]');
