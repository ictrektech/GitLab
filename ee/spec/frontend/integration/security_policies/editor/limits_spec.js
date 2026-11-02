import { APPROVAL_POLICY_TYPE } from 'ee/security_orchestration/components/constants';
import { waitForAssertion, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { mountPolicyEditor } from '../test_setup';

// Classified as custom, so the builders render without switching the configuration type.
const CUSTOM_SCAN_EXECUTION_POLICY = {
  name: 'Custom SAST scan',
  description: 'Runs SAST on the default branch',
  enabled: true,
  rules: [{ type: 'pipeline', branches: ['main'] }],
  actions: [{ scan: 'sast' }],
};

const approvalRule = () => ({
  type: 'any_merge_request',
  branch_type: 'protected',
  commits: 'any',
});

const approvalPolicyWithRules = (ruleCount) => ({
  name: 'Approvals for protected branches',
  description: 'Requires approval on protected branches',
  enabled: true,
  rules: Array.from({ length: ruleCount }, approvalRule),
  actions: [{ type: 'require_approval', approvals_required: 1, role_approvers: ['owner'] }],
});

const findAddAction = () => document.querySelector('[data-testid="add-action"]');
const findAddActionWrapper = () => document.querySelector('[data-testid="add-action-wrapper"]');
const findAddRule = () => document.querySelector('[data-testid="add-rule"]');
const findPreview = () => document.querySelector('[data-testid="rule-editor-preview-content"]');
const findStatusRadios = () => [
  ...document.querySelectorAll('[data-testid="policy-status-selection"] input[type="radio"]'),
];

// GlButton renders `disabled` as `aria-disabled`, not the native attribute.
const isDisabled = (element) => element.getAttribute('aria-disabled') === 'true';

describe('Scan execution policy action limit', () => {
  it('stops offering new actions once the instance limit is reached, and says why', async () => {
    mountPolicyEditor({
      policy: CUSTOM_SCAN_EXECUTION_POLICY,
      dataset: { maxScanExecutionPolicyActions: '2' },
    });

    await waitForElement(findAddAction);

    // One action, limit of two: still under the limit, and no explanation to give.
    expect(isDisabled(findAddAction())).toBe(false);
    expect(findAddActionWrapper().getAttribute('title')).toBe('');

    findAddAction().click();

    await waitForAssertion(() => {
      expect(isDisabled(findAddAction())).toBe(true);
    });

    // The plural comes from the number of actions, so a limit of 2 reads as "actions".
    expect(findAddActionWrapper().getAttribute('title')).toBe(
      'Policy has reached the maximum of 2 actions',
    );
  });

  it('applies the singular form when the limit is one', async () => {
    mountPolicyEditor({
      policy: CUSTOM_SCAN_EXECUTION_POLICY,
      dataset: { maxScanExecutionPolicyActions: '1' },
    });

    await waitForElement(findAddAction);

    expect(isDisabled(findAddAction())).toBe(true);
    expect(findAddActionWrapper().getAttribute('title')).toBe(
      'Policy has reached the maximum of 1 action',
    );
  });
});

describe('Merge request approval policy rule limit', () => {
  // MAX_ALLOWED_RULES_LENGTH has no dataset behind it, so walk the policy up to it.
  it('stops offering new rules at the fifth one', async () => {
    mountPolicyEditor({
      policy: approvalPolicyWithRules(4),
      policyType: APPROVAL_POLICY_TYPE,
    });

    await waitForElement(findAddRule);
    expect(isDisabled(findAddRule())).toBe(false);

    findAddRule().click();

    // The new rule has no type yet, which is how it shows up in the YAML.
    await waitForAssertion(() => {
      expect(findPreview().textContent).toContain("- type: ''");
    });

    expect(isDisabled(findAddRule())).toBe(true);
  });
});

// `editor_layout.vue` reads the enabled state once, so the limit only locks a policy that
// is not already enabled. jsdom hides the tooltip, so only the lock itself is asserted.
describe.each`
  description                                          | limitReached | enabled  | locked
  ${'the limit is reached and the policy is disabled'} | ${'true'}    | ${false} | ${true}
  ${'the limit is reached but the policy is enabled'}  | ${'true'}    | ${true}  | ${false}
  ${'the limit is not reached'}                        | ${'false'}   | ${false} | ${false}
`('when $description', ({ limitReached, enabled, locked }) => {
  it(`renders the policy status radios ${locked ? 'locked' : 'editable'}`, async () => {
    mountPolicyEditor({
      policy: { ...CUSTOM_SCAN_EXECUTION_POLICY, enabled },
      dataset: { maxActiveScanExecutionPoliciesReached: limitReached },
    });

    await waitForElement(findAddAction);

    const radios = findStatusRadios();
    expect(radios).toHaveLength(2);
    expect(radios.map((radio) => radio.disabled)).toEqual([locked, locked]);
  });
});
