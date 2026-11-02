import { GlTableLite } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import TriggerVariableTable from 'ee/security_configuration/components/scan_profiles/trigger_variable_table.vue';
import {
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
} from 'ee/security_configuration/components/scan_profiles/variable_definitions';

describe('TriggerVariableTable', () => {
  let wrapper;

  const createComponent = (propsData) => {
    wrapper = shallowMountExtended(TriggerVariableTable, { propsData });
  };

  const findTable = () => wrapper.findComponent(GlTableLite);

  it('renders the given rows with a setting/value aria-label for the trigger', () => {
    createComponent({
      triggerTitle: 'Merge Request Pipelines',
      rows: [
        { setting: 'historicScan', value: true },
        { setting: 'excludedPaths', value: ['spec/'] },
      ],
      variableDefinitions: {},
    });

    expect(findTable().props('items')).toEqual([
      { setting: 'historicScan', value: true },
      { setting: 'excludedPaths', value: ['spec/'] },
    ]);
    expect(findTable().attributes('aria-label')).toBe(
      'Analyzer settings for Merge Request Pipelines',
    );
  });

  it('renders no table when there are no rows', () => {
    createComponent({ triggerTitle: 'Merge Request Pipelines', rows: [], variableDefinitions: {} });

    expect(findTable().exists()).toBe(false);
  });

  describe('display labels', () => {
    const variableDefinitions = {
      historicScan: { valueType: VALUE_TYPE_BOOLEAN },
      imageSuffix: {
        valueType: VALUE_TYPE_ENUM,
        options: [
          { value: '', text: 'Default' },
          { value: '-fips', text: 'FIPS' },
        ],
      },
      disabledResolutionJobs: {
        valueType: VALUE_TYPE_MULTI_SELECT,
        options: [
          { value: 'maven', text: 'Maven' },
          { value: 'gradle', text: 'Gradle' },
        ],
      },
    };

    it('shows a boolean value as its Enabled/Disabled label rather than raw true/false', () => {
      wrapper = mountExtended(TriggerVariableTable, {
        propsData: {
          triggerTitle: 'Merge Request Pipelines',
          rows: [{ setting: 'historicScan', value: true }],
          variableDefinitions,
        },
      });

      expect(wrapper.text()).toContain('Enabled');
      expect(wrapper.text()).not.toContain('true');
    });

    it('shows an enum value as its option label rather than the raw value', () => {
      wrapper = mountExtended(TriggerVariableTable, {
        propsData: {
          triggerTitle: 'Merge Request Pipelines',
          rows: [{ setting: 'imageSuffix', value: '-fips' }],
          variableDefinitions,
        },
      });

      expect(wrapper.text()).toContain('FIPS');
    });

    it('shows multi-select labels joined by commas', () => {
      wrapper = mountExtended(TriggerVariableTable, {
        propsData: {
          triggerTitle: 'Merge Request Pipelines',
          rows: [{ setting: 'disabledResolutionJobs', value: ['maven', 'gradle'] }],
          variableDefinitions,
        },
      });

      expect(wrapper.text()).toContain('Maven, Gradle');
    });

    it('falls back to the raw value for a setting with no variable definition', () => {
      wrapper = mountExtended(TriggerVariableTable, {
        propsData: {
          triggerTitle: 'Merge Request Pipelines',
          rows: [{ setting: 'logOptions', value: '--since=1.year.ago' }],
          variableDefinitions,
        },
      });

      expect(wrapper.text()).toContain('--since=1.year.ago');
    });
  });
});
