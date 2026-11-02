import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import {
  APPROVAL_POLICY_TYPE,
  SCAN_EXECUTION_POLICY_TYPE,
} from 'ee/security_orchestration/components/constants';
import {
  getText,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import {
  EXISTING_APPROVAL_POLICY,
  EXISTING_SCAN_EXECUTION_POLICY,
  expectNoMergeRequestOpened,
  mountPolicyEditor,
  NAMESPACE_PATHS,
} from '../test_setup';

// Spelled out rather than derived from the fixture, so a change the editor makes on the way
// back out shows up as a diff here.
const APPROVAL_YAML_WITHOUT_NAME = `name: ''
description: This policy considers only container scanning and critical severities
enabled: true
policy_scope: {}
actions:
  - type: require_approval
    approvals_required: 1
    user_approvers:
      - admin
rules:
  - type: scan_finding
    branches:
      - master
    scanners:
      - container_scanning
    vulnerabilities_allowed: 0
    severity_levels:
      - critical
    vulnerability_states:
      - detected
    vulnerability_attributes: {}
approval_settings: {}
fallback_behavior: {}
metadata: {}
policy_tuning: {}
bypass_settings: {}
enforcement_type: enforce
type: approval_policy
`;

const SCAN_EXECUTION_YAML_WITHOUT_NAME = `name: ''
description: This policy enforces to run DAST for every pipeline within the project
enabled: true
policy_scope: {}
actions:
  - scan: dast
    site_profile: Site Profile
    scanner_profile: Scanner Profile
rules:
  - type: pipeline
    branches:
      - master
metadata: {}
type: scan_execution_policy
`;

const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findNameInput = () => document.querySelector('[data-testid="policy-name-text"]');
const findNameError = () => document.querySelector('#policyName ~ .invalid-feedback');

// `updatePolicy` replaces by the name the policy had when the editor opened, so submitting
// the edited name would append a second policy instead.
describe.each`
  policyType                    | existingPolicy                    | expectedYaml
  ${APPROVAL_POLICY_TYPE}       | ${EXISTING_APPROVAL_POLICY}       | ${APPROVAL_YAML_WITHOUT_NAME}
  ${SCAN_EXECUTION_POLICY_TYPE} | ${EXISTING_SCAN_EXECUTION_POLICY} | ${SCAN_EXECUTION_YAML_WITHOUT_NAME}
`('Editing an existing $policyType', ({ policyType, existingPolicy, expectedYaml }) => {
  const fullPath = NAMESPACE_PATHS[NAMESPACE_TYPES.PROJECT];

  beforeEach(() => {
    // Stubbed to fail so the flow stops at the save mutation.
    setQueryVariant(updatePolicy).error();
  });

  it('replaces the policy under its original name, and renders the rejection', async () => {
    // `policy` is left to `mountPolicyEditor`, whose type-keyed lookup is what stops a
    // policy body being paired with another type's editor.
    mountPolicyEditor({ policyType });

    const saveButton = await waitForElement(findSaveButton);
    // Pins edit mode: a create page would compose APPEND instead.
    expect(getText(saveButton)).toBe('Update via merge request');
    expect(findNameInput().value).toBe(existingPolicy.name);
    expect(findNameInput().getAttribute('aria-invalid')).toBe(null);

    await waitAndSetValue(findNameInput, '');

    // The editor's own verdict on an empty name, which it reaches without asking the
    // server. `aria-invalid` is the assertion: GlFormGroup renders the feedback text
    // whether or not the field is in an invalid state.
    await waitForAssertion(() => {
      expect(findNameInput().getAttribute('aria-invalid')).toBe('true');
    });
    expect(getText(findNameError())).toBe('This field is required');

    findSaveButton().click();

    await waitForAssertion(() => {
      expect(lastRequestVariables('updatePolicy')).toEqual({
        mode: 'REPLACE',
        name: existingPolicy.name,
        fullPath,
        policyYaml: expectedYaml,
      });
    });

    const alert = await waitForElement(findErrorAlert);

    expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
    expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

    expectNoMergeRequestOpened();
  });
});
