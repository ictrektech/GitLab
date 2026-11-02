import Ajv from 'ajv/dist/2020';
import AjvFormats from 'ajv-formats';
import { safeLoad } from 'js-yaml';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EditorComponent, {
  DEFAULT_DEPENDENCY_FIREWALL_POLICY,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/editor_component.vue';
import EditorLayout from 'ee/security_orchestration/components/policy_editor/editor_layout.vue';
import RuleList from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_list.vue';
import PolicyDetailsCard from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/policy_details_card.vue';
import PolicyScopeCard from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/policy_scope_card.vue';
import SectionHeading from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/section_heading.vue';
import DisabledSection from 'ee/security_orchestration/components/policy_editor/disabled_section.vue';
import BypassSettings from 'ee/security_orchestration/components/policy_editor/dependency_firewall/advanced_settings/bypass_settings.vue';
import { buildDefaultRuleForType } from 'ee/security_orchestration/components/policy_editor/dependency_firewall/utils';
import { removeIdsFromPolicy } from 'ee/security_orchestration/components/policy_editor/utils';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/constants';
import {
  EDITOR_MODE_RULE,
  EDITOR_MODE_YAML,
} from 'ee/security_orchestration/components/policy_editor/constants';
import PolicySchema from '../../../../../../app/validators/json_schemas/security_orchestration_policy.json';

// ajv cannot compile the full policy schema - an unrelated cron `pattern` in it is not a
// valid unicode-mode regex - so validate against the `dependency_firewall_policy` subtree,
// carrying `$defs` over for its `$ref`s. Strict mode is off because the schema declares
// draft 2020-12 but still uses the draft-07 `additionalItems` keyword.
const ajv = new Ajv({ strict: false, allowMatchingProperties: true });
AjvFormats(ajv);
const validate = ajv.compile({
  $schema: PolicySchema.$schema,
  $defs: PolicySchema.$defs,
  type: 'object',
  required: ['dependency_firewall_policy'],
  properties: {
    dependency_firewall_policy: PolicySchema.properties.dependency_firewall_policy,
  },
});

describe('DependencyFirewallEditorComponent', () => {
  let wrapper;

  const createWrapper = (propsData = {}, glFeatures = { dependencyFirewallPhase2: true }) => {
    wrapper = shallowMountExtended(EditorComponent, {
      propsData: {
        existingPolicy: null,
        isCreating: false,
        isDeleting: false,
        isEditing: false,
        selectedPolicyType: 'dependency_firewall_policy',
        ...propsData,
      },
      provide: { glFeatures },
    });
  };

  const findEditorLayout = () => wrapper.findComponent(EditorLayout);

  it('defaults to rule mode with both modes available', () => {
    createWrapper();
    expect(findEditorLayout().props('defaultEditorMode')).toBe(EDITOR_MODE_RULE);
    expect(findEditorLayout().props('editorModes')).toEqual([
      expect.objectContaining({ value: EDITOR_MODE_RULE }),
      expect.objectContaining({ value: EDITOR_MODE_YAML }),
    ]);
  });

  it('renders the rule list seeded from the default policy YAML with no rules', () => {
    createWrapper();
    expect(wrapper.findComponent(RuleList).props('rules')).toEqual([]);
  });

  it('renders the policy details card seeded from the default policy YAML', () => {
    createWrapper();
    expect(wrapper.findComponent(PolicyDetailsCard).props('enforcementType')).toBe('warn');
  });

  it('updates the yaml editor value when a rule changes', async () => {
    createWrapper();
    const initialYaml = findEditorLayout().props('yamlEditorValue');

    await wrapper.findComponent(RuleList).vm.$emit('changed', [{ type: 'license', denied: [] }]);

    expect(findEditorLayout().props('yamlEditorValue')).not.toBe(initialYaml);
    expect(findEditorLayout().props('yamlEditorValue')).toContain('type: license');
  });

  it('updates the yaml editor value when the enforcement type changes', async () => {
    createWrapper();
    await wrapper.findComponent(PolicyDetailsCard).vm.$emit('change-enforcement-type', 'enforced');
    expect(findEditorLayout().props('yamlEditorValue')).toContain('enforcement_type: enforced');
  });

  it('updates the yaml editor value when the policy details card changes a property', async () => {
    createWrapper();
    await wrapper.findComponent(PolicyDetailsCard).vm.$emit('update-property', 'name', 'Card name');
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Card name');
  });

  it('removes the policy scope when the policy scope card emits remove-property', async () => {
    createWrapper();
    expect(findEditorLayout().props('yamlEditorValue')).toContain('policy_scope:');

    await wrapper.findComponent(PolicyScopeCard).vm.$emit('remove-property', 'policy_scope');

    expect(findEditorLayout().props('yamlEditorValue')).not.toContain('policy_scope:');
  });

  it('updates the yaml editor value when a policy property changes', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit('update-property', 'name', 'My DFW Policy');
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: My DFW Policy');
  });

  it('re-parses the policy object when the yaml pane is edited directly', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit(
      'update-yaml',
      'dependency_firewall_policy:\n  - name: x\n    enabled: true\n    enforcement_type: warn\n    rules: []\n',
    );
    expect(wrapper.findComponent(RuleList).props('rules')).toEqual([]);
  });

  it('ignores an update-yaml echo of the value it just set, preserving rule ids', async () => {
    createWrapper();
    await wrapper
      .findComponent(RuleList)
      .vm.$emit('changed', [{ type: 'malicious', denied: [{ is_malicious: true }] }]);

    const rulesBefore = wrapper.findComponent(RuleList).props('rules');
    const yamlEcho = findEditorLayout().props('yamlEditorValue');

    // Simulates the underlying Monaco editor firing its change event for the
    // programmatic :value update we just made (not a genuine user edit).
    await findEditorLayout().vm.$emit('update-yaml', yamlEcho);

    const rulesAfter = wrapper.findComponent(RuleList).props('rules');
    expect(rulesAfter).toBe(rulesBefore);
    expect(rulesAfter[0].id).toBe(rulesBefore[0].id);
  });

  it('emits save with the yaml built from the current yaml editor value', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit('save-policy', 'APPEND');
    expect(wrapper.emitted('save')[0][0]).toMatchObject({ action: 'APPEND' });
  });

  it('disables the rules and bypass settings sections when the yaml pane has unparseable content', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit('update-yaml', 'not: valid: yaml: [');

    const disabledSections = wrapper.findAllComponents(DisabledSection);

    expect(disabledSections).toHaveLength(2);
    expect(disabledSections.at(0).props('disabled')).toBe(true);
    expect(disabledSections.at(1).props('disabled')).toBe(true);
  });

  describe('rules subtitle', () => {
    const createWrapperWithTitleSlot = (glFeatures) => {
      wrapper = shallowMountExtended(EditorComponent, {
        propsData: {
          existingPolicy: null,
          isCreating: false,
          isDeleting: false,
          isEditing: false,
          selectedPolicyType: 'dependency_firewall_policy',
        },
        provide: { glFeatures },
        stubs: {
          EditorLayout: { template: '<div><slot name="rules" /></div>' },
          DisabledSection: { template: '<div><slot name="title" /></div>' },
        },
      });
    };

    const findRulesSubtitle = () => wrapper.findComponent(SectionHeading).props('subtitle');

    describe('when dependencyFirewallAccess is disabled', () => {
      beforeEach(() => {
        createWrapperWithTitleSlot({
          dependencyFirewallPhase2: true,
          dependencyFirewallPackageVersion: true,
        });
      });

      it('counts three rule kinds', () => {
        expect(findRulesSubtitle()).toBe('Three kinds of rule, all in one policy.');
      });
    });

    describe('when dependencyFirewallPackageVersion is disabled', () => {
      beforeEach(() => {
        createWrapperWithTitleSlot({
          dependencyFirewallPhase2: true,
          dependencyFirewallAccess: true,
        });
      });

      it('counts three rule kinds', () => {
        expect(findRulesSubtitle()).toBe('Three kinds of rule, all in one policy.');
      });
    });

    describe('when dependencyFirewallAccess and dependencyFirewallPackageVersion are enabled', () => {
      beforeEach(() => {
        createWrapperWithTitleSlot({
          dependencyFirewallPhase2: true,
          dependencyFirewallAccess: true,
          dependencyFirewallPackageVersion: true,
        });
      });

      it('counts four rule kinds', () => {
        expect(findRulesSubtitle()).toBe('Four kinds of rule, all in one policy.');
      });
    });
  });

  it('renders bypass settings seeded from the default policy YAML', () => {
    createWrapper();
    expect(wrapper.findComponent(BypassSettings).props('bypassSettings')).toEqual({});
  });

  it('updates the yaml editor value when bypass settings change', async () => {
    createWrapper();
    await wrapper
      .findComponent(BypassSettings)
      .vm.$emit('changed', 'bypass_settings', { users: [{ id: 1 }] });

    expect(findEditorLayout().props('yamlEditorValue')).toContain('bypass_settings');
    expect(wrapper.findComponent(BypassSettings).props('bypassSettings')).toEqual({
      users: [{ id: 1 }],
    });
  });
});

describe('DependencyFirewallEditorComponent with an existing policy', () => {
  let wrapper;

  const existingPolicy = {
    name: 'Existing DFW policy',
    description: 'Blocks GPL licenses',
    enabled: true,
    enforcement_type: 'enforced',
    policy_scope: { projects: { excluding: [] } },
    rules: [{ type: 'license', denied: [{ name: 'GPL-3.0' }] }],
    bypass_settings: { users: [{ id: 7 }] },
  };

  const createWrapper = (glFeatures = { dependencyFirewallPhase2: true }) => {
    wrapper = shallowMountExtended(EditorComponent, {
      propsData: {
        existingPolicy,
        isCreating: false,
        isDeleting: false,
        isEditing: true,
        selectedPolicyType: 'dependency_firewall_policy',
      },
      provide: { glFeatures },
    });
  };

  const findEditorLayout = () => wrapper.findComponent(EditorLayout);

  it('seeds the yaml editor and rule list from the existing policy, not the defaults', () => {
    createWrapper();
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Existing DFW policy');
    expect(wrapper.findComponent(RuleList).props('rules')).toEqual([
      expect.objectContaining(existingPolicy.rules[0]),
    ]);
    expect(wrapper.findComponent(PolicyDetailsCard).props('enforcementType')).toBe('enforced');
    expect(wrapper.findComponent(BypassSettings).props('bypassSettings')).toEqual({
      users: [{ id: 7 }],
    });
  });

  it('still renders the legacy yaml-only view when the flag is disabled', () => {
    createWrapper({ dependencyFirewallPhase2: false });
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Existing DFW policy');
    expect(wrapper.findComponent(RuleList).exists()).toBe(false);
  });
});

describe('DependencyFirewallEditorComponent when dependencyFirewallPhase2 is disabled', () => {
  let wrapper;

  const createWrapper = () => {
    wrapper = shallowMountExtended(EditorComponent, {
      propsData: {
        existingPolicy: null,
        isCreating: false,
        isDeleting: false,
        isEditing: false,
        selectedPolicyType: 'dependency_firewall_policy',
      },
      provide: { glFeatures: { dependencyFirewallPhase2: false } },
    });
  };

  const findEditorLayout = () => wrapper.findComponent(EditorLayout);

  it('defaults to yaml-only mode, hiding the rule builder', () => {
    createWrapper();
    expect(findEditorLayout().props('defaultEditorMode')).toBe(EDITOR_MODE_YAML);
    expect(findEditorLayout().props('editorModes')).toEqual([
      expect.objectContaining({ value: EDITOR_MODE_YAML }),
    ]);
    expect(wrapper.findComponent(RuleList).exists()).toBe(false);
    expect(wrapper.findComponent(PolicyDetailsCard).exists()).toBe(false);
    expect(wrapper.findComponent(BypassSettings).exists()).toBe(false);
  });

  it('seeds the yaml editor with the legacy example policy', () => {
    createWrapper();
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Your policy name');
  });

  it('seeds a legacy template that validates against the schema', () => {
    createWrapper();
    const policy = safeLoad(findEditorLayout().props('yamlEditorValue'), { json: true });

    expect(policy).toValidateJsonSchema(validate);
  });
});

describe('DEFAULT_DEPENDENCY_FIREWALL_POLICY', () => {
  const parsed = () => safeLoad(DEFAULT_DEPENDENCY_FIREWALL_POLICY, { json: true });

  it('is intentionally invalid until a name and at least one rule are added', () => {
    // By design: an empty name and no rules guide the user to fill them in,
    // rather than showing pre-filled example data that looks real.
    // minLength/minItems in the schema surface that at save time.
    expect(parsed()).not.toValidateJsonSchema(validate);

    const policy = parsed().dependency_firewall_policy[0];
    expect(policy.name).toBe('');
    expect(policy.rules).toEqual([]);
  });

  it('rejects a risk_severity rule whose row has no severity selected yet', () => {
    const policy = parsed();
    policy.dependency_firewall_policy[0].name = 'A valid name';
    policy.dependency_firewall_policy[0].rules = [
      removeIdsFromPolicy(buildDefaultRuleForType(RULE_TYPE_RISK_SEVERITY)),
    ];

    expect(policy).not.toValidateJsonSchema(validate);
  });

  it('rejects a rule that omits both denied and allowed', () => {
    const policy = parsed();
    policy.dependency_firewall_policy[0].name = 'A valid name';
    policy.dependency_firewall_policy[0].rules = [{ type: 'license' }];

    expect(policy).not.toValidateJsonSchema(validate);
  });

  it('validates a fully filled-in policy covering all four rule types', () => {
    const policy = parsed();
    const firstPolicy = policy.dependency_firewall_policy[0];

    firstPolicy.name = 'A fully configured policy';
    firstPolicy.description = 'Covers license, vulnerability, malicious, and risk_severity rules';
    firstPolicy.rules = [
      { ...buildDefaultRuleForType(RULE_TYPE_LICENSE), denied: [{ name: 'MIT' }] },
      buildDefaultRuleForType(RULE_TYPE_MALICIOUS),
      {
        ...buildDefaultRuleForType(RULE_TYPE_RISK_SEVERITY),
        // The default row has no severity yet, which the schema rejects on purpose.
        denied: [{ severity: 'critical', threshold: 0 }],
      },
    ];
    firstPolicy.bypass_settings = { users: [{ id: 1 }], access_tokens: [{ id: 2 }] };
    policy.dependency_firewall_policy[0] = removeIdsFromPolicy(firstPolicy);

    expect(policy).toValidateJsonSchema(validate);
  });
});
