import groupCustomRoles from 'test_fixtures/graphql/security_policies/integration/group_custom_roles.query.graphql.json';
import { ignoreConsoleMessages } from 'helpers/console_watcher';
import { lastRequestVariables, snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import { APPROVAL_POLICY_TYPE } from 'ee/security_orchestration/components/constants';
import { DEFAULT_MR_TITLE } from 'ee/security_orchestration/components/policy_editor/constants';
import {
  getText,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import {
  expectNoMergeRequestOpened,
  mountPolicyEditor,
  NAMESPACE_PATHS,
  POLICY_PROJECT_BRANCH,
  POLICY_PROJECT_PATH,
} from '../test_setup';

const POLICY_NAME = 'Prevent vulnerabilities';

// The custom role the group fixture carries, offered as a second option group. The project
// fixture resolves `memberRoles` to null, so the project listbox has none.
const [GROUP_CUSTOM_ROLE] = groupCustomRoles.data.group.memberRoles.nodes;

// The mount below narrows `roleApproverTypes` to two, so anything past them is custom.
const EXPECTED_ROLES = {
  [NAMESPACE_TYPES.PROJECT]: ['Maintainer', 'Owner'],
  [NAMESPACE_TYPES.GROUP]: ['Maintainer', 'Owner', GROUP_CUSTOM_ROLE.name],
};

// A group policy starts from a different default manifest: project scope plus one setting.
const SCOPE_BLOCK = `policy_scope:
  projects:
    excluding: []
`;
const GROUP_SETTING = '  block_group_branch_modification: true\n';

// The rule the default manifest ships: present, but with no type chosen yet.
const UNSET_RULE = `rules:
  - type: ''
`;

const NO_RULES = `rules: []
`;

// Spelled out rather than derived from `securityScanBuildRule`, which would be circular.
const SECURITY_SCAN_RULE = `rules:
  - type: scan_finding
    scanners:
      - type: sast
        vulnerabilities_allowed: 0
        severity_levels:
          - critical
          - high
        vulnerability_states:
          - new_needs_triage
        vulnerability_attributes:
          false_positive: false
      - type: secret_detection
        vulnerabilities_allowed: 0
        severity_levels:
          - critical
          - high
        vulnerability_states:
          - new_needs_triage
      - type: dependency_scanning
        vulnerabilities_allowed: 0
        vulnerability_attributes:
          false_positive: false
          fix_available: true
          known_exploited: true
          epss_score:
            operator: greater_than
            value: 0.1
          enrichment_data_unavailable:
            action: block
        is_malicious: true
    vulnerabilities_allowed: 0
    severity_levels: []
    vulnerability_states: []
    branch_type: protected
`;

const OWNER_APPROVER = `    role_approvers:
      - owner
`;

// Spelled out rather than derived from the default manifest, which would make every
// assertion below true by construction.
const composedYaml = ({ name = '', namespaceType, rules = UNSET_RULE, approvers = '' }) => {
  const isGroup = namespaceType === NAMESPACE_TYPES.GROUP;

  // js-yaml renders an empty name as a quoted empty string.
  return `name: ${name || "''"}
description: ''
enabled: true
enforcement_type: warn
${isGroup ? SCOPE_BLOCK : ''}${rules}actions:
  - type: require_approval
    approvals_required: 1
${approvers}  - type: send_bot_message
    enabled: true
approval_settings:
  block_branch_modification: true
${isGroup ? GROUP_SETTING : ''}  prevent_pushing_and_force_pushing: true
  prevent_approval_by_author: true
  prevent_approval_by_commit_author: true
  remove_approvals_with_new_commit: true
  prevent_editing_approval_rules: false
  require_password_to_approve: false
fallback_behavior:
  fail: closed
type: approval_policy
`;
};

const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findNameInput = () => document.querySelector('[data-testid="policy-name-text"]');
const findRemoveFirstRule = () =>
  document.querySelector('[data-testid="rule-0"] [data-testid="remove-rule"]');
const findScanTypeToggle = () => document.querySelector('#scanType button');
const findApproverTypeToggle = () =>
  document.querySelector('[data-testid="action-0"] [data-testid="available-types"] button');
const findRoleToggle = () => document.querySelector('[data-testid="approver-items"] button');
const findRoleOptions = () => [
  ...document.querySelectorAll('[data-testid="approver-items"] [data-testid^="listbox-item-"]'),
];
const findListboxItem = (value) => document.querySelector(`[data-testid="listbox-item-${value}"]`);

// `role_select.vue` appends custom roles as a second option group, so the list is only
// settled once that response lands — and each namespace needs its own signal for that.
const CUSTOM_ROLES_LANDED = {
  [NAMESPACE_TYPES.PROJECT]: () => expect(snapshotRequests().projectCustomRoles).toBe(1),
  [NAMESPACE_TYPES.GROUP]: () =>
    expect(findListboxItem(getIdFromGraphQLId(GROUP_CUSTOM_ROLE.id))).not.toBe(null),
};

describe.each([NAMESPACE_TYPES.PROJECT, NAMESPACE_TYPES.GROUP])(
  'Creating a merge request approval policy at %s level',
  (namespaceType) => {
    const fullPath = NAMESPACE_PATHS[namespaceType];

    const mountCreatePage = (dataset) =>
      mountPolicyEditor({
        policy: null,
        policyType: APPROVAL_POLICY_TYPE,
        namespaceType,
        dataset,
      });

    describe('when the save is rejected', () => {
      beforeEach(() => {
        // Stubbed to fail so the flow stops at the save mutation.
        setQueryVariant(updatePolicy).error();
      });

      // The frontend's half: it submits what the user left on screen and shows what returns.
      it('submits an empty name as an append, and renders the rejection', async () => {
        mountCreatePage();

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
            policyYaml: composedYaml({ namespaceType }),
          });
        });

        const alert = await waitForElement(findErrorAlert);

        expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
        expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

        expectNoMergeRequestOpened();
      });

      // The template asks for one approval without naming an approver; the frontend's half
      // is submitting that as-is rather than inventing one.
      it('submits the approver action with nobody named on it', async () => {
        mountCreatePage();

        await waitAndSetValue(findNameInput, POLICY_NAME);
        findSaveButton().click();

        await waitForAssertion(() => {
          expect(lastRequestVariables('updatePolicy')).toEqual({
            mode: 'APPEND',
            name: POLICY_NAME,
            fullPath,
            policyYaml: composedYaml({ name: POLICY_NAME, namespaceType }),
          });
        });

        expect(lastRequestVariables('updatePolicy').policyYaml).not.toMatch(/_approvers/);

        const alert = await waitForElement(findErrorAlert);

        expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
        expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

        expectNoMergeRequestOpened();
      });

      // `role_select.vue` builds its standard options from `roleApproverTypes`, so a role
      // outside that list is never offered — the backend rejection the original tested.
      it('offers only the roles the namespace allows, and submits the one picked', async () => {
        mountCreatePage({ roleApproverTypes: '["maintainer","owner"]' });

        await waitAndSetValue(findNameInput, POLICY_NAME);
        await waitAndClick(findApproverTypeToggle);
        await waitAndClick(() => findListboxItem('role'));
        await waitAndClick(findRoleToggle);

        // `waitForAssertion` checks synchronously first, before the custom-role response.
        await waitForAssertion(CUSTOM_ROLES_LANDED[namespaceType]);

        await waitForAssertion(() => {
          // Developer is offered by default, so its absence is the dataset narrowing it.
          expect(findRoleOptions().map((option) => getText(option))).toEqual(
            EXPECTED_ROLES[namespaceType],
          );
        });

        await waitAndClick(() => findListboxItem('owner'));

        findSaveButton().click();

        await waitForAssertion(() => {
          expect(lastRequestVariables('updatePolicy')).toEqual({
            mode: 'APPEND',
            name: POLICY_NAME,
            fullPath,
            policyYaml: composedYaml({
              name: POLICY_NAME,
              namespaceType,
              approvers: OWNER_APPROVER,
            }),
          });
        });

        const alert = await waitForElement(findErrorAlert);

        expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
        expect(getText(alert)).toContain(SYNTHETIC_SECONDARY_SAVE_ERROR);

        expectNoMergeRequestOpened();
      });

      it('submits an empty rules list when the user removes the only rule', async () => {
        mountCreatePage();

        await waitAndSetValue(findNameInput, POLICY_NAME);
        await waitAndClick(findRemoveFirstRule);

        findSaveButton().click();

        await waitForAssertion(() => {
          expect(lastRequestVariables('updatePolicy')).toEqual({
            mode: 'APPEND',
            name: POLICY_NAME,
            fullPath,
            policyYaml: composedYaml({ name: POLICY_NAME, namespaceType, rules: NO_RULES }),
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

      it('commits the policy, then opens a merge request for that commit', async () => {
        mountCreatePage();

        await waitAndSetValue(findNameInput, POLICY_NAME);
        await waitAndClick(findScanTypeToggle);
        await waitAndClick(() => findListboxItem('scan_finding'));

        findSaveButton().click();

        await waitForAssertion(() => {
          expect(snapshotRequests().createMergeRequest).toBe(1);
        });

        expect(lastRequestVariables('updatePolicy')).toEqual({
          mode: 'APPEND',
          name: POLICY_NAME,
          fullPath,
          policyYaml: composedYaml({
            name: POLICY_NAME,
            namespaceType,
            rules: SECURITY_SCAN_RULE,
          }),
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

        // Nothing up to the commit response errored.
        expect(findErrorAlert()).toBe(null);
      });
    });
  },
);
