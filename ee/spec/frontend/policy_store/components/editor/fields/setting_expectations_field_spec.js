import { mountExtended } from 'helpers/vue_test_utils_helper';
import { RULES, RULE_SETTING_VALIDATION } from 'ee/policy_store/catalog/rules';
import { SETTINGS, SETTINGS_BY_ID } from 'ee/policy_store/catalog/settings';
import SettingExpectationsField from 'ee/policy_store/components/editor/fields/setting_expectations_field.vue';

describe('SettingExpectationsField', () => {
  let wrapper;

  const BOOLEAN = SETTINGS_BY_ID.request_access_enabled;
  const RESTRICTED_BOOLEAN = SETTINGS_BY_ID.only_allow_merge_if_pipeline_succeeds;
  const STRING = SETTINGS_BY_ID.squash_option;

  // The catalog's own field, not a stand-in: the choices and the entries each row resolves
  // its permitted values against are declared there, so a spec with its own field would
  // pass while the wired-up control drew nothing.
  const field = RULES.find(({ id }) => id === RULE_SETTING_VALIDATION).fields[0];

  const createComponent = ({ value = [] } = {}) => {
    wrapper = mountExtended(SettingExpectationsField, { propsData: { field, value } });
  };

  const findRows = () => wrapper.findAllByTestId('expectation-row');
  const findSettingSelect = (index = 0) => wrapper.findAllByTestId('expectation-setting').at(index);
  const findValueSelect = (index = 0) => wrapper.findAllByTestId('expectation-value').at(index);
  const optionTexts = (select) => select.findAll('option').wrappers.map((option) => option.text());
  const lastInput = () => wrapper.emitted('input').at(-1)[0];

  it('renders one empty row when nothing is authored yet, without emitting it', () => {
    createComponent();

    expect(findRows()).toHaveLength(1);
    expect(findSettingSelect().element.value).toBe('');
    expect(wrapper.emitted('input')).toBeUndefined();
  });

  it('offers every setting the catalog knows, behind a placeholder', () => {
    createComponent();

    expect(optionTexts(findSettingSelect())).toEqual([
      'Select a setting',
      ...SETTINGS.map(({ name }) => name),
    ]);
  });

  it('renders one row per authored pair', () => {
    createComponent({
      value: [
        { setting: BOOLEAN.id, expected: true },
        { setting: STRING.id, expected: 'never' },
      ],
    });

    expect(findRows()).toHaveLength(2);
    expect(findSettingSelect(1).element.value).toBe(STRING.id);
  });

  describe('the value control', () => {
    it('draws nothing until the row names a setting', () => {
      createComponent();

      expect(wrapper.findByTestId('expectation-value').exists()).toBe(false);
    });

    it('offers both ways round for an unrestricted boolean', () => {
      createComponent({ value: [{ setting: BOOLEAN.id, expected: null }] });

      expect(optionTexts(findValueSelect())).toEqual([
        'Select a required value',
        'Enabled',
        'Disabled',
      ]);
    });

    it('offers every declared value for a string setting', () => {
      createComponent({ value: [{ setting: STRING.id, expected: null }] });

      expect(optionTexts(findValueSelect())).toEqual([
        'Select a required value',
        'Never',
        'Always',
        'Default on',
        'Default off',
      ]);
    });

    // The whole point of the narrowing: `false` here is a value an upper level can still
    // override, which the rule transpiler refuses. An author must not be able to pick it.
    it('offers a restricted setting only the value a policy may require', () => {
      createComponent({ value: [{ setting: RESTRICTED_BOOLEAN.id, expected: null }] });

      expect(optionTexts(findValueSelect())).toEqual(['Select a required value', 'Enabled']);
    });

    it('emits a boolean, not the string the option carries', async () => {
      createComponent({ value: [{ setting: BOOLEAN.id, expected: null }] });

      await findValueSelect().findAll('option').at(1).setSelected();

      expect(lastInput()).toEqual([{ setting: BOOLEAN.id, expected: true }]);
    });

    it('emits null when the value is cleared back to the placeholder', async () => {
      createComponent({ value: [{ setting: BOOLEAN.id, expected: false }] });

      await findValueSelect().findAll('option').at(0).setSelected();

      expect(lastInput()).toEqual([{ setting: BOOLEAN.id, expected: null }]);
    });

    it('selects a value the catalog still permits', () => {
      createComponent({ value: [{ setting: BOOLEAN.id, expected: false }] });

      expect(findValueSelect().element.value).toBe('false');
    });

    // The stored value belongs to a setting that is no longer selected, or to a catalog
    // that has since retyped this one. Showing it would read as an answer.
    it('selects nothing for a value the catalog no longer permits', () => {
      createComponent({ value: [{ setting: RESTRICTED_BOOLEAN.id, expected: false }] });

      expect(findValueSelect().element.value).toBe('');
    });
  });

  // A policy written through the API, or one the catalog narrowed after it was saved, can
  // name a setting the catalog does not offer. Showing an empty dropdown would read as a
  // row the author never filled in, and they would re-save the id without knowing.
  describe('a setting the catalog does not know', () => {
    const unknown = () => createComponent({ value: [{ setting: 'gone', expected: true }] });

    it('still names the stored id, as the selected option', () => {
      unknown();

      expect(findSettingSelect().element.value).toBe('gone');
      expect(optionTexts(findSettingSelect())).toContain('gone');
    });

    it('offers it as a dead end rather than a choice', () => {
      unknown();

      expect(findSettingSelect().find('option[value="gone"]').attributes('disabled')).toBeDefined();
    });

    it('names the stored id in the row controls', () => {
      unknown();

      expect(findSettingSelect().attributes('aria-label')).toBe('Project setting gone');
    });
  });

  // The author is told which of their rows offers a single value, and why. Nothing else
  // on screen explains why one row's value list is shorter than another's.
  describe('the restriction note', () => {
    it('names every restricted setting in play', () => {
      createComponent({
        value: [
          { setting: RESTRICTED_BOOLEAN.id, expected: true },
          { setting: SETTINGS_BY_ID.allow_author_approval.id, expected: false },
        ],
      });

      expect(wrapper.findByTestId('restriction-note').text()).toBe(
        `${RESTRICTED_BOOLEAN.name} and ${SETTINGS_BY_ID.allow_author_approval.name}: a group or instance setting can still override the values not offered here, so only these values can be required.`,
      );
    });

    // Two rows may name the same setting while the author is still editing; naming it
    // twice would read as two different restrictions.
    it('names a setting once however many rows pin it', () => {
      createComponent({
        value: [
          { setting: RESTRICTED_BOOLEAN.id, expected: true },
          { setting: RESTRICTED_BOOLEAN.id, expected: true },
        ],
      });

      expect(wrapper.findByTestId('restriction-note').text()).toBe(
        `${RESTRICTED_BOOLEAN.name}: a group or instance setting can still override the values not offered here, so only these values can be required.`,
      );
    });

    // The note exists to explain a one-option select, which is invisible to a screen
    // reader user unless the select points at it.
    it("describes a restricted row's value control", () => {
      createComponent({
        value: [
          { setting: RESTRICTED_BOOLEAN.id, expected: true },
          { setting: BOOLEAN.id, expected: true },
        ],
      });

      expect(findValueSelect(0).attributes('aria-describedby')).toBe(
        wrapper.findByTestId('restriction-note').attributes('id'),
      );
      expect(findValueSelect(1).attributes('aria-describedby')).toBeUndefined();
    });

    it('stays hidden while no row names a restricted setting', () => {
      createComponent({ value: [{ setting: BOOLEAN.id, expected: true }] });

      expect(wrapper.findByTestId('restriction-note').exists()).toBe(false);
    });
  });

  // The old value belongs to the old setting's domain, and a value the new setting does
  // not permit is one the rule transpiler refuses.
  it('clears the stale value when a row changes setting', async () => {
    createComponent({ value: [{ setting: BOOLEAN.id, expected: true }] });

    await findSettingSelect().findAll('option').at(1).setSelected();

    expect(lastInput()).toEqual([{ setting: SETTINGS[0].id, expected: null }]);
  });

  it('names the setting in each row control, so the rows are tellable apart', () => {
    createComponent({
      value: [
        { setting: BOOLEAN.id, expected: true },
        { setting: STRING.id, expected: 'never' },
      ],
    });

    expect(wrapper.findAllByTestId('expectation-remove').at(1).attributes('aria-label')).toBe(
      `Remove setting ${STRING.name}`,
    );
    expect(findSettingSelect(1).attributes('aria-label')).toBe(`Project setting ${STRING.name}`);
    expect(findValueSelect(1).attributes('aria-label')).toBe(`Required value for ${STRING.name}`);
  });

  // The row is a placeholder the model does not hold, so removing it would re-render the
  // identical row and look broken.
  it('offers no remove button while the only row is the unauthored one', () => {
    createComponent();

    expect(wrapper.findByTestId('expectation-remove').exists()).toBe(false);
  });

  it('adds an empty row', async () => {
    createComponent({ value: [{ setting: BOOLEAN.id, expected: true }] });

    await wrapper.findByTestId('expectation-add').trigger('click');

    expect(lastInput()).toEqual([
      { setting: BOOLEAN.id, expected: true },
      { setting: '', expected: null },
    ]);
  });

  it('removes the row it is asked to remove', async () => {
    createComponent({
      value: [
        { setting: BOOLEAN.id, expected: true },
        { setting: STRING.id, expected: 'never' },
      ],
    });

    await wrapper.findAllByTestId('expectation-remove').at(0).trigger('click');

    expect(lastInput()).toEqual([{ setting: STRING.id, expected: 'never' }]);
  });

  it('keeps the surviving row intact after a removal', async () => {
    createComponent({
      value: [
        { setting: BOOLEAN.id, expected: true },
        { setting: STRING.id, expected: 'never' },
      ],
    });

    await wrapper.findAllByTestId('expectation-remove').at(0).trigger('click');

    const emissions = wrapper.emitted('input').length;

    await wrapper.setProps({ value: lastInput() });

    // A second emission here IS the bug: it would be the surviving row reporting that the
    // setting it was handed changed, and wiping the answer along with it.
    expect(wrapper.emitted('input')).toHaveLength(emissions);
    expect(lastInput()).toEqual([{ setting: STRING.id, expected: 'never' }]);
  });
});
