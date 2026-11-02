import {
  blank,
  configItemsFor,
  hiddenFieldKeys,
  visibleFields,
} from 'ee/policy_store/catalog/helpers';
import { RULES, RULE_SETTING_VALIDATION } from 'ee/policy_store/catalog/rules';

describe('blank', () => {
  // `false` and `0` are answers a policy can require, so they must not read as absent.
  it.each([false, 0, 'yes', ['a'], { a: 1 }])('treats %p as an answer', (value) => {
    expect(blank(value)).toBe(false);
  });

  it.each([undefined, null, '', '   ', [], {}])('treats %p as no answer', (value) => {
    expect(blank(value)).toBe(true);
  });
});

describe('visibleFields', () => {
  const plain = { key: 'mode', type: 'select', label: 'Mode' };
  const conditional = {
    key: 'names',
    type: 'text',
    label: 'Names',
    showIf: { key: 'mode', in: ['detailed'] },
  };
  const fields = [plain, conditional];

  it('keeps a field that declares no showIf', () => {
    expect(visibleFields([plain], {})).toEqual([plain]);
  });

  it('hides a conditional field while the sibling does not match', () => {
    expect(visibleFields(fields, { mode: 'simple' })).toEqual([plain]);
  });

  it('shows a conditional field once the sibling matches', () => {
    expect(visibleFields(fields, { mode: 'detailed' })).toEqual(fields);
  });

  it('hides a conditional field while the sibling is unanswered', () => {
    expect(visibleFields(fields, {})).toEqual([plain]);
  });

  it('matches any of several listed values', () => {
    const anyOf = [{ ...conditional, showIf: { key: 'mode', in: ['warn', 'enforce'] } }];

    expect(visibleFields(anyOf, { mode: 'warn' })).toHaveLength(1);
    expect(visibleFields(anyOf, { mode: 'enforce' })).toHaveLength(1);
    expect(visibleFields(anyOf, { mode: 'audit' })).toHaveLength(0);
  });

  it('matches a boolean sibling by identity', () => {
    const onChecked = [{ ...conditional, showIf: { key: 'mode', in: [true] } }];

    expect(visibleFields(onChecked, { mode: true })).toHaveLength(1);
    expect(visibleFields(onChecked, { mode: false })).toHaveLength(0);
  });

  // Documented limits, guarded in catalog_spec so no entry can rely on them.
  describe('limits the catalog guard enforces', () => {
    it('never matches an array-valued sibling, since comparison is by identity', () => {
      const onArray = [{ ...conditional, showIf: { key: 'tiers', in: [['production']] } }];

      expect(visibleFields(onArray, { tiers: ['production'] })).toHaveLength(0);
    });

    it('resolves a chained showIf against the raw config, not the parent visibility', () => {
      const chained = [
        { key: 'a', type: 'select', label: 'A' },
        { key: 'b', type: 'select', label: 'B', showIf: { key: 'a', in: ['yes'] } },
        { key: 'c', type: 'text', label: 'C', showIf: { key: 'b', in: ['deep'] } },
      ];

      // `b` is hidden, yet a stale `b` still reveals `c` — the single-pass behaviour.
      expect(visibleFields(chained, { a: 'no', b: 'deep' }).map(({ key }) => key)).toEqual([
        'a',
        'c',
      ]);
    });
  });

  it('defaults to an empty list when given no fields', () => {
    expect(visibleFields()).toEqual([]);
  });
});

describe('hiddenFieldKeys', () => {
  const plain = { key: 'mode', type: 'select', label: 'Mode' };
  const conditional = {
    key: 'names',
    type: 'text',
    label: 'Names',
    showIf: { key: 'mode', in: ['detailed'] },
  };
  const fields = [plain, conditional];

  it('is empty when every field is visible', () => {
    expect(hiddenFieldKeys(fields, { mode: 'detailed' })).toEqual([]);
  });

  it('names the fields a showIf currently hides', () => {
    expect(hiddenFieldKeys(fields, { mode: 'simple' })).toEqual(['names']);
  });

  it('is empty for an entry that declares no fields', () => {
    expect(hiddenFieldKeys(undefined, undefined)).toEqual([]);
  });
});

describe('configItemsFor', () => {
  const entry = {
    fields: [
      { key: 'mode', type: 'select', label: 'Mode', options: [{ id: 'simple', label: 'Simple' }] },
      {
        key: 'names',
        type: 'text',
        label: 'Names',
        showIf: { key: 'mode', in: ['detailed'] },
      },
    ],
  };

  // The read-only views must show what the editor showed, or an author sees a value on
  // the detail page for a control the form never rendered.
  it('omits a hidden field even when the config still carries its value', () => {
    const items = configItemsFor(entry, { mode: 'simple', names: 'left over' });

    expect(items.map(({ key }) => key)).toEqual(['mode']);
  });

  it('includes the field once it is revealed', () => {
    const items = configItemsFor(entry, { mode: 'detailed', names: 'prod' });

    expect(items.map(({ key }) => key)).toEqual(['mode', 'names']);
  });
});

describe('configItemsFor with a setting_expectations field', () => {
  // The catalog's own field: it carries the settings the summary resolves labels from, and
  // a stand-in without them would pass on the raw ids this test exists to rule out.
  const field = RULES.find(({ id }) => id === RULE_SETTING_VALIDATION).fields[0];
  const entry = { fields: [field] };

  const itemsFor = (expectations) => configItemsFor(entry, { expectations });

  // Every other field type summarises through a label; a stored attribute name or a raw
  // `true` here would read as a bug to anyone opening a saved policy.
  it('summarises each row through the catalog, not the stored id and value', () => {
    const items = itemsFor([
      { setting: 'secret_push_protection_enabled', expected: true },
      { setting: 'squash_option', expected: 'default_on' },
    ]);

    expect(items).toEqual([
      {
        key: 'expectations',
        label: field.label,
        code: false,
        value: 'Secret push protection = Enabled, Squash commits when merging = Default on',
      },
    ]);
  });

  // The catalog narrowed this setting to `true` after the policy was saved, so the stored
  // value resolves to no option. Dropping the row would hide a rule that still exists.
  it('falls back to the stored value when the catalog no longer offers it', () => {
    expect(
      itemsFor([{ setting: 'only_allow_merge_if_pipeline_succeeds', expected: false }])[0].value,
    ).toBe('Pipelines must succeed = Disabled');
  });

  // A setting the catalog no longer knows still shows, the same way a dropped rule id does.
  it('falls back to the stored id for a setting the catalog does not know', () => {
    expect(itemsFor([{ setting: 'gone', expected: true }])[0].value).toBe('gone = Enabled');
  });

  // A row the author added but never filled is not policy content, and the serializer
  // drops it, so the read-only view must not claim it either.
  it.each([
    ['no setting', { setting: '', expected: null }],
    ['no value', { setting: 'secret_push_protection_enabled', expected: null }],
  ])('drops a row with %s', (_, row) => {
    expect(itemsFor([row])).toEqual([]);
  });
});
