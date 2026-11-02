import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import {
  getText,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import { expectNoMergeRequestOpened, mountPolicyEditor, NAMESPACE_PATHS } from '../test_setup';

const POLICY_NAME = 'Branch information check';

// A group policy starts from a different default manifest, scope block included.
const SCOPE_BLOCK = `policy_scope:
  projects:
    excluding: []
`;

// Spelled out rather than derived from the default manifest, which would make every
// assertion below true by construction.
const composedYaml = ({ name = '', namespaceType, firstRule }) =>
  // js-yaml renders an empty name as a quoted empty string.
  `name: ${name || "''"}
description: ''
enabled: true
${namespaceType === NAMESPACE_TYPES.GROUP ? SCOPE_BLOCK : ''}rules:
${firstRule}  - type: pipeline
    branch_type: target_default
    pipeline_sources:
      including:
        - merge_request_event
actions:
  - scan: secret_detection
    template: latest
    variables:
      SECURE_ENABLE_LOCAL_CONFIGURATION: 'false'
skip_ci:
  allowed: true
type: scan_execution_policy
`;

const TEMPLATE_FIRST_RULE = `  - type: pipeline
    branch_type: default
`;

// No `branch_type`, and an empty `branches`: a schedule the user never gave a branch to.
const SCHEDULE_WITHOUT_BRANCHES = `  - type: schedule
    branches: []
    cadence: 0 0 * * *
    time_window:
      distribution: random
      value: 36000
`;

const PIPELINE_WITH_CLEARED_BRANCHES = `  - type: pipeline
    branches: []
`;

const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findNameInput = () => document.querySelector('[data-testid="policy-name-text"]');
const findPreview = () => document.querySelector('[data-testid="rule-editor-preview-content"]');
const findConfigRadio = (value) =>
  document.querySelector(`[data-testid="enforcement-selection"] input[value="${value}"]`);
const findFirstRule = () => document.querySelector('[data-testid="rule-0"]');
const findRuleTypeToggle = () =>
  findFirstRule()?.querySelector('[data-testid="rule-component-type"] button') ?? null;
const findBranchTypeToggle = () =>
  findFirstRule()?.querySelector('#branch-type-selector button') ?? null;
const findBranchesInput = () =>
  findFirstRule()?.querySelector('[data-testid="rule-branches"]') ?? null;
const findListboxItem = (value) => document.querySelector(`[data-testid="listbox-item-${value}"]`);

// The builders only render under the custom configuration type.
const switchToCustomConfiguration = async () => {
  await waitAndClick(() => findConfigRadio('custom'));
  await waitForElement(findFirstRule);
};

describe.each([NAMESPACE_TYPES.PROJECT, NAMESPACE_TYPES.GROUP])(
  'Creating a scan execution policy at %s level',
  (namespaceType) => {
    const fullPath = NAMESPACE_PATHS[namespaceType];

    beforeEach(() => {
      // Stubbed to fail so the flow stops at the save mutation.
      setQueryVariant(updatePolicy).error();
    });

    // The frontend's half: it submits what the user left on screen and shows what comes back.
    it('submits an empty name as an append, and renders the rejection', async () => {
      mountPolicyEditor({ policy: null, namespaceType });

      const saveButton = await waitForElement(findSaveButton);
      // Pins create mode: an editor really in edit mode would compose REPLACE.
      expect(getText(saveButton)).toBe('Configure with a merge request');
      expect(findNameInput().value).toBe('');

      saveButton.click();

      await waitForAssertion(() => {
        expect(lastRequestVariables('updatePolicy')).toEqual({
          mode: 'APPEND',
          name: '',
          fullPath,
          policyYaml: composedYaml({ namespaceType, firstRule: TEMPLATE_FIRST_RULE }),
        });
      });

      const alert = await waitForElement(findErrorAlert);

      expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

      expectNoMergeRequestOpened();
    });

    it('drops the branch information the template rule carried when the rule becomes a schedule', async () => {
      mountPolicyEditor({ policy: null, namespaceType });

      await waitAndSetValue(findNameInput, POLICY_NAME);
      await switchToCustomConfiguration();

      // The template ships a pipeline rule on the default branch, so the switch removed it.
      await waitForAssertion(() => {
        expect(findPreview().textContent).toContain('branch_type: default');
      });

      await waitAndClick(findRuleTypeToggle);
      await waitAndClick(() => findListboxItem('schedule'));

      await waitForAssertion(() => {
        expect(findPreview().textContent).toContain('type: schedule');
      });

      findSaveButton().click();

      await waitForAssertion(() => {
        expect(lastRequestVariables('updatePolicy')).toEqual({
          mode: 'APPEND',
          name: POLICY_NAME,
          fullPath,
          policyYaml: composedYaml({
            name: POLICY_NAME,
            namespaceType,
            firstRule: SCHEDULE_WITHOUT_BRANCHES,
          }),
        });
      });

      const alert = await waitForElement(findErrorAlert);

      expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

      expectNoMergeRequestOpened();
    });

    it('submits an empty branches list when the user clears the specific-branches input', async () => {
      mountPolicyEditor({ policy: null, namespaceType });

      await waitAndSetValue(findNameInput, POLICY_NAME);
      await switchToCustomConfiguration();

      await waitAndClick(findBranchTypeToggle);
      await waitAndClick(() => findListboxItem('SPECIFIC_BRANCHES'));

      // Picking specific branches seeds the wildcard, so the empty list is the user's doing.
      const branchesInput = await waitForElement(findBranchesInput);
      expect(branchesInput.value).toBe('*');

      await waitAndSetValue(findBranchesInput, '');

      await waitForAssertion(() => {
        expect(findPreview().textContent).toContain('branches: []');
      });

      findSaveButton().click();

      await waitForAssertion(() => {
        expect(lastRequestVariables('updatePolicy')).toEqual({
          mode: 'APPEND',
          name: POLICY_NAME,
          fullPath,
          policyYaml: composedYaml({
            name: POLICY_NAME,
            namespaceType,
            firstRule: PIPELINE_WITH_CLEARED_BRANCHES,
          }),
        });
      });

      const alert = await waitForElement(findErrorAlert);

      expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

      expectNoMergeRequestOpened();
    });
  },
);
