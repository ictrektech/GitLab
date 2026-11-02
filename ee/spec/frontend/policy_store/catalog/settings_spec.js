import {
  SETTING_VALUE_TYPE_BOOLEAN,
  SETTING_VALUE_TYPE_STRING,
} from 'ee/policy_store/components/editor/constants';
import { RULES } from 'ee/policy_store/catalog/rules';
import {
  SETTINGS,
  SETTINGS_BY_ID,
  SETTING_OPTIONS,
  VALUE_LABELS,
  isRestricted,
  labelForValue,
  promisableOptions,
} from 'ee/policy_store/catalog/settings';
import { ruleConfigBlockers } from 'ee/policy_store/catalog/validation';

const settingValidation = () => RULES.find(({ id }) => id === 'setting_validation');

const settingById = (id) => SETTINGS_BY_ID[id];

describe('policy store settings catalog', () => {
  it('ids every setting uniquely', () => {
    const ids = SETTINGS.map(({ id }) => id);

    expect(new Set(ids).size).toBe(ids.length);
  });

  it('gives every setting the contract Gitlab::PolicyStore::Settings defines', () => {
    SETTINGS.forEach((setting) => {
      expect(setting).toMatchObject({
        id: expect.any(String),
        name: expect.any(String),
        value_type: expect.any(String),
      });
    });
  });

  // The ids the merged evaluation context builder emits
  // (ee/lib/govern/policy_engine/project_settings_context.rb), which is also what the
  // served catalog lists. Save-time validation rejects any other id, so this list is a
  // claim about the backend rather than a sample: it changes by copying the catalog.
  it('offers exactly the settings the engine governs', () => {
    expect(SETTINGS.map(({ id }) => id)).toEqual([
      'visibility',
      'request_access_enabled',
      'only_allow_merge_if_pipeline_succeeds',
      'only_allow_merge_if_all_discussions_are_resolved',
      'remove_source_branch_after_merge',
      'squash_option',
      'allow_author_approval',
      'allow_committer_approval',
      'allow_overrides_to_approver_list_per_merge_request',
      'retain_approvals_on_push',
      'keep_latest_artifact',
      'allow_fork_pipelines_to_run_in_parent_project',
      'pipeline_variables_minimum_override_role',
      'merge_requests_access_level',
      'builds_access_level',
      'forking_access_level',
      'secret_push_protection_enabled',
    ]);
  });

  // A row offers a select over the setting's permitted values and nothing else, so a
  // setting with no enumerable values would leave the row unanswerable. The contract's
  // third type, `integer`, is that case and has no entry yet.
  it('gives every setting enumerable values', () => {
    SETTINGS.forEach((setting) => {
      expect([SETTING_VALUE_TYPE_BOOLEAN, SETTING_VALUE_TYPE_STRING]).toContain(setting.value_type);
      expect(promisableOptions(setting).length).toBeGreaterThan(0);
    });
  });

  it('declares values for every string setting', () => {
    SETTINGS.filter(({ value_type: valueType }) => valueType === SETTING_VALUE_TYPE_STRING).forEach(
      ({ values }) => {
        expect(values.length).toBeGreaterThan(0);
      },
    );
  });

  // promisable_values is a subset of what the type allows, never a widening: a value
  // outside the type is one the transpiler refuses on type before it checks the value.
  it('keeps every promisable value within the values the setting allows', () => {
    SETTINGS.filter(isRestricted).forEach(
      ({ value_type: valueType, values, promisable_values: promisable }) => {
        const allowed = valueType === SETTING_VALUE_TYPE_BOOLEAN ? [true, false] : values;

        expect(allowed).toEqual(expect.arrayContaining(promisable));
      },
    );
  });

  describe('promisableOptions', () => {
    // The values an upper level can still override are the ones the rule transpiler
    // refuses, so a restricted setting must not offer them at all: offering them is the
    // defect this narrowing exists to fix.
    it('narrows a restricted setting to its promisable values', () => {
      expect(promisableOptions(settingById('only_allow_merge_if_pipeline_succeeds'))).toEqual([
        { id: true, label: 'Enabled' },
      ]);
      expect(promisableOptions(settingById('allow_author_approval'))).toEqual([
        { id: false, label: 'Disabled' },
      ]);
      expect(promisableOptions(settingById('visibility'))).toEqual([
        { id: 'private', label: 'Private' },
      ]);
    });

    it('offers both ways round for an unrestricted boolean', () => {
      expect(promisableOptions(settingById('request_access_enabled'))).toEqual([
        { id: true, label: 'Enabled' },
        { id: false, label: 'Disabled' },
      ]);
    });

    it('offers every declared value for an unrestricted string', () => {
      expect(promisableOptions(settingById('squash_option'))).toEqual([
        { id: 'never', label: 'Never' },
        { id: 'always', label: 'Always' },
        { id: 'default_on', label: 'Default on' },
        { id: 'default_off', label: 'Default off' },
      ]);
    });

    it('has nothing to offer for a setting it does not know', () => {
      expect(promisableOptions(undefined)).toBeUndefined();
    });
  });

  // A value the table does not know falls through to `humanize`, a machine transform, so
  // the author would read a translated setting name next to a raw English value.
  it('has translated wording for every value any setting declares', () => {
    const declared = SETTINGS.flatMap(({ value_type: valueType, values }) =>
      valueType === SETTING_VALUE_TYPE_BOOLEAN ? [true, false] : values,
    );

    expect(declared.filter((value) => !(String(value) in VALUE_LABELS))).toEqual([]);
  });

  describe('labelForValue', () => {
    it('writes a known value the way the table declares', () => {
      expect(labelForValue(true)).toBe('Enabled');
      expect(labelForValue('default_on')).toBe('Default on');
    });

    // The branch the test above proves never fires for today's catalog, which is exactly
    // why it needs its own case: the served catalog can gain a value before this file does.
    it('humanizes a value the table does not know', () => {
      expect(labelForValue('default_branch_only')).toBe('Default branch only');
    });
  });

  describe('derived shapes', () => {
    it('offers one choice per setting, named', () => {
      expect(SETTING_OPTIONS).toEqual(SETTINGS.map(({ id, name }) => ({ id, label: name })));
    });

    it('resolves each id back to its own entry', () => {
      SETTINGS.forEach((setting) => {
        expect(SETTINGS_BY_ID[setting.id]).toBe(setting);
      });
    });
  });

  describe('the setting_validation rule', () => {
    // The author edits every pair in one field; the serializer fans the rows out into one
    // persisted `{ setting, expected }` rule each.
    it('edits the pairs through a single expectations field', () => {
      expect(settingValidation().fields.map(({ key, type }) => [key, type])).toEqual([
        ['expectations', 'setting_expectations'],
      ]);
    });

    it('hands the rows the catalog they resolve against', () => {
      const [field] = settingValidation().fields;

      expect(field.options).toBe(SETTING_OPTIONS);
      expect(field.settings).toBe(SETTINGS_BY_ID);
    });

    it('blocks saving until a row names a setting and a required value', () => {
      const config = { expectations: [{ setting: 'secret_push_protection_enabled' }] };

      expect(
        ruleConfigBlockers(RULES, ['setting_validation'], { setting_validation: config }),
      ).toEqual(['Setting validation: Secret push protection needs a required value.']);
    });

    it('does not block once the value is answered', () => {
      const config = {
        expectations: [{ setting: 'secret_push_protection_enabled', expected: true }],
      };

      expect(
        ruleConfigBlockers(RULES, ['setting_validation'], { setting_validation: config }),
      ).toEqual([]);
    });
  });
});
