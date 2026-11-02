import {
  deserializePolicyData,
  deserializeScope,
  emptyPolicyData,
  serializePolicyData,
  serializePolicyParams,
  serializeScope,
} from 'ee/policy_store/components/editor/serializer';

// No shipped catalog entry declares `showIf` yet, so the hidden-field behaviour is
// exercised against a stand-in entry rather than waiting on its first consumer.
jest.mock('ee/policy_store/catalog/rules', () => {
  const actual = jest.requireActual('ee/policy_store/catalog/rules');

  return {
    ...actual,
    RULES: [
      ...actual.RULES,
      {
        id: 'conditional',
        fields: [
          { key: 'mode', type: 'select', label: 'Mode' },
          {
            key: 'branches',
            type: 'text_list',
            label: 'Branches',
            showIf: { key: 'mode', in: ['scoped'] },
          },
        ],
      },
    ],
  };
});

jest.mock('ee/policy_store/catalog/actions', () => {
  const actual = jest.requireActual('ee/policy_store/catalog/actions');

  return {
    ...actual,
    ACTIONS: [
      ...actual.ACTIONS,
      {
        id: 'conditional_action',
        fields: [
          { key: 'mode', type: 'select', label: 'Mode' },
          {
            key: 'reviewers',
            type: 'text_list',
            label: 'Reviewers',
            showIf: { key: 'mode', in: ['scoped'] },
          },
        ],
      },
    ],
  };
});

describe('policy data serializer', () => {
  const formState = {
    trigger: 'deployment_requested',
    triggerConfig: {},
    rules: ['custom', 'environment'],
    ruleConfigs: {
      custom: { policy: 'package governance' },
      environment: { names: ['production'] },
    },
    actions: ['require_approval'],
    actionConfigs: { require_approval: { roles: ['maintainer'] } },
  };

  describe('serializePolicyData', () => {
    it('puts the Rego program in `value` directly, which is where the gate reads it', () => {
      const { rules } = serializePolicyData(formState);

      expect(rules[0]).toEqual({ type: 'custom', value: 'package governance' });
    });

    it('puts a typed rule config in `value` as an object', () => {
      const { rules } = serializePolicyData(formState);

      expect(rules[1]).toEqual({ type: 'environment', value: { names: ['production'] } });
    });

    it('drops an all-blank freeze window but keeps a partially filled one', () => {
      const { rules } = serializePolicyData({
        trigger: 'deployment_requested',
        rules: ['calendar'],
        ruleConfigs: {
          calendar: {
            windows: [
              { name: '', tiers: [], starts_at: '', ends_at: '' },
              { name: 'eoq', tiers: [], starts_at: '', ends_at: '' },
            ],
          },
        },
      });

      expect(rules[0]).toEqual({
        type: 'calendar',
        value: { windows: [{ name: 'eoq', tiers: [], starts_at: '', ends_at: '' }] },
      });
    });

    // The transpiler de-duplicates windows before compiling, so a duplicate
    // kept here would show on the detail page as a window the program does
    // not separately carry.
    it('drops a duplicate freeze window, ignoring the order tiers were picked in', () => {
      const window = {
        name: 'eoq',
        tiers: ['production', 'staging'],
        starts_at: '2026-12-24T00:00:00Z',
        ends_at: '2027-01-02T00:00:00Z',
      };
      const { rules } = serializePolicyData({
        trigger: 'deployment_requested',
        rules: ['calendar'],
        ruleConfigs: {
          calendar: {
            windows: [window, { ...window, tiers: ['staging', 'production'] }],
          },
        },
      });

      expect(rules[0].value.windows).toEqual([window]);
    });

    it('keeps windows that differ only by one bound', () => {
      const window = {
        name: 'eoq',
        tiers: ['production'],
        starts_at: '2026-12-24T00:00:00Z',
        ends_at: '2027-01-02T00:00:00Z',
      };
      const later = { ...window, ends_at: '2027-01-03T00:00:00Z' };
      const { rules } = serializePolicyData({
        trigger: 'deployment_requested',
        rules: ['calendar'],
        ruleConfigs: { calendar: { windows: [window, later] } },
      });

      expect(rules[0].value.windows).toEqual([window, later]);
    });

    it('puts an action config in `value`, the only config key the API persists', () => {
      const { actions } = serializePolicyData(formState);

      expect(actions).toEqual([{ type: 'require_approval', value: { roles: ['maintainer'] } }]);
    });

    it('exposes the trigger as trigger_type', () => {
      expect(serializePolicyData(formState).trigger_type).toBe('deployment_requested');
    });

    it('serializes an empty policy without throwing', () => {
      expect(serializePolicyData(emptyPolicyData())).toEqual({
        trigger_type: null,
        rules: [],
        actions: [],
      });
    });

    it('serializes with no argument at all', () => {
      expect(serializePolicyData()).toEqual({
        trigger_type: null,
        rules: [],
        actions: [],
      });
    });

    it('defaults a missing rule config to an empty value', () => {
      const { rules } = serializePolicyData({ rules: ['environment'] });

      expect(rules).toEqual([{ type: 'environment', value: {} }]);
    });

    it('defaults a missing action config to an empty value', () => {
      const { actions } = serializePolicyData({ actions: ['block'] });

      expect(actions).toEqual([{ type: 'block', value: {} }]);
    });

    it('drops a value the config still holds for a hidden field', () => {
      const { rules } = serializePolicyData({
        rules: ['conditional'],
        ruleConfigs: { conditional: { mode: 'all', branches: ['main'] } },
      });

      expect(rules).toEqual([{ type: 'conditional', value: { mode: 'all' } }]);
    });

    it('keeps that value once the sibling reveals the field again', () => {
      const { rules } = serializePolicyData({
        rules: ['conditional'],
        ruleConfigs: { conditional: { mode: 'scoped', branches: ['main'] } },
      });

      expect(rules).toEqual([
        { type: 'conditional', value: { mode: 'scoped', branches: ['main'] } },
      ]);
    });

    it('drops a hidden field from an action config too', () => {
      const { actions } = serializePolicyData({
        actions: ['conditional_action'],
        actionConfigs: { conditional_action: { mode: 'all', reviewers: ['owners'] } },
      });

      expect(actions).toEqual([{ type: 'conditional_action', value: { mode: 'all' } }]);
    });

    it('keeps an action field its sibling reveals', () => {
      const { actions } = serializePolicyData({
        actions: ['conditional_action'],
        actionConfigs: { conditional_action: { mode: 'scoped', reviewers: ['owners'] } },
      });

      expect(actions).toEqual([
        { type: 'conditional_action', value: { mode: 'scoped', reviewers: ['owners'] } },
      ]);
    });

    it('defaults a missing Rego program to an empty string, not undefined', () => {
      const { rules } = serializePolicyData({ rules: ['custom'] });

      expect(rules).toEqual([{ type: 'custom', value: '' }]);
    });
  });

  describe('setting validation expectations', () => {
    const expectations = [
      { setting: 'secret_push_protection_enabled', expected: true },
      { setting: 'only_allow_merge_if_pipeline_succeeds', expected: false },
    ];
    // A row calls the required value `expected`, matching the word the violation detail
    // reports; it is persisted under `value`, which is the key the gem's emitter reads.
    const persisted = [
      { setting: 'secret_push_protection_enabled', value: true },
      { setting: 'only_allow_merge_if_pipeline_succeeds', value: false },
    ];
    const settingState = {
      trigger: 'deployment_requested',
      triggerConfig: {},
      rules: ['setting_validation'],
      ruleConfigs: { setting_validation: { expectations } },
      actions: [],
      actionConfigs: {},
    };

    // The API takes one rule per pair, so the wizard's single entry fans out.
    it('persists one rule per row', () => {
      expect(serializePolicyData(settingState).rules).toEqual([
        { type: 'setting_validation', value: persisted[0] },
        { type: 'setting_validation', value: persisted[1] },
      ]);
    });

    it.each([
      ['no setting', { setting: '', expected: true }],
      ['no value', { setting: 'secret_push_protection_enabled', expected: null }],
    ])('drops a row with %s', (_, row) => {
      const { rules } = serializePolicyData({
        rules: ['setting_validation'],
        ruleConfigs: { setting_validation: { expectations: [row] } },
      });

      expect(rules).toEqual([]);
    });

    it('drops the rule entirely when nothing is authored', () => {
      expect(serializePolicyData({ rules: ['setting_validation'] }).rules).toEqual([]);
    });

    // Every other rule type is kept once; these are collected back into the one entry the
    // wizard edits instead.
    it('collects the persisted rules back into a single entry', () => {
      const { rules, ruleConfigs } = deserializePolicyData({
        rules: [
          { type: 'setting_validation', value: persisted[0] },
          { type: 'custom', value: 'package governance' },
          { type: 'setting_validation', value: persisted[1] },
        ],
      });

      // The collapsed entry keeps the position of the first pair, because `rules` order is
      // the wizard's render order: appending it would reorder the author's rules on reload.
      expect(rules).toEqual(['setting_validation', 'custom']);
      expect(ruleConfigs.setting_validation).toEqual({ expectations });
    });

    it('round trips the rule order', () => {
      const ordered = {
        rules: ['setting_validation', 'custom'],
        ruleConfigs: {
          setting_validation: { expectations },
          custom: { code: 'package governance' },
        },
      };

      expect(deserializePolicyData(serializePolicyData(ordered)).rules).toEqual(ordered.rules);
    });

    it('tolerates a persisted rule with no value', () => {
      const { ruleConfigs } = deserializePolicyData({ rules: [{ type: 'setting_validation' }] });

      expect(ruleConfigs.setting_validation).toEqual({
        expectations: [{ setting: '', expected: null }],
      });
    });

    it('round trips the form state', () => {
      expect(deserializePolicyData(serializePolicyData(settingState))).toEqual(settingState);
    });
  });

  describe('round trip', () => {
    it('returns the original form state', () => {
      expect(deserializePolicyData(serializePolicyData(formState))).toEqual(formState);
    });

    it('survives a policy with no rules or actions', () => {
      const empty = emptyPolicyData();

      expect(deserializePolicyData(serializePolicyData(empty))).toEqual(empty);
    });
  });

  describe('deserializePolicyData', () => {
    it('drops value keys the catalog no longer declares for the rule', () => {
      const { ruleConfigs } = deserializePolicyData({
        trigger_type: 'deployment_requested',
        rules: [
          {
            type: 'calendar',
            value: { windowStart: '2026-12-20T00:00:00Z', recurring: 'weekly', windows: [] },
          },
        ],
      });

      expect(ruleConfigs.calendar).toEqual({ windows: [] });
    });

    it('keeps the whole value for a rule type the catalog does not know', () => {
      const { ruleConfigs } = deserializePolicyData({
        trigger_type: 'deployment_requested',
        rules: [{ type: 'brand_new', value: { anything: 'goes' } }],
      });

      expect(ruleConfigs.brand_new).toEqual({ anything: 'goes' });
    });

    it('returns empty form state for a policy with nothing set', () => {
      expect(deserializePolicyData({})).toEqual(emptyPolicyData());
    });

    it('returns empty form state with no argument', () => {
      expect(deserializePolicyData()).toEqual(emptyPolicyData());
    });

    it('reads the persisted trigger_type back as the selected trigger', () => {
      expect(deserializePolicyData({ trigger_type: 'deployment_requested' }).trigger).toBe(
        'deployment_requested',
      );
    });

    it('unwraps the Rego program back into the code field', () => {
      const { ruleConfigs } = deserializePolicyData({
        rules: [{ type: 'custom', value: 'package foo' }],
      });

      expect(ruleConfigs.custom).toEqual({ policy: 'package foo' });
    });

    it('tolerates a Rego rule with no value', () => {
      const { ruleConfigs } = deserializePolicyData({ rules: [{ type: 'custom' }] });

      expect(ruleConfigs.custom).toEqual({ policy: '' });
    });

    it('tolerates an action with no value', () => {
      const { actionConfigs } = deserializePolicyData({ actions: [{ type: 'block' }] });

      expect(actionConfigs.block).toEqual({});
    });

    it('keeps the first occurrence of a duplicated rule type', () => {
      const { rules, ruleConfigs } = deserializePolicyData({
        rules: [
          { type: 'custom', value: 'package first' },
          { type: 'custom', value: 'package second' },
        ],
      });

      expect(rules).toEqual(['custom']);
      expect(ruleConfigs).toEqual({ custom: { policy: 'package first' } });
    });

    it('keeps the first occurrence of a duplicated action type', () => {
      const { actions, actionConfigs } = deserializePolicyData({
        actions: [
          { type: 'require_approval', value: { roles: ['developer'] } },
          { type: 'require_approval', value: { roles: ['owner'] } },
        ],
      });

      expect(actions).toEqual(['require_approval']);
      expect(actionConfigs).toEqual({ require_approval: { roles: ['developer'] } });
    });

    it('drops action keys the catalog no longer declares', () => {
      const { actionConfigs } = deserializePolicyData({
        actions: [
          {
            type: 'block',
            value: { message: 'No deploys', blockMessage: 'Retired', overrideGroups: 'sec-leads' },
          },
        ],
      });

      expect(actionConfigs.block).toEqual({ message: 'No deploys' });
    });

    // Neither action declares fields, so every stored key under one is a key the catalog
    // never promised. Reading one back would re-persist it on the next save.
    it.each(['log_audit_trail', 'set_setting'])(
      'drops all config for %s, a catalog action that declares no fields',
      (type) => {
        const { actionConfigs } = deserializePolicyData({
          actions: [{ type, value: { smuggled: 'via the API' } }],
        });

        expect(actionConfigs[type]).toEqual({});
      },
    );

    it('keeps the value of an action the catalog does not know at all', () => {
      const { actionConfigs } = deserializePolicyData({
        actions: [{ type: 'not_in_the_catalog', value: { kept: true } }],
      });

      expect(actionConfigs.not_in_the_catalog).toEqual({ kept: true });
    });
  });

  describe('serializeScope', () => {
    const projects = [
      { id: 'gid://gitlab/Project/7', fullPath: 'flightjs/one' },
      { id: 'gid://gitlab/Project/9', fullPath: 'flightjs/two' },
    ];

    it('serializes "all projects" with no exclusions to an empty scope', () => {
      expect(serializeScope({ mode: 'all', projects: [], exclusions: [] })).toEqual({});
    });

    it('serializes with no argument to an empty scope', () => {
      expect(serializeScope()).toEqual({});
    });

    it('serializes specific projects to a plain list of numeric ids', () => {
      expect(serializeScope({ mode: 'specific', projects, exclusions: [] })).toEqual({
        projects: { including: [7, 9] },
      });
    });

    it('serializes exclusions independently of the mode', () => {
      expect(serializeScope({ mode: 'all', projects: [], exclusions: projects })).toEqual({
        projects: { excluding: [7, 9] },
      });
    });

    it('ignores selected projects left over from a previous "specific" choice', () => {
      expect(serializeScope({ mode: 'all', projects, exclusions: [] })).toEqual({});
    });
  });

  describe('deserializeScope', () => {
    it('reads an empty scope as "all projects"', () => {
      expect(deserializeScope({})).toEqual({ mode: 'all', projects: [], exclusions: [] });
    });

    it('reads a missing scope as "all projects"', () => {
      expect(deserializeScope(undefined)).toEqual({ mode: 'all', projects: [], exclusions: [] });
    });

    it('reads included project ids back as "specific" with GraphQL id stubs', () => {
      expect(deserializeScope({ projects: { including: [7, 9] } })).toEqual({
        mode: 'specific',
        projects: [{ id: 'gid://gitlab/Project/7' }, { id: 'gid://gitlab/Project/9' }],
        exclusions: [],
      });
    });

    it('reads `{ id }` hash entries the same as bare ids', () => {
      expect(deserializeScope({ projects: { including: [{ id: 7 }] } })).toEqual({
        mode: 'specific',
        projects: [{ id: 'gid://gitlab/Project/7' }],
        exclusions: [],
      });
    });

    it('reads excluded project ids back as exclusions, skipping typed entries', () => {
      expect(deserializeScope({ projects: { excluding: [7, { type: 'personal' }] } })).toEqual({
        mode: 'all',
        projects: [],
        exclusions: [{ id: 'gid://gitlab/Project/7' }],
      });
    });
  });

  describe('serializePolicyParams', () => {
    it('builds the full request params for the write endpoints', () => {
      expect(
        serializePolicyParams({
          name: 'Production gate',
          description: 'Gates production deployments',
          mode: 'enforce',
          scope: {
            mode: 'specific',
            projects: [{ id: 'gid://gitlab/Project/7' }],
            exclusions: [],
          },
          policyData: formState,
        }),
      ).toEqual({
        name: 'Production gate',
        description: 'Gates production deployments',
        mode: 'enforce',
        policy_scope: { projects: { including: [7] } },
        trigger_type: 'deployment_requested',
        rules: [
          { type: 'custom', value: 'package governance' },
          { type: 'environment', value: { names: ['production'] } },
        ],
        actions: [{ type: 'require_approval', value: { roles: ['maintainer'] } }],
      });
    });

    it('trims surrounding whitespace from the name', () => {
      expect(
        serializePolicyParams({
          name: '  Production gate ',
          description: '',
          mode: 'enforce',
          scope: { mode: 'all', projects: [], exclusions: [] },
          policyData: formState,
        }),
      ).toMatchObject({ name: 'Production gate' });
    });
  });
});
