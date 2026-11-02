import {
  actionRuleBlockers,
  entryFieldBlockers,
  ruleConfigBlockers,
} from 'ee/policy_store/catalog/validation';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { RULES } from 'ee/policy_store/catalog/rules';

describe('ruleConfigBlockers', () => {
  const catalog = [
    {
      id: 'needy',
      label: 'Needy Rule',
      fields: [
        { key: 'code', label: 'Code block', required: true },
        { key: 'note', label: 'Note' },
      ],
    },
    {
      id: 'either',
      label: 'Either Rule',
      requireOneOf: ['names', 'tiers'],
      fields: [
        { key: 'names', label: 'Names' },
        { key: 'tiers', label: 'Tiers' },
      ],
    },
  ];

  it('returns nothing when every required field is filled', () => {
    expect(ruleConfigBlockers(catalog, ['needy'], { needy: { code: 'x' } })).toEqual([]);
  });

  it.each([undefined, '', '   '])('flags a required field left as %p', (code) => {
    expect(ruleConfigBlockers(catalog, ['needy'], { needy: { code } })).toEqual([
      'Needy Rule is missing Code block.',
    ]);
  });

  it('flags a missing config object the same as blank fields', () => {
    expect(ruleConfigBlockers(catalog, ['needy'])).toEqual(['Needy Rule is missing Code block.']);
  });

  it('does not flag optional fields', () => {
    expect(ruleConfigBlockers(catalog, ['needy'], { needy: { code: 'x', note: '' } })).toEqual([]);
  });

  it('flags a requireOneOf entry only when every alternative is blank', () => {
    expect(ruleConfigBlockers(catalog, ['either'], { either: { names: [], tiers: [] } })).toEqual([
      'Either Rule needs at least one of: Names, Tiers.',
    ]);
    expect(ruleConfigBlockers(catalog, ['either'], { either: { tiers: ['production'] } })).toEqual(
      [],
    );
  });

  it('produces no blockers for a rule the catalog does not know', () => {
    expect(ruleConfigBlockers(catalog, ['retired_rule'], {})).toEqual([]);
  });

  it('treats an object value with no keys as blank', () => {
    const objectCatalog = [
      {
        id: 'matrix',
        label: 'Matrix Rule',
        fields: [{ key: 'sla', label: 'SLA', required: true }],
      },
    ];

    expect(ruleConfigBlockers(objectCatalog, ['matrix'], { matrix: { sla: {} } })).toEqual([
      'Matrix Rule is missing SLA.',
    ]);
    expect(ruleConfigBlockers(objectCatalog, ['matrix'], { matrix: { sla: { high: 7 } } })).toEqual(
      [],
    );
  });

  it('ignores an empty requireOneOf declaration instead of blocking forever', () => {
    const emptyCatalog = [{ id: 'odd', label: 'Odd Rule', requireOneOf: [], fields: [] }];

    expect(ruleConfigBlockers(emptyCatalog, ['odd'], {})).toEqual([]);
  });

  it('does not HTML-escape labels, because the sentences render as text', () => {
    const quotedCatalog = [
      {
        id: 'quoted',
        label: "Ma'am's Rule",
        fields: [{ key: 'code', label: "Noms d'environnement", required: true }],
      },
    ];

    expect(ruleConfigBlockers(quotedCatalog, ['quoted'], {})).toEqual([
      "Ma'am's Rule is missing Noms d'environnement.",
    ]);
  });

  describe('setting validation expectations', () => {
    const blockers = (expectations) =>
      ruleConfigBlockers(RULES, ['setting_validation'], { setting_validation: { expectations } });

    it.each([undefined, []])('blocks saving with %p rows', (expectations) => {
      expect(blockers(expectations)).toEqual(['Setting validation is missing Project settings.']);
    });

    // "is missing Project settings" would point an author who has already picked one at the
    // wrong fix, so a half-filled row gets the more precise complaint — naming the setting,
    // since an unanswered boolean row and one answered `false` look identical on screen.
    it('names the setting of a touched but incomplete row', () => {
      expect(blockers([{ setting: 'secret_push_protection_enabled', expected: null }])).toEqual([
        'Setting validation: Secret push protection needs a required value.',
      ]);
    });

    it('falls back to the general complaint when the incomplete row has no setting', () => {
      expect(blockers([{ setting: '', expected: true }])).toEqual([
        'Setting validation: every selected setting needs a required value.',
      ]);
    });

    // The control clears the display for a value the catalog does not offer, which leaves
    // the row looking unanswered while the model still holds it. Without a blocker the
    // author re-saves a value the transpiler refuses, with nothing on screen to act on.
    it('blocks a value the setting does not let a policy require', () => {
      expect(
        blockers([{ setting: 'only_allow_merge_if_pipeline_succeeds', expected: false }]),
      ).toEqual([
        'Setting validation: Pipelines must succeed is set to a value a policy cannot require.',
      ]);
    });

    it('allows a value the setting does let a policy require', () => {
      expect(
        blockers([{ setting: 'only_allow_merge_if_pipeline_succeeds', expected: true }]),
      ).toEqual([]);
    });

    // Reachable once the served catalog drops or renames a setting a saved policy names.
    it('blocks a setting the catalog does not know, naming the stored id', () => {
      expect(blockers([{ setting: 'gone', expected: true }])).toEqual([
        'Setting validation: gone is not a setting a policy can govern.',
      ]);
    });

    // Each row persists as its own rule, so the same setting twice is a policy nothing can
    // satisfy rather than a redundant one.
    it('blocks the same setting pinned to contradictory values', () => {
      expect(
        blockers([
          { setting: 'secret_push_protection_enabled', expected: true },
          { setting: 'secret_push_protection_enabled', expected: false },
        ]),
      ).toEqual(['Setting validation: Secret push protection is pinned more than once.']);
    });

    // `blank()`, not a hand-rolled null check: a `multi` setting the served catalog brings
    // would otherwise persist an empty selection as a required value.
    it('treats an empty selection as no answer', () => {
      expect(blockers([{ setting: 'secret_push_protection_enabled', expected: [] }])).toEqual([
        'Setting validation: Secret push protection needs a required value.',
      ]);
    });

    it('leaves an optional expectations field unanswered rather than demanding a row', () => {
      const optionalCatalog = [
        {
          id: 'optional',
          label: 'Optional rule',
          fields: [
            { ...RULES.find(({ id }) => id === 'setting_validation').fields[0], required: false },
          ],
        },
      ];

      expect(ruleConfigBlockers(optionalCatalog, ['optional'], {})).toEqual([]);
    });

    it('ignores an untouched trailing row when a complete one exists', () => {
      expect(
        blockers([
          { setting: 'secret_push_protection_enabled', expected: true },
          { setting: '', expected: null },
        ]),
      ).toEqual([]);
    });

    // `false` is an answer, not an absence: a boolean setting required to be off would
    // otherwise be unsaveable.
    it('accepts false as a required value', () => {
      expect(blockers([{ setting: 'secret_push_protection_enabled', expected: false }])).toEqual(
        [],
      );
    });

    it('ignores a non-array value instead of reading rows off it', () => {
      expect(blockers('not rows')).toEqual(['Setting validation is missing Project settings.']);
    });

    // One complaint per save, in the order the checks run: a half-filled row is reported
    // before a duplicate further down, so a reorder of the checks fails here.
    it('reports the half-filled row ahead of a duplicate in a later row', () => {
      expect(
        blockers([
          { setting: 'secret_push_protection_enabled', expected: null },
          { setting: 'only_allow_merge_if_pipeline_succeeds', expected: true },
          { setting: 'only_allow_merge_if_pipeline_succeeds', expected: true },
        ]),
      ).toEqual(['Setting validation: Secret push protection needs a required value.']);
    });

    // A served catalog can describe a setting whose type enumerates nothing, which leaves
    // the row with no option to pick. Blocking beats throwing out of validation.
    it('blocks a setting whose type enumerates no value', () => {
      const field = RULES.find(({ id }) => id === 'setting_validation').fields[0];
      const openCatalog = [
        {
          id: 'open',
          label: 'Open rule',
          fields: [{ ...field, settings: { free_text: { id: 'free_text', name: 'Free text' } } }],
        },
      ];

      expect(
        ruleConfigBlockers(openCatalog, ['open'], {
          open: { expectations: [{ setting: 'free_text', expected: 'anything' }] },
        }),
      ).toEqual(['Open rule: Free text is set to a value a policy cannot require.']);
    });
  });

  describe('firstStatement declarations', () => {
    const regoCatalog = [
      {
        id: 'rego',
        label: 'Rego Rule',
        fields: [
          { key: 'code', label: 'Program', required: true, firstStatement: 'package governance' },
        ],
      },
    ];

    it('flags a program opening with a different statement', () => {
      expect(
        ruleConfigBlockers(regoCatalog, ['rego'], { rego: { code: 'package other\n\nallow' } }),
      ).toEqual(['Program in Rego Rule must open with package governance.']);
    });

    it('reads past comments and blank lines to find the first statement', () => {
      const code = '# header comment\n\n  package governance # trailing\nallow';

      expect(ruleConfigBlockers(regoCatalog, ['rego'], { rego: { code } })).toEqual([]);
    });

    it('reports only the missing-field blocker when the program is blank', () => {
      expect(ruleConfigBlockers(regoCatalog, ['rego'], { rego: { code: '' } })).toEqual([
        'Rego Rule is missing Program.',
      ]);
    });
  });

  describe('showIf declarations', () => {
    const conditionalCatalog = [
      {
        id: 'setting',
        label: 'Setting Rule',
        fields: [
          { key: 'setting', label: 'Setting' },
          {
            key: 'expected',
            label: 'Expected value',
            required: true,
            showIf: { key: 'setting', in: ['visibility'] },
          },
        ],
      },
    ];

    it('does not block save on a required field the config hides', () => {
      expect(ruleConfigBlockers(conditionalCatalog, ['setting'], { setting: {} })).toEqual([]);
      expect(
        ruleConfigBlockers(conditionalCatalog, ['setting'], { setting: { setting: 'other' } }),
      ).toEqual([]);
    });

    it('blocks save once the field is revealed and still blank', () => {
      expect(
        ruleConfigBlockers(conditionalCatalog, ['setting'], { setting: { setting: 'visibility' } }),
      ).toEqual(['Setting Rule is missing Expected value.']);
    });

    it('accepts the revealed field once it is filled', () => {
      expect(
        ruleConfigBlockers(conditionalCatalog, ['setting'], {
          setting: { setting: 'visibility', expected: 'private' },
        }),
      ).toEqual([]);
    });

    describe('with requireOneOf', () => {
      const eitherCatalog = [
        {
          id: 'either',
          label: 'Either Rule',
          requireOneOf: ['names', 'tiers'],
          fields: [
            { key: 'mode', label: 'Mode' },
            { key: 'names', label: 'Names', showIf: { key: 'mode', in: ['detailed'] } },
            { key: 'tiers', label: 'Tiers', showIf: { key: 'mode', in: ['detailed'] } },
          ],
        },
      ];

      it('skips the check when every alternative is hidden', () => {
        expect(ruleConfigBlockers(eitherCatalog, ['either'], { either: {} })).toEqual([]);
      });

      it('flags the visible alternatives once they are revealed', () => {
        expect(
          ruleConfigBlockers(eitherCatalog, ['either'], { either: { mode: 'detailed' } }),
        ).toEqual(['Either Rule needs at least one of: Names, Tiers.']);
      });

      // "needs at least one of: Names" is a list of one. Say what it means instead.
      it('falls back to the missing-field sentence when one alternative is reachable', () => {
        const mixedCatalog = [
          {
            ...eitherCatalog[0],
            fields: [
              { key: 'mode', label: 'Mode' },
              { key: 'names', label: 'Names' },
              { key: 'tiers', label: 'Tiers', showIf: { key: 'mode', in: ['detailed'] } },
            ],
          },
        ];

        expect(ruleConfigBlockers(mixedCatalog, ['either'], { either: {} })).toEqual([
          'Either Rule is missing Names.',
        ]);
      });

      it('does not repeat the required check when the sole alternative is required', () => {
        const requiredCatalog = [
          {
            ...eitherCatalog[0],
            requireOneOf: ['names'],
            fields: [{ key: 'names', label: 'Names', required: true }],
          },
        ];

        expect(ruleConfigBlockers(requiredCatalog, ['either'], { either: {} })).toEqual([
          'Either Rule is missing Names.',
        ]);
      });
    });
  });

  it('collects blockers across all selected rules in order', () => {
    expect(ruleConfigBlockers(catalog, ['needy', 'either'], {})).toEqual([
      'Needy Rule is missing Code block.',
      'Either Rule needs at least one of: Names, Tiers.',
    ]);
  });

  // Pins the live catalog's declarations so the store's actual requirements
  // (an empty Rego program cannot compile; the environment rule needs a name
  // or a tier) cannot be dropped silently.
  describe('with the real rules catalog', () => {
    it('blocks a custom rule without Rego', () => {
      expect(ruleConfigBlockers(RULES, ['custom'], { custom: { policy: '' } })).toEqual([
        'Custom Rule (Rego) is missing Rego policy definition.',
      ]);
    });

    it('blocks a custom rule whose program does not open with package governance', () => {
      expect(
        ruleConfigBlockers(RULES, ['custom'], { custom: { policy: 'package mine\n\nallow' } }),
      ).toEqual([
        'Rego policy definition in Custom Rule (Rego) must open with package governance.',
      ]);
    });

    it('accepts the shipped default template', () => {
      const custom = RULES.find(({ id }) => id === 'custom');
      const { default: template } = custom.fields.find(({ key }) => key === 'policy');

      // The default must satisfy the field's own requirements, or a freshly
      // added custom rule would be born blocked.
      expect(template).toEqual(expect.any(String));
      expect(ruleConfigBlockers(RULES, ['custom'], { custom: { policy: template } })).toEqual([]);
    });

    it('blocks an environment rule with neither names nor tiers', () => {
      expect(ruleConfigBlockers(RULES, ['environment'], { environment: {} })).toEqual([
        'Environment State needs at least one of: Environment names, Environment tiers.',
      ]);
    });

    it.each([{}, { windows: [] }])('blocks a calendar rule configured as %p', (calendar) => {
      expect(ruleConfigBlockers(RULES, ['calendar'], { calendar })).toEqual([
        'Freeze Window is missing Freeze windows.',
      ]);
    });

    it('accepts a calendar rule once a window is authored', () => {
      const windows = [
        {
          name: 'Year end',
          tiers: ['production'],
          starts_at: '2026-12-24T00:00:00Z',
          ends_at: '2027-01-02T00:00:00Z',
        },
      ];

      expect(ruleConfigBlockers(RULES, ['calendar'], { calendar: { windows } })).toEqual([]);
    });
  });
});

describe('actionRuleBlockers', () => {
  const actions = [
    { id: 'plain', label: 'Plain Action' },
    { id: 'borrower', label: 'Borrowing Action', requiresRule: 'supplier' },
  ];
  const rules = [{ id: 'supplier', label: 'Supplying Rule' }];
  const catalogs = { actions, rules };
  const REAL = { actions: ACTIONS, rules: RULES };

  it('accepts an action that declares no required rule', () => {
    expect(actionRuleBlockers(catalogs, ['plain'], [])).toEqual([]);
  });

  it('blocks an action whose required rule is not selected', () => {
    expect(actionRuleBlockers(catalogs, ['borrower'], ['other'])).toEqual([
      'Borrowing Action needs the Supplying Rule rule to supply its configuration.',
    ]);
  });

  it('accepts the action once its required rule is selected', () => {
    expect(actionRuleBlockers(catalogs, ['borrower'], ['other', 'supplier'])).toEqual([]);
  });

  it('names the raw rule id when the rule catalog does not carry it', () => {
    expect(actionRuleBlockers({ actions }, ['borrower'], [])).toEqual([
      'Borrowing Action needs the supplier rule to supply its configuration.',
    ]);
  });

  it('ignores an action the catalog does not know', () => {
    expect(actionRuleBlockers(catalogs, ['retired'], [])).toEqual([]);
  });

  describe('against the real catalogs', () => {
    it('blocks Set project setting without the setting validation rule', () => {
      expect(actionRuleBlockers(REAL, ['set_setting'], ['custom'])).toEqual([
        'Set project setting needs the Setting validation rule to supply its configuration.',
      ]);
    });

    it('accepts Set project setting alongside the setting validation rule', () => {
      expect(actionRuleBlockers(REAL, ['set_setting'], ['setting_validation'])).toEqual([]);
    });

    it('never blocks the two blocking actions, which carry their own fields', () => {
      expect(actionRuleBlockers(REAL, ['block', 'require_approval'], [])).toEqual([]);
    });
  });
});

describe('entryFieldBlockers', () => {
  const catalog = [
    {
      id: 'needy',
      label: 'Needy Rule',
      fields: [
        { key: 'code', label: 'Code block', required: true, firstStatement: 'package governance' },
        { key: 'note', label: 'Note', required: true },
      ],
    },
    {
      id: 'either',
      label: 'Either Rule',
      requireOneOf: ['names', 'tiers'],
      fields: [
        { key: 'names', label: 'Names' },
        { key: 'tiers', label: 'Tiers' },
      ],
    },
  ];

  it('keys each blocker by its entry and field', () => {
    expect(entryFieldBlockers(catalog, ['needy'], { needy: { note: 'ok' } })).toEqual({
      needy: { code: 'Needy Rule is missing Code block.' },
    });
  });

  it('reports every offending field of an entry', () => {
    expect(entryFieldBlockers(catalog, ['needy'], {})).toEqual({
      needy: {
        code: 'Needy Rule is missing Code block.',
        note: 'Needy Rule is missing Note.',
      },
    });
  });

  it('reports a first-statement violation against the field that carries it', () => {
    expect(
      entryFieldBlockers(catalog, ['needy'], { needy: { code: 'allow := true', note: 'ok' } }),
    ).toEqual({
      needy: { code: 'Code block in Needy Rule must open with package governance.' },
    });
  });

  it('omits entries with nothing wrong, and entries the catalog does not know', () => {
    const configs = { needy: { code: 'package governance', note: 'ok' } };

    expect(entryFieldBlockers(catalog, ['needy', 'retired_rule'], configs)).toEqual({});
  });

  it('leaves requireOneOf to the save button, since no single control owns it', () => {
    expect(entryFieldBlockers(catalog, ['either'], { either: { names: [], tiers: [] } })).toEqual(
      {},
    );
  });

  // The whole design rests on one source of truth feeding both surfaces, so this walks the
  // real catalog rather than a toy one: every inline sentence must also be in the save
  // button's list, and the only sentences the list keeps to itself are the requireOneOf ones.
  describe('parity with ruleConfigBlockers', () => {
    it.each(RULES.map((rule) => [rule.id, rule]))('%s', (id, rule) => {
      const inline = Object.values(entryFieldBlockers(RULES, [id], {})[id] ?? {});
      const listed = ruleConfigBlockers(RULES, [id], {});

      expect(listed).toEqual(expect.arrayContaining(inline));

      const onlyListed = listed.filter((message) => !inline.includes(message));
      const requireOneOf = rule.requireOneOf ?? [];

      expect(onlyListed).toHaveLength(requireOneOf.length ? 1 : 0);
    });

    it('covers a field only reachable once a sibling reveals it', () => {
      const conditional = [
        {
          id: 'gated',
          label: 'Gated Rule',
          fields: [
            { key: 'mode', label: 'Mode' },
            {
              key: 'detail',
              label: 'Detail',
              required: true,
              showIf: { key: 'mode', in: ['strict'] },
            },
          ],
        },
      ];

      expect(entryFieldBlockers(conditional, ['gated'], { gated: {} })).toEqual({});
      expect(entryFieldBlockers(conditional, ['gated'], { gated: { mode: 'strict' } })).toEqual({
        gated: { detail: 'Gated Rule is missing Detail.' },
      });
      expect(ruleConfigBlockers(conditional, ['gated'], { gated: { mode: 'strict' } })).toEqual([
        'Gated Rule is missing Detail.',
      ]);
    });
  });
});
