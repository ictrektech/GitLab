import { GlFormRadioGroup } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import AdvancedConfigurationTable from 'ee/security_configuration/components/scan_profiles/advanced_configuration_table.vue';
import StringListTokenSelector from 'ee/security_configuration/components/scan_profiles/string_list_token_selector.vue';
import {
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_NUMBER,
  VALUE_TYPE_STRING_LIST,
} from 'ee/security_configuration/components/scan_profiles/variable_definitions';

describe('AdvancedConfigurationTable', () => {
  let wrapper;

  const sharedRow = {
    setting: 'excludedPaths',
    value: 'spec/,tmp/',
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: 'spec/,tmp/' },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: 'spec/,tmp/' },
    ],
  };

  const varyingRow = {
    setting: 'historicScan',
    varies: true,
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: 'Yes' },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: 'No' },
    ],
  };

  const booleanRow = {
    setting: 'historicScan',
    value: true,
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: true },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: true },
    ],
  };

  const enumRow = {
    setting: 'imageSuffix',
    value: '-fips',
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: '-fips' },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: '-fips' },
    ],
  };

  const stringListRow = {
    setting: 'excludedPaths',
    varies: true,
    triggerValues: [
      { triggerType: 'MERGE_REQUEST_PIPELINE', value: ['spec/'] },
      { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: ['spec/', 'tmp/'] },
    ],
  };

  const variableDefinitions = {
    historicScan: { valueType: VALUE_TYPE_BOOLEAN },
    imageSuffix: {
      valueType: VALUE_TYPE_ENUM,
      options: [
        { value: '', text: 'Default' },
        { value: '-fips', text: 'FIPS' },
      ],
    },
    excludedPaths: { valueType: VALUE_TYPE_STRING_LIST },
    apiTimeout: { valueType: VALUE_TYPE_NUMBER, min: 5, max: 300 },
  };

  const numberRow = (value) => ({
    setting: 'apiTimeout',
    value,
    triggerValues: [{ triggerType: 'MERGE_REQUEST_PIPELINE', value }],
  });

  const sharedTriggerValues = [
    'Merge Request Pipelines',
    'spec/,tmp/',
    'Branch pipelines (default only)',
    'spec/,tmp/',
  ];

  const varyingTriggerValues = [
    'Merge Request Pipelines',
    'Yes',
    'Branch pipelines (default only)',
    'No',
  ];

  const createComponent = (rows, { editable = false, variableDefinitions: defs = {} } = {}) => {
    wrapper = mountExtended(AdvancedConfigurationTable, {
      propsData: {
        caption: 'Settings that apply across this profile',
        rows,
        editable,
        variableDefinitions: defs,
      },
    });
  };

  const findVariableRow = () => wrapper.find('tbody tr:not(.b-table-details)');
  const findToggle = () => findVariableRow().find('button');
  const findVariableCell = () => findVariableRow().findAll('td').at(1);
  const findValueCell = () => findVariableRow().findAll('td').at(2);
  const findTriggerValues = () =>
    wrapper
      .findByTestId('trigger-values')
      .findAll('span')
      .wrappers.map((value) => value.text());
  const findTriggerValueInput = (setting, triggerType) =>
    wrapper.findByTestId(`advanced-configuration-value-input-${setting}-${triggerType}`);
  const findTriggerRemoveButton = (setting, triggerType) =>
    wrapper.findByTestId(`advanced-configuration-remove-button-${setting}-${triggerType}`);

  it('shows a value shared by every trigger', () => {
    createComponent([sharedRow]);

    expect(findVariableCell().text()).toBe('excludedPaths');
    expect(findValueCell().text()).toBe('spec/,tmp/');
  });

  it('shows that a value differs by trigger', () => {
    createComponent([varyingRow]);

    expect(findVariableCell().text()).toBe('historicScan');
    expect(findValueCell().text()).toBe('Differs by trigger');
  });

  it('shows a boolean value as its Enabled/Disabled label rather than raw true/false', () => {
    createComponent([booleanRow], { variableDefinitions });

    expect(findValueCell().text()).toBe('Enabled');
  });

  it('shows an enum value as its option label rather than the raw value', () => {
    createComponent([enumRow], { variableDefinitions });

    expect(findValueCell().text()).toBe('FIPS');
  });

  it('shows the Default label for an enum explicitly set to the empty-string option', () => {
    createComponent([{ ...enumRow, value: '', triggerValues: [] }], { variableDefinitions });

    expect(findValueCell().text()).toBe('Default');
  });

  it.each`
    description  | row           | expected
    ${'shared'}  | ${sharedRow}  | ${sharedTriggerValues}
    ${'varying'} | ${varyingRow} | ${varyingTriggerValues}
  `('shows a value per trigger in a $description row', async ({ row, expected }) => {
    createComponent([row]);

    await findToggle().trigger('click');

    expect(findTriggerValues()).toEqual(expected);
  });

  describe('when editable', () => {
    it('shows an input per trigger for a varying value once expanded', async () => {
      createComponent([varyingRow], { editable: true });
      await findToggle().trigger('click');

      expect(findTriggerValueInput('historicScan', 'MERGE_REQUEST_PIPELINE').element.value).toBe(
        'Yes',
      );
      expect(findTriggerValueInput('historicScan', 'DEFAULT_BRANCH_PIPELINE').element.value).toBe(
        'No',
      );
    });

    it('shows an empty, editable field for a trigger with no value yet, rather than omitting it', async () => {
      createComponent(
        [
          {
            setting: 'secureAnalyzersPrefix',
            varies: true,
            triggerValues: [
              { triggerType: 'MERGE_REQUEST_PIPELINE', value: 'registry.example.com' },
              { triggerType: 'DEFAULT_BRANCH_PIPELINE', value: null },
            ],
          },
        ],
        { editable: true },
      );
      await findToggle().trigger('click');

      expect(
        findTriggerValueInput('secureAnalyzersPrefix', 'DEFAULT_BRANCH_PIPELINE').element.value,
      ).toBe('');

      // Not setValue(): it also triggers `change` under Vue 3's test-utils, which would double
      // the emit alongside the explicit trigger below (Vue 2's test-utils doesn't).
      findTriggerValueInput('secureAnalyzersPrefix', 'DEFAULT_BRANCH_PIPELINE').element.value =
        'registry.example.com';
      await findTriggerValueInput('secureAnalyzersPrefix', 'DEFAULT_BRANCH_PIPELINE').trigger(
        'change',
      );

      expect(wrapper.emitted('update-value')).toEqual([
        [
          {
            setting: 'secureAnalyzersPrefix',
            triggerType: 'DEFAULT_BRANCH_PIPELINE',
            value: 'registry.example.com',
          },
        ],
      ]);
    });

    it('emits update-value for just that trigger when its value changes', async () => {
      createComponent([varyingRow], { editable: true });
      await findToggle().trigger('click');

      findTriggerValueInput('historicScan', 'MERGE_REQUEST_PIPELINE').element.value = 'No';
      await findTriggerValueInput('historicScan', 'MERGE_REQUEST_PIPELINE').trigger('change');

      expect(wrapper.emitted('update-value')).toEqual([
        [{ setting: 'historicScan', triggerType: 'MERGE_REQUEST_PIPELINE', value: 'No' }],
      ]);
    });

    it('gives each field an aria-label combining the variable label and the trigger name, so identical trigger names across expanded rows stay distinguishable', async () => {
      createComponent([varyingRow], {
        editable: true,
        variableDefinitions: { historicScan: { label: 'Historic scan' } },
      });
      await findToggle().trigger('click');

      expect(
        findTriggerValueInput('historicScan', 'MERGE_REQUEST_PIPELINE').attributes('aria-label'),
      ).toBe('Historic scan for Merge Request Pipelines');
      expect(
        findTriggerValueInput('historicScan', 'DEFAULT_BRANCH_PIPELINE').attributes('aria-label'),
      ).toBe('Historic scan for Branch pipelines (default only)');
    });

    describe('when the setting is boolean', () => {
      it('shows a radio group per trigger once expanded', async () => {
        createComponent([booleanRow], { editable: true, variableDefinitions });
        await findToggle().trigger('click');

        const triggerRadioGroups = wrapper.findAllComponents(GlFormRadioGroup);
        expect(triggerRadioGroups.at(0).props('checked')).toBe(true);
        expect(triggerRadioGroups.at(1).props('checked')).toBe(true);
      });

      it('emits update-value for just that trigger when its radio group changes', async () => {
        createComponent([booleanRow], { editable: true, variableDefinitions });
        await findToggle().trigger('click');

        wrapper.findAllComponents(GlFormRadioGroup).at(0).vm.$emit('input', false);

        expect(wrapper.emitted('update-value')).toEqual([
          [{ setting: 'historicScan', triggerType: 'MERGE_REQUEST_PIPELINE', value: false }],
        ]);
      });
    });

    describe('when the setting is a stringList', () => {
      const findTokenSelectors = () => wrapper.findAllComponents(StringListTokenSelector);

      it('shows a token selector per trigger', async () => {
        createComponent([stringListRow], { editable: true, variableDefinitions });
        await findToggle().trigger('click');

        expect(findTokenSelectors().wrappers.map((selector) => selector.props('value'))).toEqual([
          ['spec/'],
          ['spec/', 'tmp/'],
        ]);
      });

      it('emits update-value with the new array', async () => {
        createComponent([stringListRow], { editable: true, variableDefinitions });
        await findToggle().trigger('click');

        findTokenSelectors().at(0).vm.$emit('input', ['spec/**', 'fixtures/**']);

        expect(wrapper.emitted('update-value')).toEqual([
          [
            {
              setting: 'excludedPaths',
              triggerType: 'MERGE_REQUEST_PIPELINE',
              value: ['spec/**', 'fixtures/**'],
            },
          ],
        ]);
      });
    });

    describe('with an invalid number value', () => {
      const findApiTimeoutInput = () =>
        findTriggerValueInput('apiTimeout', 'MERGE_REQUEST_PIPELINE');

      const changeApiTimeout = async (value) => {
        findApiTimeoutInput().element.value = value;
        await findApiTimeoutInput().trigger('change');
        await wrapper.setProps({ rows: [numberRow(value)] });
      };

      it('keeps a loaded row open with its toggle disabled', () => {
        createComponent([numberRow('1.5')], { editable: true, variableDefinitions });

        expect(findApiTimeoutInput().exists()).toBe(true);
        expect(findToggle().attributes('aria-expanded')).toBe('true');
        expect(findToggle().attributes('aria-disabled')).toBe('true');
      });

      it('keeps the row open after an invalid value', async () => {
        createComponent([numberRow('30')], { editable: true, variableDefinitions });
        await findToggle().trigger('click');

        await changeApiTimeout('1.5');

        expect(findApiTimeoutInput().exists()).toBe(true);
        expect(findToggle().attributes('aria-disabled')).toBe('true');
      });

      it('enables the toggle and keeps the row open', async () => {
        createComponent([numberRow('1.5')], { editable: true, variableDefinitions });

        await changeApiTimeout('30');

        expect(findApiTimeoutInput().exists()).toBe(true);
        expect(findToggle().attributes('aria-expanded')).toBe('true');
        expect(findToggle().attributes('aria-disabled')).toBeUndefined();
      });
    });

    describe('remove button', () => {
      it('emits update-value with a null value for just that trigger in the expanded view', async () => {
        createComponent([varyingRow], { editable: true });
        await findToggle().trigger('click');

        await findTriggerRemoveButton('historicScan', 'MERGE_REQUEST_PIPELINE').trigger('click');

        expect(wrapper.emitted('update-value')).toEqual([
          [{ setting: 'historicScan', triggerType: 'MERGE_REQUEST_PIPELINE', value: null }],
        ]);
      });
    });
  });
});
