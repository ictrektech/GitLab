import { GlCollapsibleListbox, GlFormRadioGroup } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import AdvancedConfigurationValueField from 'ee/security_configuration/components/scan_profiles/advanced_configuration_value_field.vue';
import StringListTokenSelector from 'ee/security_configuration/components/scan_profiles/string_list_token_selector.vue';
import {
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
  VALUE_TYPE_NUMBER,
  VALUE_TYPE_STRING_LIST,
} from 'ee/security_configuration/components/scan_profiles/variable_definitions';

describe('AdvancedConfigurationValueField', () => {
  let wrapper;

  const enumOptions = [
    { value: '', text: 'Default' },
    { value: '-fips', text: 'FIPS' },
  ];

  const createComponent = (propsData = {}) => {
    wrapper = mountExtended(AdvancedConfigurationValueField, {
      propsData: {
        fieldLabel: 'Merge Request Pipelines',
        removeLabel: 'Remove historicScan',
        valueDataTestid: 'value-input',
        removeDataTestid: 'remove-button',
        ...propsData,
      },
    });
  };

  const findRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findSelect = () => wrapper.find('select');
  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findTokenSelector = () => wrapper.findComponent(StringListTokenSelector);
  const findInput = () => wrapper.find('input:not([type="radio"])');
  const findRemoveButton = () => wrapper.findByTestId('remove-button');

  it('defaults to a plain text input when no definition is given', () => {
    createComponent();

    expect(findInput().element.value).toBe('');
    expect(findInput().attributes('aria-label')).toBe('Merge Request Pipelines');
  });

  describe('boolean setting', () => {
    it('renders an Enabled/Disabled radio group reflecting the current value', () => {
      createComponent({ value: true, definition: { valueType: VALUE_TYPE_BOOLEAN } });

      expect(findRadioGroup().props()).toMatchObject({
        checked: true,
        options: [
          { value: true, text: 'Enabled' },
          { value: false, text: 'Disabled' },
        ],
      });
      expect(findRadioGroup().attributes('aria-label')).toBe('Merge Request Pipelines');
    });

    it('emits update with the new boolean when changed', () => {
      createComponent({ value: true, definition: { valueType: VALUE_TYPE_BOOLEAN } });

      findRadioGroup().vm.$emit('input', false);

      expect(wrapper.emitted('update')).toEqual([[false]]);
    });
  });

  describe('enum setting', () => {
    it('shows the current value selected', () => {
      createComponent({
        value: '-fips',
        definition: { valueType: VALUE_TYPE_ENUM, options: enumOptions },
      });

      expect(findSelect().element.value).toBe('-fips');
      expect(findSelect().attributes('aria-label')).toBe('Merge Request Pipelines');
    });

    it('adds a genuinely blank placeholder option instead of visually defaulting to the first one when unset', () => {
      createComponent({
        value: null,
        definition: { valueType: VALUE_TYPE_ENUM, options: enumOptions },
      });

      const optionTexts = findSelect()
        .findAll('option')
        .wrappers.map((option) => option.text());
      expect(optionTexts[0]).toBe('');
      expect(optionTexts).toEqual(['', 'Default', 'FIPS']);
    });

    it('does not add a placeholder once a value is set', () => {
      createComponent({
        value: '',
        definition: { valueType: VALUE_TYPE_ENUM, options: enumOptions },
      });

      const optionTexts = findSelect()
        .findAll('option')
        .wrappers.map((option) => option.text());
      expect(optionTexts).toEqual(['Default', 'FIPS']);
    });

    it('emits update with the newly selected option', async () => {
      createComponent({
        value: '',
        definition: { valueType: VALUE_TYPE_ENUM, options: enumOptions },
      });

      await findSelect().setValue('-fips');

      expect(wrapper.emitted('update')).toEqual([['-fips']]);
    });
  });

  describe('number setting', () => {
    const definition = { valueType: VALUE_TYPE_NUMBER, min: 5, max: 300 };

    it('renders a number input with the definition range', () => {
      createComponent({ value: 30, definition });

      expect(findInput().attributes()).toMatchObject({
        type: 'number',
        min: '5',
        max: '300',
        'aria-label': 'Merge Request Pipelines',
      });
      expect(findInput().element.value).toBe('30');
    });

    it('renders an empty input for an unset value', () => {
      createComponent({ value: null, definition });

      expect(findInput().element.value).toBe('');
    });

    it('emits update with the entered value', async () => {
      createComponent({ value: 30, definition });

      findInput().element.value = '60';
      await findInput().trigger('change');

      expect(wrapper.emitted('update')).toEqual([['60']]);
    });

    it.each(['500', '1.5'])('renders %s as invalid', (value) => {
      createComponent({ value, definition });

      expect(findInput().attributes('aria-invalid')).toBe('true');
    });

    it('shows the invalid feedback under the input', () => {
      createComponent({ value: '1.5', definition: { ...definition, label: 'API timeout' } });

      expect(wrapper.find('.invalid-feedback').text()).toBe(
        'API timeout must be a whole number from 5 to 300.',
      );
    });
  });

  describe('multiSelect setting', () => {
    const definition = {
      valueType: VALUE_TYPE_MULTI_SELECT,
      options: [
        { value: 'maven', text: 'Maven' },
        { value: 'gradle', text: 'Gradle' },
        { value: 'python', text: 'Python' },
      ],
      placeholder: 'Select jobs to skip',
    };

    it('shows the selected options in a multiple listbox', () => {
      createComponent({ value: ['python', 'maven'], definition });

      expect(findListbox().props()).toMatchObject({
        multiple: true,
        items: definition.options,
        selected: ['python', 'maven'],
        toggleText: 'Maven, Python',
      });
    });

    it('renders an empty selection for a null value', () => {
      createComponent({ value: null, definition });

      expect(findListbox().props()).toMatchObject({
        selected: [],
        toggleText: 'Select jobs to skip',
      });
    });

    it('passes the field label to the toggle', () => {
      createComponent({ value: ['maven'], definition });

      const [labelId, toggleId] = findListbox().props('toggleAriaLabelledBy').split(' ');
      expect(wrapper.find(`#${labelId}`).text()).toBe('Merge Request Pipelines');
      expect(toggleId).toBe(findListbox().props('toggleId'));
    });

    it('emits update with the new selection', () => {
      createComponent({ value: ['maven'], definition });

      findListbox().vm.$emit('select', ['maven', 'gradle']);

      expect(wrapper.emitted('update')).toEqual([[['maven', 'gradle']]]);
    });
  });

  describe('stringList setting', () => {
    it('shows the array as tokens', () => {
      createComponent({
        value: ['spec/', 'tmp/'],
        definition: { valueType: VALUE_TYPE_STRING_LIST },
      });

      expect(findTokenSelector().props()).toMatchObject({
        value: ['spec/', 'tmp/'],
        ariaLabel: 'Merge Request Pipelines',
        textInputAttrs: { 'data-testid': 'value-input' },
      });
    });

    it('emits update with the new array', () => {
      createComponent({
        value: ['spec/'],
        definition: { valueType: VALUE_TYPE_STRING_LIST },
      });

      findTokenSelector().vm.$emit('input', ['spec/', 'fixtures/**']);

      expect(wrapper.emitted('update')).toEqual([[['spec/', 'fixtures/**']]]);
    });
  });

  describe('remove button', () => {
    it('is always shown, using removeLabel as its aria-label', () => {
      createComponent();

      expect(findRemoveButton().exists()).toBe(true);
      expect(findRemoveButton().attributes('aria-label')).toBe('Remove historicScan');
    });

    it('emits update with null when clicked', async () => {
      createComponent({ value: 'registry.example.com' });

      await findRemoveButton().trigger('click');

      expect(wrapper.emitted('update')).toEqual([[null]]);
    });
  });
});
