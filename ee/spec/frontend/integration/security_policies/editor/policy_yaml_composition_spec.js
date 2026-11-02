import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import { expectNoMergeRequestOpened, mountPolicyEditor } from '../test_setup';

// Spelled out rather than imported: the builder's own rule strategy would make "this is the
// optimized policy" true by construction, and the radios only enable for an optimized one.
const OPTIMIZED_POLICY = {
  name: 'Optimized secret detection',
  description: 'Runs secret detection on merge requests and the default branch',
  enabled: true,
  rules: [
    { type: 'pipeline', branch_type: 'default' },
    {
      type: 'pipeline',
      branch_type: 'target_default',
      pipeline_sources: { including: ['merge_request_event'] },
    },
  ],
  actions: [{ scan: 'secret_detection', template: 'latest' }],
  skip_ci: { allowed: true },
};

const NEW_NAME = 'Renamed in rule mode';
const NEW_DESCRIPTION = 'Description rewritten in rule mode';

const findPreview = () => document.querySelector('[data-testid="rule-editor-preview-content"]');
const previewYaml = () => findPreview().textContent;
const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findConfigRadio = (value) =>
  document.querySelector(`[data-testid="enforcement-selection"] input[value="${value}"]`);
const findStatusRadio = (value) =>
  document.querySelector(`[data-testid="policy-status-selection"] input[value="${value}"]`);

const INITIAL_YAML = `scan_execution_policy:
  - name: Optimized secret detection
    description: Runs secret detection on merge requests and the default branch
    enabled: true
    rules:
      - type: pipeline
        branch_type: default
      - type: pipeline
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
`;

// Pinned in full: the editor derives its YAML from the policy object after every mutation
// rather than patching it in place.
const EDITED_YAML = `scan_execution_policy:
  - name: ${NEW_NAME}
    description: ${NEW_DESCRIPTION}
    enabled: false
    rules:
      - type: pipeline
        branch_type: default
      - type: pipeline
        branch_type: target_default
        pipeline_sources:
          including:
            - merge_request_event
      - type: pipeline
        branches:
          - '*'
    actions:
      - scan: secret_detection
        template: latest
        variables:
          SECURE_ENABLE_LOCAL_CONFIGURATION: 'false'
      - scan: secret_detection
        variables:
          SECURE_ENABLE_LOCAL_CONFIGURATION: 'false'
    skip_ci:
      allowed: true
`;

// The same policy, unwrapped and with the root `type` the mutation still expects.
const EXPECTED_POLICY_YAML = `name: ${NEW_NAME}
description: ${NEW_DESCRIPTION}
enabled: false
rules:
  - type: pipeline
    branch_type: default
  - type: pipeline
    branch_type: target_default
    pipeline_sources:
      including:
        - merge_request_event
  - type: pipeline
    branches:
      - '*'
actions:
  - scan: secret_detection
    template: latest
    variables:
      SECURE_ENABLE_LOCAL_CONFIGURATION: 'false'
  - scan: secret_detection
    variables:
      SECURE_ENABLE_LOCAL_CONFIGURATION: 'false'
skip_ci:
  allowed: true
type: scan_execution_policy
`;

describe('Scan execution policy editor YAML composition', () => {
  beforeEach(() => {
    // Stubbed to fail so the flow stops at the save mutation.
    setQueryVariant(updatePolicy).error();
  });

  it('re-derives the YAML from every rule-mode edit and sends it as policyYaml', async () => {
    mountPolicyEditor({ policy: OPTIMIZED_POLICY });

    await waitForElement(findPreview);
    expect(previewYaml()).toBe(INITIAL_YAML);

    // A view change, so the YAML must survive untouched; otherwise the edits below could be
    // passing on a rebuild the radio triggered.
    findConfigRadio('custom').click();
    await waitForElement(() => document.querySelector('[data-testid="custom-action-config"]'));
    expect(previewYaml()).toBe(INITIAL_YAML);

    findConfigRadio('default').click();
    await waitForElement(() => document.querySelector('[data-testid="default-action-config"]'));
    expect(previewYaml()).toBe(INITIAL_YAML);

    // Back to the custom view, where the rule and action builders live.
    findConfigRadio('custom').click();
    await waitForElement(() => document.querySelector('[data-testid="custom-action-config"]'));

    await waitAndSetValue(
      () => document.querySelector('[data-testid="policy-name-text"]'),
      NEW_NAME,
    );
    await waitForAssertion(() => {
      expect(previewYaml()).toContain(`name: ${NEW_NAME}`);
    });

    await waitAndSetValue(
      () => document.querySelector('[data-testid="policy-description-text"]'),
      NEW_DESCRIPTION,
    );
    await waitForAssertion(() => {
      expect(previewYaml()).toContain(`description: ${NEW_DESCRIPTION}`);
    });

    findStatusRadio('false').click();
    await waitForAssertion(() => {
      expect(previewYaml()).toContain('enabled: false');
    });

    await waitAndClick(() => document.querySelector('[data-testid="add-rule"]'));
    await waitAndClick(() => document.querySelector('[data-testid="add-action"]'));

    await waitForAssertion(() => {
      expect(previewYaml()).toBe(EDITED_YAML);
    });

    findSaveButton().click();

    await waitForAssertion(() => {
      expect(lastRequestVariables('updatePolicy')).toEqual({
        mode: 'REPLACE',
        // The name on disk, so a rename cannot retarget the commit at a missing policy.
        name: OPTIMIZED_POLICY.name,
        fullPath: 'flightjs/Flight',
        policyYaml: EXPECTED_POLICY_YAML,
      });
    });

    // `addRule`/`addAction` tag each entry with a `uniqueId` for Vue; the schema rejects it.
    expect(lastRequestVariables('updatePolicy').policyYaml).not.toMatch(/\bid:/);

    const alert = await waitForElement(findErrorAlert);

    expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
    expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

    expectNoMergeRequestOpened();
  });
});
