import {
  CONDITION_SECTION_DISABLE_ERROR,
  UNSUPPORTED_CADENCE_DISABLE_ERROR,
  UNSUPPORTED_CADENCE_TITLE,
} from 'ee/security_orchestration/components/policy_editor/constants';
import { getText, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { mountPolicyEditor } from '../test_setup';

// `disabled_section.vue` owns the fallback title for every non-schedule parsing error.
const INVALID_SYNTAX_TITLE = 'Invalid syntax';

const policyWithRules = (rules) => ({
  name: 'Nightly secret detection',
  description: 'Runs secret detection on a schedule',
  enabled: true,
  rules,
  actions: [{ scan: 'secret_detection' }],
});

// Valid cron the backend runs happily, but more than the rule-mode builder can express.
const UNSUPPORTED_CADENCE_POLICY = policyWithRules([
  { type: 'schedule', cadence: '*/15 9-17 * * *', branches: ['main'] },
]);

// `branches` and `branch_type` are mutually exclusive, so this rule is genuinely broken.
const CONFLICTING_KEYS_POLICY = policyWithRules([
  { type: 'pipeline', branches: ['main'], branch_type: 'default' },
]);

const EDITABLE_POLICY = policyWithRules([
  { type: 'schedule', cadence: '0 9 * * *', branches: ['main'] },
]);

const findRuleSection = () => document.querySelector('[data-testid="disabled-rule"]');
const findRuleSectionOverlay = () =>
  document.querySelector('[data-testid="disabled-rule"] [data-testid="disabled-section-overlay"]');

describe('Scan execution policy editor rule parsing errors', () => {
  it('tells the user the schedule is undisplayable rather than invalid', async () => {
    mountPolicyEditor({ policy: UNSUPPORTED_CADENCE_POLICY });

    const section = await waitForElement(findRuleSection);

    expect(getText(section)).toContain(UNSUPPORTED_CADENCE_TITLE);
    expect(getText(section)).toContain(UNSUPPORTED_CADENCE_DISABLE_ERROR);
    // This YAML is valid and the policy still runs, so the generic wording would be wrong.
    expect(getText(section)).not.toContain(INVALID_SYNTAX_TITLE);
    expect(getText(section)).not.toContain(CONDITION_SECTION_DISABLE_ERROR);
    expect(findRuleSectionOverlay()).not.toBe(null);
  });

  it('falls back to the invalid-syntax message for a rule it cannot parse', async () => {
    mountPolicyEditor({ policy: CONFLICTING_KEYS_POLICY });

    const section = await waitForElement(findRuleSection);

    expect(getText(section)).toContain(INVALID_SYNTAX_TITLE);
    expect(getText(section)).toContain(CONDITION_SECTION_DISABLE_ERROR);
    expect(getText(section)).not.toContain(UNSUPPORTED_CADENCE_TITLE);
    expect(getText(section)).not.toContain(UNSUPPORTED_CADENCE_DISABLE_ERROR);
    expect(findRuleSectionOverlay()).not.toBe(null);
  });

  // Negative control: the editor renders neither message by default.
  it('disables nothing for a schedule rule mode can display', async () => {
    mountPolicyEditor({ policy: EDITABLE_POLICY });

    const section = await waitForElement(findRuleSection);

    expect(getText(section)).not.toContain(UNSUPPORTED_CADENCE_TITLE);
    expect(getText(section)).not.toContain(INVALID_SYNTAX_TITLE);
    expect(findRuleSectionOverlay()).toBe(null);
  });
});
