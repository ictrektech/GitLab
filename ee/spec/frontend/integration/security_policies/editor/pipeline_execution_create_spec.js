import getGroupProjects from 'test_fixtures/graphql/security_policies/integration/get_group_projects.query.graphql.json';
import { ignoreConsoleMessages } from 'helpers/console_watcher';
import { lastRequestVariables, snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import { PIPELINE_EXECUTION_POLICY_TYPE } from 'ee/security_orchestration/components/constants';
import { DEFAULT_MR_TITLE } from 'ee/security_orchestration/components/policy_editor/constants';
import {
  getText,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import getFile from '../fixture_variants/get_file';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import {
  expectNoMergeRequestOpened,
  mountPolicyEditor,
  NAMESPACE_PATHS,
  POLICY_PROJECT_BRANCH,
  POLICY_PROJECT_PATH,
} from '../test_setup';

const POLICY_NAME = 'Run custom pipeline jobs';
const CI_FILE_PATH = '.gitlab-ci.yml';

const MISSING_FILE_PATH = 'no-such-pipeline.yml';

// The one project the fixture offers, so the clicked option and the composed YAML agree.
const [CI_PROJECT] = getGroupProjects.data.group.projects.nodes;

// Spelled out rather than derived from the default template, which would make every
// assertion below true by construction.
const composedYaml = ({ name = '', include }) =>
  // js-yaml renders an empty name as a quoted empty string.
  `name: ${name || "''"}
description: ''
enabled: true
pipeline_config_strategy: inject_policy
content:
  include:
${include}skip_ci:
  allowed: false
variables_override:
  allowed: false
  exceptions: []
type: pipeline_execution_policy
`;

const TEMPLATE_INCLUDE = `    - project: ''
`;

const CHOSEN_FILE_INCLUDE = `    - project: ${CI_PROJECT.fullPath}
      file: ${CI_FILE_PATH}
`;

const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findNameInput = () => document.querySelector('[data-testid="policy-name-text"]');
const findActionSection = () => document.querySelector('[data-testid="disabled-action"]');
const findProjectToggle = () =>
  findActionSection()?.querySelector(
    '[data-testid="pipeline-execution-project-dropdown"] button',
  ) ?? null;
const findProjectOption = () =>
  document.querySelector(`[data-testid="listbox-item-${CI_PROJECT.id}"]`);
const findFilePathInput = () => document.querySelector('#file-path');
const findFilePathValidationError = () =>
  document.querySelector('[data-testid="ci-file-path-text"] .invalid-feedback');
// The message and the invalid state are separate computed properties, so assert both.
const isFilePathMarkedInvalid = () => findFilePathInput()?.getAttribute('aria-invalid') === 'true';

const selectCiProject = async () => {
  await waitAndClick(findProjectToggle);
  await waitAndClick(findProjectOption);
};

describe('Creating a pipeline execution policy', () => {
  const fullPath = NAMESPACE_PATHS[NAMESPACE_TYPES.PROJECT];

  const mountCreatePage = () =>
    mountPolicyEditor({ policy: null, policyType: PIPELINE_EXECUTION_POLICY_TYPE });

  // Only this editor validates its CI file client-side, before anything is submitted.
  describe('file path validation', () => {
    it('reports an empty file path once the user has edited it', async () => {
      mountCreatePage();

      await waitAndSetValue(findNameInput, POLICY_NAME);
      await selectCiProject();
      await waitAndSetValue(findFilePathInput, CI_FILE_PATH);

      // `doesFileExist` defaults to true, so an unchecked field looks valid too.
      await waitForAssertion(() => {
        expect(lastRequestVariables('getFile')).toEqual({
          fullPath: CI_PROJECT.fullPath,
          filePath: CI_FILE_PATH,
          ref: null,
        });
      });

      // Null before the clear, so the message below is something the clear produced.
      expect(findFilePathValidationError()).toBe(null);
      expect(isFilePathMarkedInvalid()).toBe(false);

      await waitAndSetValue(findFilePathInput, '');

      await waitForAssertion(() => {
        expect(getText(findFilePathValidationError())).toBe("The file path can't be empty");
      });
      expect(isFilePathMarkedInvalid()).toBe(true);
    });

    it('reports a file path that the chosen project does not have', async () => {
      setQueryVariant(getFile).missing();

      mountCreatePage();

      await waitAndSetValue(findNameInput, POLICY_NAME);
      await selectCiProject();
      await waitAndSetValue(findFilePathInput, MISSING_FILE_PATH);

      await waitForAssertion(() => {
        expect(getText(findFilePathValidationError())).toBe(
          "The file at that project, ref, and path doesn't exist",
        );
      });
      expect(isFilePathMarkedInvalid()).toBe(true);
      // Ties the message to a lookup of this path, not the empty-path validation.
      expect(lastRequestVariables('getFile')).toEqual({
        fullPath: CI_PROJECT.fullPath,
        filePath: MISSING_FILE_PATH,
        ref: null,
      });
    });
  });

  describe('when the save is rejected', () => {
    beforeEach(() => {
      // Stubbed to fail so the flow stops at the save mutation.
      setQueryVariant(updatePolicy).error();
    });

    // The frontend's half: it submits the untouched template rather than filling it in.
    it('submits the untouched template, and renders the rejection', async () => {
      mountCreatePage();

      const saveButton = await waitForElement(findSaveButton);
      // Pins create mode: an editor really in edit mode would compose REPLACE.
      expect(getText(saveButton)).toBe('Configure with a merge request');

      await waitAndSetValue(findNameInput, POLICY_NAME);

      findSaveButton().click();

      await waitForAssertion(() => {
        expect(lastRequestVariables('updatePolicy')).toEqual({
          mode: 'APPEND',
          name: POLICY_NAME,
          fullPath,
          policyYaml: composedYaml({ name: POLICY_NAME, include: TEMPLATE_INCLUDE }),
        });
      });

      const alert = await waitForElement(findErrorAlert);

      expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

      expectNoMergeRequestOpened();
    });
  });

  // A successful save redirects; jsdom refuses and logs it. Ignoring the message keeps the
  // production `visitUrl` in the chain instead of mocking away part of the flow.
  describe('when the save succeeds', () => {
    ignoreConsoleMessages([/Not implemented: navigation/]);

    it('commits the chosen project and file, then opens a merge request for that commit', async () => {
      mountCreatePage();

      await waitAndSetValue(findNameInput, POLICY_NAME);
      await selectCiProject();
      await waitAndSetValue(findFilePathInput, CI_FILE_PATH);

      findSaveButton().click();

      await waitForAssertion(() => {
        expect(snapshotRequests().createMergeRequest).toBe(1);
      });

      expect(lastRequestVariables('updatePolicy')).toEqual({
        mode: 'APPEND',
        name: POLICY_NAME,
        fullPath,
        policyYaml: composedYaml({ name: POLICY_NAME, include: CHOSEN_FILE_INCLUDE }),
      });

      expect(lastRequestVariables('createMergeRequest')).toEqual({
        input: {
          projectPath: POLICY_PROJECT_PATH,
          // The branch the commit mutation reported, not one the editor invented.
          sourceBranch: updatePolicy.BASE.data.scanExecutionPolicyCommit.branch,
          targetBranch: POLICY_PROJECT_BRANCH,
          title: DEFAULT_MR_TITLE,
          description: '',
          removeSourceBranch: true,
        },
      });

      // Nothing up to the commit response errored; the merge-request response is out of reach.
      expect(findErrorAlert()).toBe(null);
    });
  });
});
