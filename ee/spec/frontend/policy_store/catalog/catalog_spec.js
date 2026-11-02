import {
  FIELD_TYPES,
  FIELD_TYPE_CHECKBOX,
  FIELD_TYPE_CODE,
  FIELD_TYPE_FREEZE_WINDOWS,
  FIELD_TYPE_MULTI_BADGE,
  FIELD_TYPE_NUMBER,
  FIELD_TYPE_SEARCHABLE_SELECT,
  FIELD_TYPE_SELECT,
  FIELD_TYPE_SETTING_EXPECTATIONS,
  FIELD_TYPE_TEXT,
  FIELD_TYPE_TEXTAREA,
  FIELD_TYPE_TEXT_LIST,
} from 'ee/policy_store/components/editor/constants';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { CATEGORY_LABELS, CATEGORY_ORDER } from 'ee/policy_store/catalog/categories';
import { actionAllowedFor } from 'ee/policy_store/catalog/compatibility';
import { REGO_TEMPLATES } from 'ee/policy_store/catalog/rego_templates';
import { firstStatement } from 'ee/policy_store/catalog/validation';
import { RULES } from 'ee/policy_store/catalog/rules';
import { RECORDED_TRIGGERS, TRIGGERS, TRIGGER_KIND_EVENT } from 'ee/policy_store/catalog/triggers';

// Field types holding a single value, so `showIf.in.includes(...)` can match them.
const SCALAR_FIELD_TYPES = [
  FIELD_TYPE_TEXT,
  FIELD_TYPE_SELECT,
  FIELD_TYPE_SEARCHABLE_SELECT,
  FIELD_TYPE_CHECKBOX,
  FIELD_TYPE_NUMBER,
];

// How each field type's control says "no answer": `undefined`, or an empty '' / [] / false.
// Every FIELD_TYPES member must appear in exactly one of these, which is asserted below,
// so a new control cannot be added without deciding which it is.
const FIELD_TYPES_CLEARING_TO_UNDEFINED = [FIELD_TYPE_NUMBER];
const FIELD_TYPES_CLEARING_TO_EMPTY = [
  FIELD_TYPE_SETTING_EXPECTATIONS,
  FIELD_TYPE_TEXT,
  FIELD_TYPE_TEXT_LIST,
  FIELD_TYPE_TEXTAREA,
  FIELD_TYPE_SELECT,
  FIELD_TYPE_SEARCHABLE_SELECT,
  FIELD_TYPE_CHECKBOX,
  FIELD_TYPE_MULTI_BADGE,
  FIELD_TYPE_FREEZE_WINDOWS,
  FIELD_TYPE_CODE,
];

const siblingOf = (entry, field) =>
  entry.fields.find(({ key }) => key === field.showIf.key && key !== field.key);

// The catalog is data, and a typo in it fails silently: ConfigWrapper renders nothing for an
// unknown field `type`, and a duplicated id shadows an entry. These assertions are the only
// thing standing between a mistyped catalog entry and a control that quietly disappears.
describe('policy store catalog', () => {
  // The default guard below is only as good as this partition: an unclassified new field
  // type would slip past it, taking the save/reload bug with it.
  it('classifies every field type by what its control clears to', () => {
    expect([...FIELD_TYPES_CLEARING_TO_UNDEFINED, ...FIELD_TYPES_CLEARING_TO_EMPTY].sort()).toEqual(
      [...FIELD_TYPES].sort(),
    );
  });

  describe.each([
    ['triggers', TRIGGERS],
    ['recorded triggers', RECORDED_TRIGGERS],
    ['rules', RULES],
    ['actions', ACTIONS],
  ])('%s', (name, entries) => {
    it('is not empty', () => {
      expect(entries.length).toBeGreaterThan(0);
    });

    it('gives every entry a unique id', () => {
      const ids = entries.map(({ id }) => id);

      expect(new Set(ids).size).toBe(ids.length);
    });

    it('gives every entry an id, label, description, icon, category and fields', () => {
      entries.forEach((entry) => {
        expect(entry).toMatchObject({
          id: expect.any(String),
          label: expect.any(String),
          description: expect.any(String),
          icon: expect.any(String),
          category: expect.any(String),
          fields: expect.any(Array),
        });
      });
    });

    it('gives every field a unique key within its entry', () => {
      entries.forEach(({ fields }) => {
        const keys = fields.map(({ key }) => key);

        expect(new Set(keys).size).toBe(keys.length);
      });
    });

    // The serializer picks and omits config keys by name through lodash, which reads a
    // key containing a dot as a deep path. A field keyed `a.b` would restructure the
    // stored value instead of being carried across, and one named after an
    // Object.prototype member would be fabricated onto a config that never had it.
    it('keys every field with a plain identifier', () => {
      const badKeys = entries
        .flatMap(({ fields }) => fields.map(({ key }) => key))
        .filter((key) => !/^[A-Za-z][A-Za-z0-9_]*$/.test(key) || key in Object.prototype);

      expect(badKeys).toEqual([]);
    });

    // A mistyped key here would make the requirement unsatisfiable: the config
    // never carries the key, so validation.js would block saving forever.
    it('points requireOneOf only at keys the entry declares as fields', () => {
      const unknownKeys = entries.flatMap(({ fields, requireOneOf }) =>
        (requireOneOf ?? []).filter((key) => !fields.some((field) => field.key === key)),
      );

      expect(unknownKeys).toEqual([]);
    });

    it('never declares requireOneOf as an empty set', () => {
      const emptyDeclarations = entries.filter(
        ({ requireOneOf }) => requireOneOf && requireOneOf.length === 0,
      );

      expect(emptyDeclarations).toEqual([]);
    });

    // NumberField clears itself to `undefined`, and a key held as `undefined` is dropped by
    // JSON.stringify on save. A default on it would survive being cleared only until the
    // policy is saved and reloaded, then quietly come back. Until a cleared value has a wire
    // representation the backend reads as absent, this type cannot carry one.
    it('declares no default on a field type that clears itself to undefined', () => {
      const withDefaults = entries.flatMap(({ id, fields }) =>
        fields
          .filter(
            ({ type, default: value }) =>
              FIELD_TYPES_CLEARING_TO_UNDEFINED.includes(type) && value !== undefined,
          )
          .map((field) => `${id}.${field.key}`),
      );

      expect(withDefaults).toEqual([]);
    });

    // No catalog entry declares a showIf yet, so the assertions over real data below pass
    // vacuously. Each guard is also run against inline fixtures, to prove that it fires on
    // the defect it names and stays quiet on a sound declaration.
    describe('showIf declarations', () => {
      const conditionals = entries.flatMap((entry) =>
        entry.fields
          .filter(({ showIf }) => showIf)
          .map((field) => ({ entry, field, sibling: siblingOf(entry, field) })),
      );

      const brokenBy = (guard) =>
        conditionals.filter(guard).map(({ entry, field }) => `${entry.id}.${field.key}`);

      it('names a sibling the same entry declares', () => {
        const guard = ({ sibling }) => !sibling;
        // A showIf naming its own field resolves to no sibling, which is why siblingOf
        // excludes it.
        const selfReferential = { key: 'a', showIf: { key: 'a', in: ['x'] } };

        expect(brokenBy(guard)).toEqual([]);
        expect(guard({ sibling: siblingOf({ fields: [selfReferential] }, selfReferential) })).toBe(
          true,
        );
        expect(guard({ sibling: { key: 'a' } })).toBe(false);
      });

      it('lists at least one value to match', () => {
        const guard = ({ field }) =>
          !Array.isArray(field.showIf.in) || field.showIf.in.length === 0;

        expect(brokenBy(guard)).toEqual([]);
        expect(guard({ field: { showIf: { in: [] } } })).toBe(true);
        // No `in` at all: visibleFields would throw rather than hide the field.
        expect(guard({ field: { showIf: { key: 'a' } } })).toBe(true);
        expect(guard({ field: { showIf: { in: ['x'] } } })).toBe(false);
      });

      // visibleFields matches by identity, so an array-valued sibling never compares equal
      // to anything in `in`.
      it('names a sibling whose value is a scalar', () => {
        const guard = ({ sibling }) => !SCALAR_FIELD_TYPES.includes(sibling?.type);

        expect(brokenBy(guard)).toEqual([]);
        expect(guard({ sibling: { type: FIELD_TYPE_MULTI_BADGE } })).toBe(true);
        expect(guard({ sibling: { type: FIELD_TYPE_SELECT } })).toBe(false);
      });

      // visibleFields is a single pass, so a sibling that is itself conditional would be
      // read from a value the author may never have seen.
      it('names a sibling that is not itself conditional', () => {
        const guard = ({ sibling }) => Boolean(sibling?.showIf);

        expect(brokenBy(guard)).toEqual([]);
        expect(guard({ sibling: { showIf: { key: 'c', in: ['y'] } } })).toBe(true);
        expect(guard({ sibling: { type: FIELD_TYPE_TEXT } })).toBe(false);
      });

      // CheckboxField renders `value ?? field.default ?? false`, so an undefaulted checkbox
      // shows unchecked while its value stays undefined, and a showIf on [false] would never
      // match until the author toggled the box twice.
      it('names a checkbox sibling that declares a default', () => {
        const guard = ({ sibling }) =>
          sibling?.type === FIELD_TYPE_CHECKBOX && sibling.default === undefined;

        expect(brokenBy(guard)).toEqual([]);
        expect(guard({ sibling: { type: FIELD_TYPE_CHECKBOX } })).toBe(true);
        expect(guard({ sibling: { type: FIELD_TYPE_CHECKBOX, default: true } })).toBe(false);
      });

      // A value absent from the sibling's own options can never be selected.
      it('matches only values the sibling can actually take', () => {
        const unmatchable = ({ field, sibling }) =>
          sibling?.options?.length
            ? (field.showIf.in ?? []).filter(
                (value) => !sibling.options.some(({ id }) => id === value),
              )
            : [];
        const unreachable = conditionals.flatMap(({ entry, field, sibling }) =>
          unmatchable({ field, sibling }).map(
            (value) => `${entry.id}.${field.key} -> ${sibling.key}=${value}`,
          ),
        );

        expect(unreachable).toEqual([]);
        expect(
          unmatchable({
            field: { showIf: { in: ['absent'] } },
            sibling: { options: [{ id: 'present' }] },
          }),
        ).toEqual(['absent']);
      });
    });

    // Category ids drive the drawer's grouping and sort order; the label map supplies
    // the displayed text. An id outside the order would sort unpredictably, and one
    // without a label would render as its raw id.
    it('gives every entry a category from the declared order, with a label', () => {
      entries.forEach(({ category }) => {
        expect(CATEGORY_ORDER).toContain(category);
        expect(CATEGORY_LABELS[category]).toEqual(expect.any(String));
      });
    });
  });

  // Flattened across all three catalogs: the field contract is the same wherever a field appears,
  // and triggers declare no fields, so asserting per-catalog would leave that block empty.
  describe('fields', () => {
    const allFields = [...TRIGGERS, ...RULES, ...ACTIONS].flatMap(({ fields }) => fields);

    it('has fields to check', () => {
      expect(allFields.length).toBeGreaterThan(0);
    });

    it('only uses field types ConfigWrapper can render', () => {
      allFields.forEach((field) => {
        expect(FIELD_TYPES).toContain(field.type);
      });
    });

    it('gives every field a key and a label', () => {
      allFields.forEach((field) => {
        expect(field).toMatchObject({ key: expect.any(String), label: expect.any(String) });
      });
    });

    it('gives every option-carrying field non-empty { id, label } options', () => {
      const withOptions = allFields.filter(({ type }) =>
        [
          FIELD_TYPE_SELECT,
          FIELD_TYPE_SEARCHABLE_SELECT,
          FIELD_TYPE_MULTI_BADGE,
          FIELD_TYPE_FREEZE_WINDOWS,
        ].includes(type),
      );

      expect(withOptions.length).toBeGreaterThan(0);

      withOptions.forEach(({ options }) => {
        expect(options.length).toBeGreaterThan(0);
        options.forEach((option) => {
          expect(option).toMatchObject({ id: expect.any(String), label: expect.any(String) });
        });
      });
    });

    // NumberField forwards min and max but no step, so a fractional bound makes every
    // integer a step mismatch, a non-finite bound is ignored and a reversed pair breaks the
    // spinner. None of the three blocks a save, so bounds must be whole numbers or omitted.
    it('declares no fractional, non-finite or reversed bounds on a number field', () => {
      const guard = ({ min, max }) =>
        [min, max].some((bound) => bound !== undefined && !Number.isInteger(bound)) || min > max;
      const badBounds = [...TRIGGERS, ...RULES, ...ACTIONS].flatMap(({ id, fields }) =>
        fields
          .filter(({ type }) => type === FIELD_TYPE_NUMBER)
          .filter(guard)
          .map(({ key }) => `${id}.${key}`),
      );

      expect(badBounds).toEqual([]);

      // No catalog entry declares a number field yet, so the assertion above is vacuous.
      expect(guard({ min: 10, max: 1 })).toBe(true);
      expect(guard({ min: 0.5, max: 10 })).toBe(true);
      expect(guard({ min: 1, max: NaN })).toBe(true);
      expect(guard({ min: 1, max: Infinity })).toBe(true);
      expect(guard({ min: '1', max: 10 })).toBe(true);
      expect(guard({ min: 1, max: null })).toBe(true);
      expect(guard({ min: 1, max: 10 })).toBe(false);
      expect(guard({ min: -10, max: -1 })).toBe(false);
      expect(guard({ min: undefined, max: undefined })).toBe(false);
    });
  });

  describe('categories', () => {
    // The drawer renders its groups in exactly this sequence; reordering is a UX change
    // and should fail a test rather than slip through. Literals rather than the
    // imported constants, so a mistyped constant value cannot agree with itself.
    it('presents the groups in this exact order', () => {
      expect(CATEGORY_ORDER).toEqual([
        'enforcement',
        'advanced',
        'general',
        'deployment',
        'security',
        'process',
        'ai',
        'ci_cd',
        'code',
        'compliance',
        'access',
        'integrations',
      ]);
    });

    it('gives every labelled category a place in the order', () => {
      Object.keys(CATEGORY_LABELS).forEach((category) => {
        expect(CATEGORY_ORDER).toContain(category);
      });
    });
  });

  describe('scope', () => {
    it('ships the deployment gate triggers and the project lifecycle triggers', () => {
      // All six are Gitlab::PolicyStore::Triggers::ALL in the gitlab-policy-store gem, and
      // are pinned here because these are persisted wire values the frontend must not
      // invent or rename.
      expect(TRIGGERS.map(({ id }) => id)).toEqual([
        'deployment_requested',
        'environment_advanced',
        'deployment_promoted',
        'project.before_settings_update',
        'project.after_create',
        'project.after_transfer',
      ]);
    });

    // The ADR makes the periodic drift check author-facing
    // (https://gitlab.com/gitlab-org/architecture/govern/design-doc/-/merge_requests/28),
    // but the gem's authoring catalogue omits it deliberately, so the API refuses it as a
    // `trigger_type`. Presenting it would offer a trigger no policy can be saved against.
    it('presents no trigger the catalogue refuses to author', () => {
      expect(TRIGGERS.map(({ id }) => id)).not.toContain('project.scheduled_settings_drift_check');
    });

    // It is still recorded on every evaluation the daily sweep produces, so a surface
    // rendering one needs a label for it. gem_parity_spec pins this to the gem's TYPES.
    it('presents the drift check as a recorded trigger instead', () => {
      expect(RECORDED_TRIGGERS.map(({ id }) => id)).toEqual([
        'project.scheduled_settings_drift_check',
      ]);
    });

    it('ships the backend rules', () => {
      // These are Gitlab::PolicyStore::Rules::ALL in the gitlab-policy-store gem, pinned
      // here because they are persisted wire values the frontend must not invent or rename.
      expect(RULES.map(({ id }) => id)).toEqual([
        'custom',
        'calendar',
        'environment',
        'setting_validation',
      ]);
    });

    it('ships the enforcement actions and the compliance ones', () => {
      // All four are Gitlab::PolicyStore::Actions::ALL in the gitlab-policy-store gem, which
      // the write endpoints constrain against. These are persisted wire values the frontend
      // must not invent or rename.
      expect(ACTIONS.map(({ id }) => id)).toEqual([
        'block',
        'require_approval',
        'log_audit_trail',
        'set_setting',
      ]);
    });

    // The engine runs an observing action in every mode and a state-changing one only in
    // enforce mode, so an action that stopped being fieldless would be configuration the
    // author sets and no executor reads.
    it('gives the audit action no fields, because the executor reads the decision', () => {
      const audit = ACTIONS.find(({ id }) => id === 'log_audit_trail');

      expect(audit.fields).toEqual([]);
    });

    it('lets an event trigger be answered with the audit action', () => {
      const audit = ACTIONS.find(({ id }) => id === 'log_audit_trail');

      expect(
        actionAllowedFor({ id: 'project.after_create', kind: TRIGGER_KIND_EVENT }, audit),
      ).toBe(true);
    });

    it('pins the block action field keys, which are the persisted wire shape', () => {
      // The keys live inside the persisted action `value`, so renaming one changes what the
      // engine is handed. It reads the message from `message`, falling back to the retired
      // `blockMessage`. See https://gitlab.com/gitlab-org/gitlab/-/issues/628712.
      const block = ACTIONS.find(({ id }) => id === 'block');

      expect(block.fields.map(({ key }) => key)).toEqual(['message']);
    });

    it('has no warn action, because warn is an enforcement mode', () => {
      expect(ACTIONS.map(({ id }) => id)).not.toContain('warn');
    });

    // A trigger's GOVERN-016 kind and an action's blocking flag together decide which
    // pairings the editor offers, so an entry missing either silently widens or narrows what
    // an author can build. Both must be declared, and the kind of each trigger is pinned
    // because getting one wrong is invisible until a policy is saved and refused.
    it('pins which triggers are asked before the change and which are told after', () => {
      // Literals rather than the constants, so a mistyped constant cannot agree with itself.
      // The spellings are the ADR's: the registry sends these values once it exposes `kind`,
      // and a kind this catalog does not recognise silently allows every pairing again.
      expect(Object.fromEntries(TRIGGERS.map(({ id, kind }) => [id, kind]))).toEqual({
        deployment_requested: 'gate',
        environment_advanced: 'gate',
        deployment_promoted: 'gate',
        'project.before_settings_update': 'gate',
        'project.after_create': 'event',
        'project.after_transfer': 'event',
      });
    });

    it('pins which actions stop the change and which do not', () => {
      // Flipping one of these silently changes the triggers an action is offered for.
      expect(Object.fromEntries(ACTIONS.map(({ id, blocking }) => [id, blocking]))).toStrictEqual({
        block: true,
        require_approval: true,
        log_audit_trail: false,
        set_setting: false,
      });
    });

    // Every trigger needs at least one action it allows, or an author who picks it is offered
    // an empty action list with nothing explaining why. That was the state of both event
    // triggers before `set_setting` existed, and no spec failed; it reopens if the
    // last non-blocking action is removed or a later trigger kind rules more out.
    it.each(TRIGGERS.map((trigger) => [trigger.id, trigger]))(
      'offers at least one action for the %s trigger',
      (_, trigger) => {
        expect(ACTIONS.filter((action) => actionAllowedFor(trigger, action))).not.toHaveLength(0);
      },
    );

    it('declares the rule that supplies a fieldless action its configuration', () => {
      // `set_setting` carries no fields of its own, so the policy is incomplete
      // without the rule naming the setting. See `actionRuleBlockers` in validation.js.
      const setSetting = ACTIONS.find(({ id }) => id === 'set_setting');

      expect(setSetting.requiresRule).toBe('setting_validation');
      expect(RULES.map(({ id }) => id)).toContain(setSetting.requiresRule);
    });

    it('names the Rego rule `custom`, the value a saved policy persists', () => {
      // The id is a persisted wire value: the gem's RuleTranspiler and
      // PolicyRepository#authored_rego_rule? both dispatch on `rule['type'] == 'custom'`, and
      // nothing migrates stored rules, so renaming it breaks every policy already saved.
      expect(RULES.map(({ id }) => id)).toContain('custom');
      expect(RULES.map(({ id }) => id)).not.toContain('rego');
    });
  });
});

// The store rejects a custom rule whose Rego does not open with
// `package governance`, so a template without it can never be saved.
describe('rego templates', () => {
  it.each(REGO_TEMPLATES.map(({ id, rego }) => [id, rego]))(
    'the %s template declares the governance package first',
    (id, rego) => {
      expect(firstStatement(rego)).toBe('package governance');
    },
  );
});
