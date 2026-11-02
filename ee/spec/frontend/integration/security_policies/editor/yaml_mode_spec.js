import { editor as monacoEditor } from 'monaco-editor';
import { setDiagnosticsOptions } from 'monaco-yaml';
import { lastRequestVariables, snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { CONTENT_UPDATE_DEBOUNCE } from '~/editor/constants';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import { APPROVAL_POLICY_TYPE } from 'ee/security_orchestration/components/constants';
import { MAX_ALLOWED_RULES_LENGTH } from 'ee/security_orchestration/components/policy_editor/constants';
import {
  findButtonByText,
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
// Loads the lazily imported editor and its Monaco graph at file load. Transforming it inside
// the test blocks the event loop past the test timeout on a cold CI runner.
import 'ee/security_orchestration/components/yaml_editor.vue';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import { expectNoMergeRequestOpened, mountPolicyEditor, NAMESPACE_PATHS } from '../test_setup';

const POLICY_NAME = 'Policy typed in YAML mode';

const RULE = `  - type: scan_finding
    scanners: []
    vulnerabilities_allowed: 0
    severity_levels: []
    vulnerability_states: []
    branch_type: protected
`;

// One past the cap, so rule mode could not have built this body — it hides "Add new rule"
// at the limit. That is what makes YAML mode the only way in. The rejection below is the
// stub's; the cap itself is asserted on the schema the editor registers.
const BODY = `name: ${POLICY_NAME}
description: ''
enabled: true
policy_scope:
  projects:
    excluding: []
rules:
${RULE.repeat(MAX_ALLOWED_RULES_LENGTH + 1)}actions:
  - type: require_approval
    approvals_required: 1
    role_approvers:
      - owner
  - type: send_bot_message
    enabled: true
approval_settings:
  block_branch_modification: true
  prevent_approval_by_author: true
fallback_behavior:
  fail: closed
`;

const TYPED_YAML = `type: ${APPROVAL_POLICY_TYPE}\n${BODY}`;

// The editor parses and re-serialises rather than forwarding the buffer, which moves
// `type` last. Everything else surviving verbatim is the point of the assertion.
const SUBMITTED_YAML = `${BODY}type: ${APPROVAL_POLICY_TYPE}\n`;

const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findErrorListItems = () =>
  [...findErrorAlert().querySelectorAll('li')].map((item) => getText(item));

// The only security policies spec that loads Monaco, so the only one that reaches YAML mode.
describe('Security policy editor in YAML mode', () => {
  beforeEach(() => {
    // Stubbed to fail so the flow stops at the save mutation.
    setQueryVariant(updatePolicy).error();
  });

  it('submits the policy typed into the editor, and renders a failed save', async () => {
    let editorInstance;
    const created = monacoEditor.onDidCreateEditor((instance) => {
      editorInstance = instance;
    });

    mountPolicyEditor({ policy: null, policyType: APPROVAL_POLICY_TYPE });

    await waitAndClick(() => findButtonByText('.yaml mode'));

    // The YAML editor is an async component, so its Monaco model is the signal that it
    // finished loading. Vue 2 and Vue 3 disagree on where the wrapper's testid lands.
    await waitForAssertion(() => {
      expect(monacoEditor.getModels().length).toBeGreaterThan(0);
    });
    const model = monacoEditor.getModels().at(-1);

    // `readOnly` defaults to true on yaml_editor.vue and `setValue` ignores it, so without
    // this an editor nobody could type into would still pass every assertion below.
    expect(editorInstance.getRawOptions().readOnly).toBe(false);
    created.dispose();

    model.setValue(TYPED_YAML);

    // source_editor.vue debounces its `input` by this much, and the save reads the value
    // synchronously, so the click has to come after the buffer has reached the component.
    await new Promise((resolve) => {
      setTimeout(resolve, CONTENT_UPDATE_DEBOUNCE * 2);
    });

    const saveButton = findSaveButton();
    // Pins create mode: an editor really in edit mode would compose REPLACE.
    expect(getText(saveButton)).toBe('Configure with a merge request');

    saveButton.click();

    await waitForAssertion(() => {
      expect(lastRequestVariables('updatePolicy')).toEqual({
        mode: 'APPEND',
        // Read back out of the typed YAML; YAML mode renders no name field to fill in.
        name: POLICY_NAME,
        fullPath: NAMESPACE_PATHS[NAMESPACE_TYPES.PROJECT],
        policyYaml: SUBMITTED_YAML,
      });
    });

    const alert = await waitForElement(findErrorAlert);

    expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
    expect(findErrorListItems()).toEqual([SYNTHETIC_SECONDARY_SAVE_ERROR]);

    // The schema drives validation and autocomplete, and its caller swallows a failed
    // fetch, so nothing but this would notice the editor losing both.
    expect(snapshotRequests().securityPolicySchema).toBe(1);

    // The cap the editor validates against comes from the backend's schema, so this is
    // what fails if the two ever disagree about how many rules a policy may have.
    const [{ schemas }] = setDiagnosticsOptions.mock.calls.at(-1);
    const [{ schema }] = schemas;

    expect(schema.properties[APPROVAL_POLICY_TYPE].items.properties.rules.maxItems).toBe(
      MAX_ALLOWED_RULES_LENGTH,
    );

    expectNoMergeRequestOpened();
  });
});
